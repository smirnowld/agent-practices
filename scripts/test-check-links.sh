#!/bin/sh
# Offline self-test for check-links.py: the good fixture passes, and each
# line of the bad fixture is reported; with --closeout, a complete closeout
# passes and one missing fields names each.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-links.py" --offline "$dir/fixtures/links-good.md"
out=$(python3 "$dir/check-links.py" --offline "$dir/fixtures/links-bad.md") && {
  echo "error: bad fixture passed" >&2; exit 1; }
for n in 1 2 3 4 5 6 7; do
  echo "$out" | grep -q "^$n: " || { echo "error: line $n not reported" >&2; echo "$out" >&2; exit 1; }
done
python3 "$dir/check-links.py" --offline --closeout "$dir/fixtures/closeout-good.md"
out=$(python3 "$dir/check-links.py" --offline --closeout "$dir/fixtures/closeout-bad.md") && {
  echo "error: incomplete closeout passed" >&2; exit 1; }
for f in Proof Cleanup; do
  echo "$out" | grep -q "missing: \*\*$f:\*\*" || { echo "error: $f not reported" >&2; echo "$out" >&2; exit 1; }
done
echo "check-links self-test passed"
