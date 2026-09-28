#!/bin/sh
# Offline self-test for check-action-pins.py: the good fixture passes, each
# `uses:` line of the bad fixture is reported and nothing else is, and this
# repository passes.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-action-pins.py" "$dir/fixtures/pins-good"
out=$(python3 "$dir/check-action-pins.py" "$dir/fixtures/pins-bad") && {
  echo "error: bad fixture passed" >&2; exit 1; }
expected="4 5 6 7 8 9 10 11 12 13 15 16 17 18 20"
for n in $expected; do
  echo "$out" | grep -q "ci.yml:$n: " || { echo "error: line $n not reported" >&2; echo "$out" >&2; exit 1; }
done
[ "$(echo "$out" | wc -l)" -eq "$(echo $expected | wc -w)" ] || {
  echo "error: unexpected lines reported" >&2; echo "$out" >&2; exit 1; }
# An action.yml outside .github is scanned. Built here, not committed, so the
# repository check below does not see it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sub" "$tmp/.github/dir.yml"
printf 'runs:\n  steps:\n    - uses: actions/checkout@v4\n' > "$tmp/sub/action.yml"
out=$(python3 "$dir/check-action-pins.py" "$tmp") && {
  echo "error: sub/action.yml passed" >&2; exit 1; }
echo "$out" | grep -q "^sub/action.yml:3: " || { echo "error: sub/action.yml not reported" >&2; echo "$out" >&2; exit 1; }
# A missing directory, or one with no workflow or action file (such as
# REPO/.github passed instead of REPO), exits 2 rather than passing.
for bad in "$tmp/missing" "$dir/../.github"; do
  rc=0; python3 "$dir/check-action-pins.py" "$bad" 2>/dev/null || rc=$?
  [ "$rc" -eq 2 ] || { echo "error: $bad exited $rc, not 2" >&2; exit 1; }
done
python3 "$dir/check-action-pins.py" "$dir/.."
echo "check-action-pins self-test passed"
