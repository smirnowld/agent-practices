#!/bin/sh
# Offline self-test for check-adrs.py: the good fixture passes, each expected
# failure of the bad fixture is reported and nothing else is, a missing index
# is caught in a purpose-built temp tree, and a missing or wrong directory
# exits 2 rather than passing. PR mode requires a proposed ADR the PR changes
# to be named in the description's "ADRs:" item.
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
  "0003-wrong-place-superseded.md:3: superseded by ADR-0099, which does not exist" \
; do
  echo "$out" | grep -q "$needle" || { echo "error: not reported: $needle" >&2; echo "$out" >&2; exit 1; }
done
[ "$(echo "$out" | wc -l)" -eq 13 ] || {
  echo "error: unexpected lines reported" >&2; echo "$out" >&2; exit 1; }

# Issue #22: a superseded-by target must be an existing ADR other than the
# file itself.
out=$(python3 "$dir/check-adrs.py" "$dir/fixtures/adrs-bad-supersede") && {
  echo "error: bad supersede fixture passed" >&2; exit 1; }
for needle in \
  "archive/0002-self.md:3: superseded by itself (ADR-0002)" \
  "archive/0003-dangling.md:3: superseded by ADR-0007, which does not exist" \
; do
  echo "$out" | grep -q "$needle" || { echo "error: not reported: $needle" >&2; echo "$out" >&2; exit 1; }
done
[ "$(echo "$out" | wc -l)" -eq 2 ] || {
  echo "error: unexpected lines reported (supersede)" >&2; echo "$out" >&2; exit 1; }

# Issues #23, #24, #25: near-miss Status line and list-style index row name the
# expected form; the unfilled template row fails; the Status column is found
# from the header, not the last cell.
out=$(python3 "$dir/check-adrs.py" "$dir/fixtures/adrs-bad-index") && {
  echo "error: bad index fixture passed" >&2; exit 1; }
for needle in \
  '0001-near-miss-status.md: missing \*\*Status:\*\* line; line 3 reads "\*\*Status\*\*: accepted"; write \*\*Status:\*\* VALUE' \
  'README.md:5: placeholder row: replace <NNNN>' \
  'README.md:7: lists 0003-wrong-column.md as Accepted, but its Status line says proposed' \
  'README.md:9: does not list 0002-list-row.md in a table row; expected | \[NNNN\](0002-list-row.md) | DECISION | STATUS |' \
; do
  echo "$out" | grep -q "$needle" || { echo "error: not reported: $needle" >&2; echo "$out" >&2; exit 1; }
done
[ "$(echo "$out" | wc -l)" -eq 4 ] || {
  echo "error: unexpected lines reported (index)" >&2; echo "$out" >&2; exit 1; }

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

# PR mode: a PR that adds or edits a proposed ADR must name it in an "ADRs:"
# item of its description. adrs-good holds 0002 (proposed) and 0001
# (accepted).
good="$dir/fixtures/adrs-good"
pr() { python3 "$dir/check-adrs.py" "$good" --pr-body "$tmp/body" --changed "$tmp/changed"; }
# pr_fails WHAT: the PR check on $tmp/body exits exactly 1.
pr_fails() {
  rc=0; out=$(pr) || rc=$?
  [ "$rc" -eq 1 ] || { echo "error: $1: exited $rc, not 1" >&2; echo "$out" >&2; exit 1; }
}
printf 'docs/adr/0002-use-widgets.md\nREADME.md\n' > "$tmp/changed"
printf '## Summary\n\nAdds ADR-0002.\n\n- ADRs: none\n' > "$tmp/body"
pr_fails "unnamed proposed ADR"
[ "$out" = 'docs/adr/0002-use-widgets.md: proposed ADR changed in this PR; the PR description needs an "ADRs:" line naming ADR-0002 (practices/record-keeping.md#triggers)' ] || {
  echo "error: unnamed proposed ADR not reported alone" >&2; echo "$out" >&2; exit 1; }
