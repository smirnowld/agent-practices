#!/bin/sh
# Self-test for sync-policy.sh on throwaway directories.
set -eu
dir=$(mktemp -d)
printf '# Project\n\nOwn rules.\n' > "$dir/AGENTS.md"
sh scripts/sync-policy.sh "$dir"                 # insert
grep -q '^<!-- agent-practices:policy:begin' "$dir/AGENTS.md"
grep -q '^Own rules\.$' "$dir/AGENTS.md"
cp "$dir/AGENTS.md" "$dir/first"
sh scripts/sync-policy.sh "$dir"                 # resync is idempotent
cmp "$dir/AGENTS.md" "$dir/first"
sh scripts/sync-policy.sh --check "$dir"
# Malformed markers fail and leave the file alone.
bad=$(mktemp -d)
printf '<!-- agent-practices:policy:begin x -->\nold\n' > "$bad/AGENTS.md"
cp "$bad/AGENTS.md" "$bad/orig"
if sh scripts/sync-policy.sh "$bad"; then echo "malformed markers accepted"; exit 1; fi
cmp "$bad/AGENTS.md" "$bad/orig"
# Mixed line endings: lines outside the block keep theirs, byte for byte.
mix=$(mktemp -d)
printf '# P\r\nLF line\n<!-- agent-practices:policy:begin x -->\r\nold\n<!-- agent-practices:policy:end -->\nafter\n' \
  > "$mix/AGENTS.md"
sh scripts/sync-policy.sh "$mix" > /dev/null
if grep -q '^old' "$mix/AGENTS.md"; then echo "block not replaced"; exit 1; fi
outside() { sed '/^<!-- agent-practices:policy:begin/,/^<!-- agent-practices:policy:end -->/d' "$1"; }
printf '# P\r\nLF line\nafter\n' > "$mix/want"
outside "$mix/AGENTS.md" | cmp - "$mix/want"
echo "sync self-test passed"
