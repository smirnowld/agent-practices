#!/bin/sh
# Session start output, in parts because a hook's output over 10,000 characters
# is saved to a file and shown as a 2,000-character preview
# (https://code.claude.com/docs/en/hooks). Keep every part under 9,500.
#   bindings (also the default with no argument): the plugin root and this
#     adapter's session bindings.
#   policy 1 / 2 / 3: the three parts of policy/AGENTS.md, split at the two
#     `## P` headings that make the largest part smallest.
# The policy parts print nothing when the project already loads a synced copy:
# its AGENTS.md carries the sync block (scripts/sync-policy.sh) and its
# CLAUDE.md imports AGENTS.md. Imports resolve relative to the file that
# contains them, so .claude/CLAUDE.md must import ../AGENTS.md.
root="${CLAUDE_PLUGIN_ROOT:?}"
project="${CLAUDE_PROJECT_DIR:-$PWD}"
case "${1:-bindings}" in
bindings)
  echo "Plugin root for templates, practices and skills: $root"
  cat "$root/adapters/claude/session.md"
  exit 0
  ;;
policy) part="${2:?usage: session-start.sh policy 1|2|3}" ;;
*) echo "usage: session-start.sh [bindings|policy 1|policy 2|policy 3]" >&2; exit 2 ;;
esac

imports() { grep -Eq "(^|[[:space:]])@$2([[:space:]]|\$)" "$1" 2>/dev/null; }
if grep -q '^<!-- agent-practices:policy:begin' "$project/AGENTS.md" 2>/dev/null &&
   { imports "$project/CLAUDE.md" '(\./)?AGENTS\.md' ||
     imports "$project/.claude/CLAUDE.md" '\.\./AGENTS\.md'; }; then
  exit 0
fi

# Split lines: the pair of `## P` headings that minimises the largest part
# (bytes).
LC_ALL=C awk -v part="$part" '
  { line[NR] = $0; size[NR] = length($0) + 1; total += size[NR]; pre[NR] = total }
  END {
    n = 0
    for (i = 2; i <= NR; i++) if (line[i] ~ /^## P/) cand[++n] = i
    b1 = 0; b2 = 0; bestm = 0
    for (a = 1; a <= n; a++) for (b = a + 1; b <= n; b++) {
      s1 = pre[cand[a] - 1]; s2 = pre[cand[b] - 1] - s1; s3 = total - pre[cand[b] - 1]
      m = s1; if (s2 > m) m = s2; if (s3 > m) m = s3
      if (bestm == 0 || m < bestm) { bestm = m; b1 = cand[a]; b2 = cand[b] }
    }
    if (b1 == 0) { b1 = NR + 1; b2 = NR + 1 }
    if (part == 1) { from = 1; to = b1 - 1 }
    else if (part == 2) { from = b1; to = b2 - 1; print "# Agent policy (continued)" }
    else { from = b2; to = NR; print "# Agent policy (continued)" }
    for (i = from; i <= to; i++) print line[i]
  }' "$root/policy/AGENTS.md"