# Named only in an HTML comment, outside the item, or as ADR-00021: still fails.
printf -- '- Summary: ADR-0002\n- ADRs: <!-- ADR-0002 accepted -->none\n  ADR-00021\n\nADR-0002\n' > "$tmp/body"
pr_fails "ADR named outside the ADRs: item"
printf '```\n- ADRs: ADR-0002 accepted\n```\n' > "$tmp/body"
pr_fails "ADRs: item inside a fence"
printf '````\n```\n- ADRs: ADR-0002 accepted\n```\n````\n' > "$tmp/body"
pr_fails "ADRs: item inside a four-backtick fence holding three"
printf '<!--\n- ADRs: ADR-0002 accepted\n-->\n- ADRs: none\n' > "$tmp/body"
pr_fails "ADRs: item inside a comment"
# Named in the item: one line, bold, underscore emphasis, wrapped
# continuation, nested list, or a second item.
for body in \
  '- ADRs: ADR-0002 accepted, "yes"\n' \
  '**ADRs:** adr-0002 left proposed, exploratory: spike\n' \
  '- ADRs: _ADR-0002_ accepted\n' \
  '- ADRs: ADR-0001 n/a,\n  ADR-0002 not yet <!-- P11 -->\n- Next: x\n' \
  '- ADRs:\n  - ADR-0001 n/a\n  - ADR-0002 accepted\n- Next: x\n' \
  '- ADRs: none\n\n* ADRs: ADR-0002 rejected\n' \
; do
  printf -- "$body" > "$tmp/body"
  out=$(pr) || { echo "error: named proposed ADR failed: $body" >&2; echo "$out" >&2; exit 1; }
done
# Wrapping ends at a blank line, a same-level list item or a heading.
for body in \
  '- ADRs: none\n\nADR-0002\n' \
  '- ADRs: none\n- ADR-0002\n' \
  '  - ADRs: none\n  - ADR-0002\n' \
  '- ADRs: none\n# ADR-0002\n' \
  '- ADRs: ADR-00021\n' \
; do
  printf -- "$body" > "$tmp/body"
  pr_fails "text after or beside the item counted: $body"
done
# Only an accepted ADR, no ADR, or a deleted ADR changed: no ADRs: line needed.
printf 'Nothing here.\n' > "$tmp/body"
for changed in 'docs/adr/0001-record-decisions.md\n' 'README.md\nscripts/x.py\n' '\n  docs/adr/0009-gone.md  \n' 'docs/adr/README.md\ndocs/adr/0000-template.md\n'; do
  printf -- "$changed" > "$tmp/changed"
  out=$(pr) || { echo "error: PR mode failed for: $changed" >&2; echo "$out" >&2; exit 1; }
done
# --changed - reads stdin.
rc=0
printf 'docs/adr/0002-use-widgets.md\n' | python3 "$dir/check-adrs.py" "$good" --pr-body "$tmp/body" --changed - >/dev/null || rc=$?
[ "$rc" -eq 1 ] || { echo "error: --changed - exited $rc, not 1" >&2; exit 1; }
# Normal checks still run in PR mode, and their failures add to the PR ones.
printf 'docs/adr/0003-wrong-column.md\n' > "$tmp/changed"
rc=0
out=$(python3 "$dir/check-adrs.py" "$dir/fixtures/adrs-bad-index" --pr-body "$tmp/body" --changed "$tmp/changed") || rc=$?
[ "$rc" -eq 1 ] || { echo "error: bad fixture in PR mode exited $rc, not 1" >&2; exit 1; }
[ "$(echo "$out" | wc -l)" -eq 5 ] && echo "$out" | grep -q 'naming ADR-0003' || {
  echo "error: PR mode did not add to the normal failures" >&2; echo "$out" >&2; exit 1; }
# One flag without the other, or an unreadable input, exits 2.
for args in "--pr-body $tmp/body" "--changed $tmp/changed" "--pr-body $tmp/nope --changed $tmp/changed" "--pr-body $tmp/body --changed $tmp/nope"; do
  rc=0; python3 "$dir/check-adrs.py" "$good" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "error: $args exited $rc, not 2" >&2; exit 1; }
done

# A missing directory, or one with no docs/adr directory, exits 2 rather than
# passing.
for bad in "$tmp/missing" "$dir/fixtures/adrs-good/docs/adr"; do
  rc=0; python3 "$dir/check-adrs.py" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "error: $bad exited $rc, not 2" >&2; exit 1; }
done

echo "check-adrs self-test passed"
