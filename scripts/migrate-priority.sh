#!/bin/sh
# Temporary: delete this script when the p1-p3 priority labels are retired
# (baseline R6, practices/tracking.md).
# Copy each open issue's p1/p2/p3 label into the board's Priority field.
# Usage: migrate-priority.sh OWNER/REPO OWNER PROJECT_NUMBER [--verify]
# Adds every open issue to the board and sets Priority only where it is empty;
# never removes a label or overwrites a field. --verify is read-only: exits 1
# listing open issues missing from the board or whose label and field disagree.
set -eu

if [ $# -lt 3 ] || [ $# -gt 4 ] || { [ $# -eq 4 ] && [ "$4" != --verify ]; }; then
  echo "usage: $0 OWNER/REPO OWNER PROJECT_NUMBER [--verify]" >&2
  exit 2
fi
repo=$1; owner=$2; number=$3; verify=0
if [ $# -eq 4 ]; then verify=1; fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case $(gh api "users/$owner" --jq .type) in
  Organization) key=organization ;;
  *) key=user ;;
esac

# number|url|labels, comma-separated
gh issue list -R "$repo" --state open --limit 1000 --json number,url,labels \
  --jq '.[] | "\(.number)|\(.url)|\([.labels[].name] | join(","))"' > "$tmp/issues"
# url|item id|priority
gh api graphql --paginate -f query="query(\$o:String!,\$n:Int!,\$endCursor:String){$key(login:\$o){projectV2(number:\$n){items(first:100,after:\$endCursor){pageInfo{hasNextPage endCursor}nodes{id content{...on Issue{url}}fieldValueByName(name:\"Priority\"){...on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}" \
  -f o="$owner" -F n="$number" \
  --jq '.data[].projectV2.items.nodes[] | select(.content.url != null) | "\(.content.url)|\(.id)|\(.fieldValueByName.name // "")"' > "$tmp/items"
if [ "$verify" -eq 0 ]; then
  pid=$(gh project view "$number" --owner "$owner" --format json --jq .id)
  # field id|option id|option name
  gh project field-list "$number" --owner "$owner" --format json \
    --jq '.fields[] | select(.name == "Priority") | .id as $f | .options[] | "\($f)|\(.id)|\(.name)"' > "$tmp/options"
  [ -s "$tmp/options" ] || { echo "board $number has no Priority field" >&2; exit 2; }
fi

status=0
while IFS='|' read -r num url labels; do
  # The highest of p1-p3, either case; "P1 now", "P2 soon" or "P3 later" by prefix.
  level=$(printf '%s\n' "$labels" | tr ',' '\n' | tr 'P' 'p' | grep -x 'p[123]' | sort | head -n 1 || true)
  want=$(printf '%s' "$level" | tr 'p' 'P')
  item=$(awk -F'|' -v u="$url" '$1 == u {print $2; exit}' "$tmp/items")
  have=$(awk -F'|' -v u="$url" '$1 == u {print $3; exit}' "$tmp/items")
  if [ "$verify" -eq 1 ]; then
    if [ -z "$item" ]; then
      echo "#$num: not on the board"; status=1
    elif [ -n "$want" ] && [ "${have%% *}" != "$want" ]; then
      echo "#$num: label $level, Priority ${have:-empty}"; status=1
    fi
    continue
  fi
  if [ -z "$item" ]; then
    item=$(gh project item-add "$number" --owner "$owner" --url "$url" --format json --jq .id </dev/null)
    echo "#$num: added to the board"
  fi
  if [ -z "$want" ]; then
    :
  elif [ -z "$have" ]; then
    line=$(awk -F'|' -v p="$want" 'index($3, p " ") == 1 || $3 == p {print; exit}' "$tmp/options")
    [ -n "$line" ] || { echo "#$num: no Priority option for $level" >&2; status=1; continue; }
    gh project item-edit --id "$item" --project-id "$pid" --field-id "${line%%|*}" \
      --single-select-option-id "$(printf '%s' "$line" | cut -d'|' -f2)" >/dev/null </dev/null
    echo "#$num: Priority $(printf '%s' "$line" | cut -d'|' -f3)"
  elif [ "${have%% *}" != "$want" ]; then
    echo "#$num: kept Priority $have, label says $level"
  fi
done < "$tmp/issues"
exit "$status"
