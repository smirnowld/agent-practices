#!/bin/sh
# Offline self-test for check-adrs.py: the good fixture passes, each expected
# failure of the bad fixture is reported and nothing else is, a missing index
# is caught in a purpose-built temp tree, and a missing or wrong directory
# exits 2 rather than passing.
set -eu
dir=$(dirname "$0")
python3 "$dir/check-adrs.py" "$dir/fixtures/adrs-good"
out=$(python3 "$dir/check-adrs.py" "$dir/fixtures/adrs-bad") && {
  echo "error: bad fixture passed" >&2; exit 1; }
for needle in \
  "0001-missing-status.md: missing \*\*Status:\*\* line" \
  "0002-invalid-status.md:3: status outside the set: Draft" \
  "0003-wrong-place-superseded.md:3: superseded/rejected status in docs/adr/" \
  "archive/0004-wrong-place-accepted.md:3: proposed/accepted status in docs/adr/archive/" \
  "bad-name.md: file name must be NNNN-kebab-case.md" \
  "duplicate ADR-0005: docs/adr/0005-dup-a.md, docs/adr/0005-dup-b.md" \
  "ADR-0006 missing: gap in numbering" \
  "README.md: does not list 0007-not-indexed.md" \
  "README.md:10: lists 0011-phantom.md, which does not exist" \
  "README.md:11: lists archived 0004-wrong-place-accepted.md; archived ADRs leave the index" \
  "README.md:12: lists archived 0008-archived-bare.md; archived ADRs leave the index" \
  "README.md:8: lists 0005-dup-a.md as Accepted, but its Status line says proposed" \
; do
  echo "$out" | grep -q "$needle" || { echo "error: not reported: $needle" >&2; echo "$out" >&2; exit 1; }
done
[ "$(echo "$out" | wc -l)" -eq 12 ] || {
  echo "error: unexpected lines reported" >&2; echo "$out" >&2; exit 1; }

# A docs/adr/ with ADRs but no README.md fails with "missing index". Built
# here, not committed, so make check does not see it.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/docs/adr"
printf '# A decision\n\n**Status:** accepted\n' > "$tmp/docs/adr/0001-a-decision.md"
out=$(python3 "$dir/check-adrs.py" "$tmp") && {
  echo "error: missing index passed" >&2; exit 1; }
echo "$out" | grep -q "^docs/adr/README.md: missing index$" || {
  echo "error: missing index not reported" >&2; echo "$out" >&2; exit 1; }

# Numbering starts at 0001: a tree holding only 0002 reports ADR-0001 missing.
mkdir -p "$tmp/gap/docs/adr"
printf '# B decision\n\n**Status:** accepted\n' > "$tmp/gap/docs/adr/0002-b-decision.md"
printf '| [0002](0002-b-decision.md) | B decision | Accepted |\n' > "$tmp/gap/docs/adr/README.md"
out=$(python3 "$dir/check-adrs.py" "$tmp/gap") && {
  echo "error: numbering from 0002 passed" >&2; exit 1; }
[ "$out" = "docs/adr: ADR-0001 missing: gap in numbering" ] || {
  echo "error: ADR-0001 gap not reported alone" >&2; echo "$out" >&2; exit 1; }

# A missing directory, or one with no docs/adr directory, exits 2 rather than
# passing.
for bad in "$tmp/missing" "$dir/fixtures/adrs-good/docs/adr"; do
  rc=0; python3 "$dir/check-adrs.py" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "error: $bad exited $rc, not 2" >&2; exit 1; }
done

echo "check-adrs self-test passed"
