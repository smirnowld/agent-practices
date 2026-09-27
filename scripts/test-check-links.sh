#!/bin/sh
# Offline self-test for check-links.py: the good fixture passes, and each
# line of the bad fixture is reported.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-links.py" --offline "$dir/fixtures/links-good.md"
out=$(python3 "$dir/check-links.py" --offline "$dir/fixtures/links-bad.md") && {
  echo "error: bad fixture passed" >&2; exit 1; }
for n in 1 2 3; do
  echo "$out" | grep -q "^$n: " || { echo "error: line $n not reported" >&2; echo "$out" >&2; exit 1; }
done
echo "check-links self-test passed"
