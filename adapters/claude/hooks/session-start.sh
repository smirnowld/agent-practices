#!/bin/sh
# Print the plugin root and this adapter's session bindings, then the policy,
# unless the project already loads a synced copy: its AGENTS.md carries the sync block (scripts/sync-policy.sh)
# and its CLAUDE.md imports AGENTS.md. Imports resolve relative to the file
# that contains them, so .claude/CLAUDE.md must import ../AGENTS.md.
root="${CLAUDE_PLUGIN_ROOT:?}"
project="${CLAUDE_PROJECT_DIR:-$PWD}"
echo "Plugin root for templates, practices and skills: $root"
cat "$root/adapters/claude/session.md"

imports() { grep -Eq "(^|[[:space:]])@$2([[:space:]]|\$)" "$1" 2>/dev/null; }
if grep -q '^<!-- agent-practices:policy:begin' "$project/AGENTS.md" 2>/dev/null &&
   { imports "$project/CLAUDE.md" '(\./)?AGENTS\.md' ||
     imports "$project/.claude/CLAUDE.md" '\.\./AGENTS\.md'; }; then
  exit 0
fi
cat "$root/policy/AGENTS.md"
