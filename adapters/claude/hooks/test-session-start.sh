#!/bin/sh
# session-start.sh: every output stays under the 9,500-character cap, the two
# policy parts rebuild policy/AGENTS.md, and a synced project gets no policy.
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
hook="$here/session-start.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

mkdir "$tmp/plain" "$tmp/synced"
printf '# Project\n' > "$tmp/plain/AGENTS.md"
{ echo '# Project'; echo '<!-- agent-practices:policy:begin -->'; echo 'x'; echo '<!-- agent-practices:policy:end -->'; } > "$tmp/synced/AGENTS.md"
echo '@AGENTS.md' > "$tmp/synced/CLAUDE.md"

run() { CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$1" sh "$hook" $2 $3 > "$4"; }

for proj in plain synced; do
  d="$tmp/$proj"
  run "$d" bindings "" "$tmp/$proj.b"
  run "$d" policy 1 "$tmp/$proj.p1"
  run "$d" policy 2 "$tmp/$proj.p2"
  run "$d" "" "" "$tmp/$proj.default"
  for f in b p1 p2; do
    n=$(wc -c < "$tmp/$proj.$f" | tr -d ' ')
    echo "$proj $f: $n characters"
    [ "$n" -lt 9500 ] || bad "$proj $f is $n characters, over the 9,500 cap; split policy/AGENTS.md further"
  done
  cmp -s "$tmp/$proj.b" "$tmp/$proj.default" || bad "$proj: no argument differs from bindings"
  grep -q "^Plugin root" "$tmp/$proj.b" || bad "$proj: bindings lack the plugin root line"
done

[ -s "$tmp/plain.p1" ] && [ -s "$tmp/plain.p2" ] || bad "plain: a policy part is empty"
head -n 1 "$tmp/plain.p2" | grep -q '^# Agent policy (continued)$' || bad "plain: part 2 lacks the continuation line"
{ cat "$tmp/plain.p1"; tail -n +2 "$tmp/plain.p2"; } > "$tmp/joined"
cmp -s "$tmp/joined" "$root/policy/AGENTS.md" || bad "plain: parts do not rebuild policy/AGENTS.md"
sed -n 2p "$tmp/plain.p2" | grep -q '^## P' || bad "plain: part 2 does not start at a ## P heading"

[ ! -s "$tmp/synced.p1" ] && [ ! -s "$tmp/synced.p2" ] || bad "synced: policy parts must print nothing"

[ "$fail" = 0 ] && echo "ok"
exit "$fail"
