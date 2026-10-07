#!/bin/sh
# Session start output, in parts because a hook's output over 10,000 characters
# is saved to a file and shown as a 2,000-character preview
# (https://code.claude.com/docs/en/hooks). Keep every part under 9,500.
#   bindings (also the default with no argument): the plugin root and this
#     adapter's session bindings.
#   policy 1 / policy 2: the first and second half of policy/AGENTS.md, split
#     at the `## P` heading that makes the halves most even.
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
policy) part="${2:?usage: session-start.sh policy 1|2}" ;;
*) echo "usage: session-start.sh [bindings|policy 1|policy 2]" >&2; exit 2 ;;
esac

imports() { grep -Eq "(^|[[:space:]])@$2([[:space:]]|\$)" "$1" 2>/dev/null; }
if grep -q '^<!-- agent-practices:policy:begin' "$project/AGENTS.md" 2>/dev/null &&
   { imports "$project/CLAUDE.md" '(\./)?AGENTS\.md' ||
     imports "$project/.claude/CLAUDE.md" '\.\./AGENTS\.md'; }; then
  exit 0
fi

# Split line: the `## P` heading whose position makes the two halves' sizes
# closest (bytes).
LC_ALL=C awk -v part="$part" '
  { line[NR] = $0; size[NR] = length($0) + 1; total += size[NR] }
  END {
    acc = 0; best = 0
    for (i = 1; i <= NR; i++) {
      if (i > 1 && line[i] ~ /^## P/) {
        d = acc * 2 - total; if (d < 0) d = -d
        if (best == 0 || d < bestd) { best = i; bestd = d }
      }
      acc += size[i]
    }
    if (best == 0) best = NR + 1
    if (part == 1) { from = 1; to = best - 1 }
    else { from = best; to = NR; print "# Agent policy (continued)" }
    for (i = from; i <= to; i++) print line[i]
  }' "$root/policy/AGENTS.md"
