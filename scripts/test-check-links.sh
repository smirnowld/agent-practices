#!/bin/sh
# Offline self-test for check-links.py: the good fixture passes, and each
# line of the bad fixture is reported; with --closeout (chat summary) or
# --closeout-pr (whole closeout), a complete one passes and one missing fields
# names each.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-links.py" --offline "$dir/fixtures/links-good.md"
out=$(python3 "$dir/check-links.py" --offline "$dir/fixtures/links-bad.md") && {
  echo "error: bad fixture passed" >&2; exit 1; }
for n in 1 2 3 4 5 6 7; do
  echo "$out" | grep -q "^$n: " || { echo "error: line $n not reported" >&2; echo "$out" >&2; exit 1; }
done
for f in closeout-good closeout-chat; do
  python3 "$dir/check-links.py" --offline --closeout "$dir/fixtures/$f.md"
done
python3 "$dir/check-links.py" --offline --closeout-pr "$dir/fixtures/closeout-good.md"
expect_missing() {  # MODE FIELD...: the bad fixture fails MODE, naming each FIELD
  mode=$1; shift
  out=$(python3 "$dir/check-links.py" --offline "$mode" "$dir/fixtures/closeout-bad.md") && {
    echo "error: incomplete closeout passed $mode" >&2; exit 1; }
  for f in "$@"; do
    echo "$out" | grep -q "missing: \*\*$f:\*\*" || { echo "error: $f not reported" >&2; echo "$out" >&2; exit 1; }
  done
}
expect_missing --closeout 'TL;DR'
expect_missing --closeout-pr 'TL;DR' Proof Cleanup
# The chat check asks for the summary only, not the PR's Record.
python3 "$dir/check-links.py" --offline --closeout "$dir/fixtures/closeout-bad.md" | grep -q Proof && {
  echo "error: chat check asked for a Record field" >&2; exit 1; }
echo "check-links self-test passed"
