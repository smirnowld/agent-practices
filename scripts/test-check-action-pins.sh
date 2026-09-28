#!/bin/sh
# Offline self-test for check-action-pins.py: the good fixture passes, each
# `uses:` line of the bad fixture is reported, and this repository passes.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-action-pins.py" "$dir/fixtures/pins-good"
out=$(python3 "$dir/check-action-pins.py" "$dir/fixtures/pins-bad") && {
  echo "error: bad fixture passed" >&2; exit 1; }
for n in 4 5 6 7 8 9 11; do
  echo "$out" | grep -q "ci.yml:$n: " || { echo "error: line $n not reported" >&2; echo "$out" >&2; exit 1; }
done
python3 "$dir/check-action-pins.py" "$dir/.."
echo "check-action-pins self-test passed"
