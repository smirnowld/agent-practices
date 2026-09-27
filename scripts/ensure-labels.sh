#!/bin/sh
# Create or update the baseline R6 issue labels (practices/project-baseline.md).
# Usage: ensure-labels.sh [--check] OWNER/REPO...
# --check is read-only: exits 1 if any label is missing or differs.
set -eu

# name|colour|description, one per line.
LABELS='deferred-review|5319e7|Finding deferred from review, fix later (P4)
p1|b60205|Blocks planned work, or risks users or data
p2|fbca04|Belongs in the current or next phase
p3|0e8a16|When convenient'

check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
if [ $# -eq 0 ]; then
  echo "usage: $0 [--check] OWNER/REPO..." >&2
  exit 2
fi

status=0
for repo in "$@"; do
  current=$(gh label list -R "$repo" --limit 500 --json name,color,description \
    --jq '.[] | "\(.name)|\(.color | ascii_downcase)|\(.description)"')
  while IFS='|' read -r name colour desc; do
    if printf '%s\n' "$current" | grep -qxF "$name|$colour|$desc"; then
      echo "$repo: $name ok"
    elif [ "$check" -eq 1 ]; then
      echo "$repo: $name missing or different"
      status=1
    else
      gh label create "$name" -R "$repo" --color "$colour" \
        --description "$desc" --force >/dev/null
      echo "$repo: $name set"
    fi
  done <<LIST
$LABELS
LIST
done
exit "$status"
