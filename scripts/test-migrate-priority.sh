#!/bin/sh
# Self-test for migrate-priority.sh against a fake gh; touches no real board.
set -eu
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin"
S=$dir; export S
# Open issues (number|url|labels) and board items (url|item id|priority),
# as the script's --jq filters print them.
cat > "$S/issues" <<'EOF'
1|https://x/o/r/issues/1|bug,p1
2|https://x/o/r/issues/2|P2
3|https://x/o/r/issues/3|p3
4|https://x/o/r/issues/4|
5|https://x/o/r/issues/5|p3,p2
EOF
cat > "$S/items" <<'EOF'
https://x/o/r/issues/1|I1|
https://x/o/r/issues/3|I3|P1 now
https://x/o/r/issues/5|I5|P2 soon
EOF
cat > "$dir/bin/gh" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$S/log"
case "$1 $2" in
  "api users/"*) echo Organization ;;
  "issue list") cat "$S/issues" ;;
  "api graphql") cat "$S/items" ;;
  "project view") echo PVT_1 ;;
  "project field-list") printf 'F|op1|P1 now\nF|op2|P2 soon\nF|op3|P3 later\n' ;;
  "project item-add")
    while [ "$1" != --url ]; do shift; done
    id="I${2##*/}"; echo "$2|$id|" >> "$S/items"; echo "$id" ;;
  "project item-edit")
    while [ $# -gt 0 ]; do
      case $1 in --id) id=$2 ;; --single-select-option-id) o=$2 ;; esac; shift
    done
    case $o in op1) v='P1 now' ;; op2) v='P2 soon' ;; op3) v='P3 later' ;; esac
    awk -F'|' -v OFS='|' -v i="$id" -v v="$v" '$2 == i {$3 = v} {print}' "$S/items" > "$S/items.new"
    mv "$S/items.new" "$S/items" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$dir/bin/gh"
PATH="$dir/bin:$PATH"; export PATH

# --verify before migrating: lists gaps, writes nothing.
cp "$S/items" "$dir/before"
if sh scripts/migrate-priority.sh o/r o 1 --verify > "$dir/out"; then echo "verify passed with gaps"; exit 1; fi
cmp "$S/items" "$dir/before"
grep -qx '#1: label p1, Priority empty' "$dir/out"
grep -qx '#2: not on the board' "$dir/out"
grep -qx '#3: label p3, Priority P1 now' "$dir/out"
grep -qx '#4: not on the board' "$dir/out"
[ "$(wc -l < "$dir/out")" -eq 4 ]                 # #5: p2 wins over p3 and matches

sh scripts/migrate-priority.sh o/r o 1 > "$dir/out"
grep -qxF 'https://x/o/r/issues/1|I1|P1 now' "$S/items"
grep -qxF 'https://x/o/r/issues/2|I2|P2 soon' "$S/items"
grep -qxF 'https://x/o/r/issues/3|I3|P1 now' "$S/items"   # field never overwritten
grep -qxF 'https://x/o/r/issues/4|I4|' "$S/items"         # added, no priority
grep -qx '#3: kept Priority P1 now, label says p3' "$dir/out"
if grep -Eq '^(label|issue edit)' "$S/log"; then echo 'labels changed'; exit 1; fi

# Rerun changes nothing; --verify now flags only the kept disagreement.
cp "$S/items" "$dir/first"
sh scripts/migrate-priority.sh o/r o 1 > /dev/null
cmp "$S/items" "$dir/first"
if sh scripts/migrate-priority.sh o/r o 1 --verify > "$dir/out"; then echo "verify missed #3"; exit 1; fi
[ "$(cat "$dir/out")" = '#3: label p3, Priority P1 now' ]
echo "migrate-priority self-test passed"
