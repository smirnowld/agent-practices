#!/bin/sh
# Self-test for ensure-board.sh against a fake gh; touches no real board.
set -eu
[ -n "${TRACE:-}" ] && set -x
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin" "$dir/state"
FAKE_STATE="$dir/state"; export FAKE_STATE
echo 0 > "$FAKE_STATE/id"
# Fake gh: one directory per board holding the flattened lines ensure-board.sh
# reads (title, template, fields, views, workflows). It answers each call with
# what gh's --jq filter would print, and applies mutations to those files.
# Owner "u" is a user, every other owner an organisation. Files fail_list and
# fail_read make listing or reading boards fail. Each view created is logged
# to posts.
cat > "$dir/bin/gh" <<'FAKE'
#!/bin/sh
S=$FAKE_STATE
printf '%s\n' "$*" >> "$S/log"
# The GraphQL string after KEY in $line, unescaped and encoded as BOARD_JQ prints it.
gstr() {
  printf '%s' "$line" | sed -E 's/.*'"$1"':"(([^"\\]|\\.)*)".*/\1/; s/\\"/"/g; s/\\\\/\\/g' |
    sed 's/%/%25/g; s/~/%7E/g; s/;/%3B/g; s/[|]/%7C/g'
}
newid() { i=$(($(cat "$S/id") + 1)); echo "$i" > "$S/id"; echo "$i"; }
opt() { # FLAG ARGS...: value after FLAG
  f=$1; shift
  while [ $# -gt 1 ]; do [ "$1" = "$f" ] && { echo "$2"; return; }; shift; done
}
newboard() { # TITLE -> number
  n=1; while [ -d "$S/$n" ]; do n=$((n + 1)); done
  mkdir "$S/$n"; echo "$1" > "$S/$n/title"; echo false > "$S/$n/template"
  cat > "$S/$n/fields" <<EOF
F|PVTF_1|101|Title|TITLE|
F|PVTF_2|102|Assignees|ASSIGNEES|
F|PVTF_3|103|Status|SINGLE_SELECT|t1~Todo~GRAY~;t2~In Progress~YELLOW~;t3~Done~GREEN~
F|PVTF_4|104|Labels|LABELS|
F|PVTF_5|105|Linked pull requests|LINKED_PULL_REQUESTS|
F|PVTF_6|106|Repository|REPOSITORY|
F|PVTF_7|107|Sub-issues progress|SUB_ISSUES_PROGRESS|
EOF
  echo 'V|PVTV_0|View 1|table|||||Title' > "$S/$n/views"
  printf 'W|Item added to project|true\nW|Item closed|true\nW|Pull request merged|true\n' > "$S/$n/workflows"
  echo "$n"
}
query=''; n=''
for a in "$@"; do case $a in query=*) query=${a#query=} ;; n=*) n=${a#n=} ;; esac; done
case "$1 $2" in
  "api users/u") echo 'User|42' ;;
  "api users/"*) echo 'Organization|1' ;;
  "api graphql")
    case $query in
      *updateProjectV2Field*)
        fid=$(printf '%s' "$query" | sed 's/.*fieldId:"\([^"]*\)".*/\1/')
        opts=''
        for line in $(printf '%s' "$query" | sed 's/.*singleSelectOptions:\[{//; s/}\]}.*//; s/ /_/g; s/},{/ /g'); do
          line=$(printf '%s' "$line" | tr '_' ' ')
          id=$(printf '%s' "$line" | sed -n 's/^id:"\([^"]*\)".*/\1/p')
          [ -n "$id" ] || id="o$(newid)"
          name=$(gstr name)
          colour=$(printf '%s' "$line" | sed 's/.*color:\([A-Z]*\).*/\1/')
          desc=$(gstr description)
          opts="$opts${opts:+;}$id~$name~$colour~$desc"
        done
        for f in "$S"/*/fields; do
          awk -F'|' -v OFS='|' -v i="$fid" -v o="$opts" '$2 == i {$6 = o} {print}' "$f" > "$f.new"
          mv "$f.new" "$f"
        done ;;
      *deleteProjectV2View*)
        vid=$(printf '%s' "$query" | sed 's/.*viewId:"\([^"]*\)".*/\1/')
        for f in "$S"/*/views; do grep -v "^V|$vid|" "$f" > "$f.new" || true; mv "$f.new" "$f"; done ;;
      *updateProjectV2\(*) ;;
      *workflows*)
        [ ! -f "$S/fail_read" ] && [ -d "$S/$n" ] || { echo "Could not resolve to a ProjectV2" >&2; exit 1; }
        d="$S/$n"
        echo "P|PVT_$n|$(cat "$d/template")|$(cat "$d/title")"
        cat "$d/fields" "$d/views" "$d/workflows"
        if [ -f "$S/bad_repos" ]; then echo 'R|null'
        elif [ -f "$S/linked_$n" ]; then echo 'R|1'; else echo 'R|0'; fi ;;
      *) echo "fake gh: unexpected query $query" >&2; exit 1 ;;
    esac ;;
  "api -X")
    d="$S/$(printf '%s' "$4" | sed 's#.*projectsV2/\([0-9]*\)/views#\1#')"
    j=$(cat "$6")
    printf '%s\n' "$j" >> "$S/posts"
    get() { printf '%s' "$j" | sed -n "s/$1/\\1/p"; }
    fname() { awk -F'|' -v i="$1" '$3 == i {print $4}' "$d/fields"; }
    name=$(get '.*"name":"\([^"]*\)".*')
    layout=$(get '.*"layout":"\([^"]*\)".*')
    filter=$(get '.*"filter":"\([^"]*\)".*')
    group=$(fname "$(get '.*[{,]"group_by":\[\([0-9]*\)\].*')")
    cols=$(fname "$(get '.*"vertical_group_by":\[\([0-9]*\)\].*')")
    sort=$(get '.*"sort_by":\[\[\([0-9]*,"[a-z]*"\)\]\].*')
    if [ -n "$sort" ]; then
      sort="$(fname "${sort%%,*}"):$(printf '%s' "${sort#*,}" | tr -d '"' | tr 'a-z' 'A-Z')"
    fi
    shown=$(for i in $(get '.*"visible_fields":\[\([0-9,]*\)\].*' | tr ',' ' '); do fname "$i"; done |
      LC_ALL=C sort | paste -sd, -)
    echo "V|PVTV_$(newid)|$name|$layout|$filter|$group|$cols|$sort|$shown" >> "$d/views" ;;
  "project list")
    [ ! -f "$S/fail_list" ] || { echo "HTTP 502" >&2; exit 1; }
    for d in "$S"/[0-9]*; do [ -d "$d" ] && echo "${d##*/}|$(cat "$d/title")"; done; true ;;
  "project create") newboard "$(opt --title "$@")" ;;
  "project field-create")
    d="$S/$3"; type=$(opt --data-type "$@"); opts=''
    names=$(opt --single-select-options "$@" | tr ' ,' '_ ')
    for o in $names; do opts="$opts${opts:+;}o$(newid)~$(printf '%s' "$o" | tr '_' ' ')~GRAY~"; done
    i=$(newid)
    echo "F|PVTF_$i|$((200 + i))|$(opt --name "$@")|$type|$opts" >> "$d/fields" ;;
  "project mark-template") echo true > "$S/$3/template" ;;
  "project copy")
    n=$(newboard "$(opt --title "$@")")
    sed "s/^F|PVTF_/F|PVTF_${n}_/" "$S/$3/fields" > "$S/$n/fields"   # a copy's fields get their own ids
    cp "$S/$3/views" "$S/$n/"
    grep -v '^W|Auto-add to project|' "$S/$3/workflows" > "$S/$n/workflows" || true
    echo "$n" ;;
  "project link")
    if [ -f "$S/linked_$3" ]; then echo "repository already linked" >&2; exit 1; fi
    touch "$S/linked_$3" ;;
  *) echo "fake gh: unexpected $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$dir/bin/gh"
PATH="$dir/bin:$PATH"; export PATH
S=$FAKE_STATE
run() { sh scripts/ensure-board.sh "$@" > "$dir/out" 2>&1; }
fails() { # CODE ARGS...: the script must exit with CODE
  want=$1; shift
  if run "$@"; then got=0; else got=$?; fi
  [ "$got" -eq "$want" ] || { echo "ensure-board $*: exit $got, want $want"; cat "$dir/out"; exit 1; }
}
snap() { rm -rf "${dir:?}/$1"; mkdir "$dir/$1"; for f in "$S"/[0-9]*/*; do b=${f#"$S"/}; cp "$f" "$dir/$1/$(printf '%s' "$b" | tr / _)"; done; }
boards() { find "$S" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '; }
mark() { start=$(wc -l < "$S/log"); }
no_writes() { # nothing but reads since mark
  if tail -n "+$((start + 1))" "$S/log" | grep -E 'mutation|-X POST|^project (create|copy|link|field-create|mark-template)'; then
    echo "a read-only run wrote"; exit 1
  fi
}

# Template: only in an organisation, never after a failed list.
fails 2 template u
grep -q 'organisations only' "$dir/out"
touch "$S/fail_list"
fails 2 template o
grep -q 'cannot list the boards of o' "$dir/out"
rm "$S/fail_list"
[ "$(boards)" -eq 0 ]

# Template: created from GitHub's defaults, built-in Status options kept by id.
run template o
[ "$(cat "$S/1/title")" = 'Board template' ]
[ "$(cat "$S/1/template")" = true ]
grep -q 't1~Backlog~GRAY~Filed, not in the current phase;o[0-9]*~Planned~PURPLE~' "$S/1/fields"
grep -q 't2~In progress~YELLOW~' "$S/1/fields"
grep -q 't3~Done~GREEN~' "$S/1/fields"
grep -q '|Priority|SINGLE_SELECT|o[0-9]*~P1 now~RED~Blocks planned work, or risks users or data;' "$S/1/fields"
grep -q '|Phase|SINGLE_SELECT|o[0-9]*~Current phase~BLUE~' "$S/1/fields"
grep -q '|Waiting for|TEXT|$' "$S/1/fields"
grep -q '|Target|DATE|$' "$S/1/fields"
if grep -q '|View 1|' "$S/1/views"; then echo 'View 1 kept'; exit 1; fi
[ "$(wc -l < "$S/1/views")" -eq 7 ]
grep -q '|In flight|board|-status:Backlog,Parked,Done||Status||Assignees,Phase,Priority,Title,Waiting for$' "$S/1/views"
grep -q '|Assigned to me|table|assignee:@me -status:Done|||Priority:ASC|' "$S/1/views"
grep -q '|Phase|table|label:work-package|Phase|||' "$S/1/views"
grep -q '|Backlog|table|status:Backlog|Priority|||' "$S/1/views"
grep -q '|No priority yet|table|no:priority -status:Done||||' "$S/1/views"
grep -q '|Long-lead|roadmap|label:long-lead|||Target:ASC|' "$S/1/views"
grep -q 'Item reopened: turn on' "$dir/out"
grep -q 'Auto-archive items' "$dir/out"

# Rerun changes nothing.
snap first
run template o
snap second
diff -r "$dir/first" "$dir/second"
if grep -Eq '^(field|view|board) .*: (set|created|removed)$' "$dir/out"; then echo 'rerun changed the board'; exit 1; fi

# A drifted filter or table field set is recreated; a roadmap's fields are not compared.
sed 's/|status:Backlog|Priority|/|status:Done|Priority|/; /|Initiatives|/s/|[^|]*$/|Title/; /|Long-lead|/s/|[^|]*$/|Title/' \
  "$S/1/views" > "$dir/v"; cp "$dir/v" "$S/1/views"
run template o
grep -q 'view Backlog: set' "$dir/out"
grep -q 'view Initiatives: set' "$dir/out"
grep -q 'view Long-lead: ok' "$dir/out"
grep -q '|Backlog|table|status:Backlog|Priority|||' "$S/1/views"
[ "$(grep -c '|Backlog|' "$S/1/views")" -eq 1 ]

# A field of the wrong type stops the run instead of being replaced.
cp "$S/1/fields" "$dir/f"
sed 's/|Target|DATE|/|Target|TEXT|/' "$dir/f" > "$S/1/fields"
fails 2 template o
grep -q 'field Target exists with another type' "$dir/out"
cp "$dir/f" "$S/1/fields"

# Check against itself: only the UI-only workflows are missing, nothing written.
snap before
mark
fails 1 --check o 1 o 1
no_writes
grep -q 'workflow item reopened: not set up' "$dir/out"
grep -q 'workflow auto-archive items: not set up' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 2 ]
snap after
diff -r "$dir/before" "$dir/after"
printf 'W|Item reopened|true\nW|Auto-archive items|true\n' >> "$S/1/workflows"
run --check o 1 o 1

# Create: copy, link, Kind and its view; a rerun neither copies nor fails on the link.
run create o 'Project board' o 1 --repo o/r --with-kind
[ "$(cat "$S/2/title")" = 'Project board' ]
grep -q '^project link 2 --owner o --repo o/r$' "$S/log"
grep -q '|Kind|SINGLE_SELECT|o[0-9]*~Work package~BLUE~' "$S/2/fields"
grep -q '|Area|SINGLE_SELECT|o[0-9]*~General~GRAY~No one repository or theme$' "$S/2/fields"
grep -q '|Drafts by kind|table|is:draft|Kind|||Area,Assignees,Priority,Status,Title$' "$S/2/views"
grep -q 'is:issue -label:initiative' "$dir/out"
grep -q 'No access' "$dir/out"
grep -q 'Description: link' "$dir/out"
run create o 'Project board' o 1 --repo o/r --with-kind
grep -q 'exists, not copied again' "$dir/out"
grep -q 'linked to o/r' "$dir/out"
[ "$(boards)" -eq 2 ]

# Kind on an existing board: own options stay, missing ones are added.
# Area's options are the board's own: a rerun neither removes nor adds any.
sed 's/~Idea~GRAY~Not planned yet/~Someday~PINK~Ours/; s/|Area|SINGLE_SELECT|.*/|Area|SINGLE_SELECT|a1~repo-a~BLUE~;a2~repo-b~RED~/' \
  "$S/2/fields" > "$dir/f"; cp "$dir/f" "$S/2/fields"
run create o 'Project board' o 1 --with-kind
grep -q '~Maintainer step~PURPLE~[^;]*;[a-z0-9]*~Someday~PINK~Ours;o[0-9]*~Idea~GRAY~Not planned yet$' "$S/2/fields"
grep -q '|Area|SINGLE_SELECT|a1~repo-a~BLUE~;a2~repo-b~RED~$' "$S/2/fields"

# Only the template is copied: a plain board or a missing one stops the run.
fails 2 create o 'Other' o 2
grep -q 'board 2 of o is not a template' "$dir/out"
fails 2 create o 'Other' o 9
grep -q 'cannot read board 9 of o' "$dir/out"
fails 2 create o 'Other' u 1
grep -q 'u is not an organisation' "$dir/out"
[ "$(boards)" -eq 2 ]

# A user's board is copied across owners from the organisation's template.
run create u 'Mine' o 1
grep -q '^project copy 1 --source-owner o --target-owner u --title Mine' "$S/log"

# Auto-add is required only once the board has a linked repository.
mark
run --check u 3 o 1
no_writes
grep -q 'board 3: no linked repository, auto-add not needed' "$dir/out"
touch "$S/linked_3"
fails 1 --check u 3 o 1
grep -q 'workflow auto-add to project: not set up' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 1 ]

# Check a copy: auto-add is not copied; Kind, its view and a renamed phase are allowed.
mark
fails 1 --check o 2 o 1
no_writes
grep -q 'workflow auto-add to project: not set up' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 1 ]
echo 'W|Auto-add to project|true' >> "$S/2/workflows"
sed 's/~Current phase~/~Phase 1~/' "$S/2/fields" > "$dir/f"; cp "$dir/f" "$S/2/fields"
run --check o 2 o 1

# A board that cannot be read is exit 2, not a difference.
touch "$S/fail_read"
fails 2 --check o 2 o 1
grep -q 'cannot read board 2 of o' "$dir/out"
rm "$S/fail_read"
touch "$S/bad_repos"                     # an unreadable repository count is not "none"
fails 2 --check o 2 o 1
grep -q 'cannot read linked repositories of board 2' "$dir/out"
rm "$S/bad_repos"

# Drift is reported, one line each.
sed 's/;[a-z0-9]*~P3 later~GREEN~When convenient//; s/|Target|DATE|/|Target|TEXT|/' "$S/2/fields" > "$dir/f"; cp "$dir/f" "$S/2/fields"
sed 's/|no:priority -status:Done|/|no:assignee|/; /|Initiatives|/d' "$S/2/views" > "$dir/v"; cp "$dir/v" "$S/2/views"
sed 's/^W|Item closed|true$/W|Item closed|false/' "$S/2/workflows" > "$dir/w"; cp "$dir/w" "$S/2/workflows"
mark
fails 1 --check o 2 o 1
no_writes
grep -q '^- field Priority: is SINGLE_SELECT|P1 now,P2 soon, template has' "$dir/out"
grep -q '^- field Target: is TEXT|, template has DATE|$' "$dir/out"
grep -q '^- view No priority yet: is table|no:assignee' "$dir/out"
grep -q '^- view Initiatives: missing$' "$dir/out"
grep -q '^- workflow item closed: disabled$' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 5 ]
# Sync: a copy that matches the template gets no writes and two reads.
run create o 'Sync board' o 1
[ "$(cat "$S/4/title")" = 'Sync board' ]
mark
run --sync o 4 o 1
no_writes
tail -n 1 "$dir/out" | grep -q 'nothing to do'
grep -q '^Steps with no API.*/orgs/o/projects/4/workflows' "$dir/out"
[ "$(tail -n "+$((start + 1))" "$S/log" | grep -c '^api graphql -f query=query')" -eq 2 ]
fails 2 --sync o 4 o 1 --force
fails 2 --sync o 4 o

# Sync a drifted board: a missing field, options and views are added; what
# differs or is extra is reported and left as it is. Phase gets only Later.
f4="$S/4/fields"; v4="$S/4/views"
sed -e '/|Waiting for|TEXT|/d' -e 's/|Target|DATE|/|Target|TEXT|/' \
  -e 's/\(|Priority|SINGLE_SELECT|[a-z0-9]*~P1 now~\)RED~[^;]*/\1PINK~Ours: "urgent"%3B now/' \
  -e 's/;[a-z0-9]*~P3 later~GREEN~When convenient//' \
  -e 's/|Phase|SINGLE_SELECT|.*/|Phase|SINGLE_SELECT|ph1~Phase 1~BLUE~;ph2~Phase 2~GREEN~/' \
  -e '/|Status|/s/$/;sx~Blocked~RED~Ours/' "$f4" > "$dir/f"
echo 'F|PVTF_90|190|Estimate|NUMBER|' >> "$dir/f"
cp "$dir/f" "$f4"
sed -e '/|In flight|/d; /|Initiatives|/d' -e 's/|no:priority -status:Done|/|no:assignee|/' "$v4" > "$dir/v"
echo 'V|PVTV_99|Mine|table|assignee:@me||||Title' >> "$dir/v"
cp "$dir/v" "$v4"
sed 's/^W|Item closed|true$/W|Item closed|false/' "$S/4/workflows" > "$dir/w"; cp "$dir/w" "$S/4/workflows"
prio=$(grep '|Priority|' "$f4"); status=$(grep '|Status|' "$f4")

# Dry run: the same additions printed, nothing written.
snap before
mark
run --sync o 4 o 1 --dry-run
no_writes
snap after
diff -r "$dir/before" "$dir/after"
grep -qx 'field Waiting for: would add (TEXT)' "$dir/out"
grep -qx 'field Priority: would add option P3 later' "$dir/out"
grep -qx 'field Phase: would add option Later' "$dir/out"
grep -qx 'view In flight: would add' "$dir/out"
grep -qx 'view Initiatives: would add' "$dir/out"
[ "$(grep -c ': would add' "$dir/out")" -eq 5 ]
tail -n 1 "$dir/out" | grep -q 'dry run'

mark
run --sync o 4 o 1
grep -qx 'field Waiting for: added' "$dir/out"
grep -qx 'field Priority: option P3 later added' "$dir/out"
grep -qx 'field Phase: option Later added' "$dir/out"
grep -qx 'view In flight: added' "$dir/out"
grep -qx 'view Initiatives: added' "$dir/out"
grep -qx 'field Target: differs (board TEXT, template DATE)' "$dir/out"
grep -qx 'field Estimate: extra, not in the template' "$dir/out"
grep -qx 'field Status: option Blocked extra, not in the template' "$dir/out"
grep -q '^field Priority: option P1 now differs (board PINK|Ours: "urgent"%3B now, template RED|Blocks' "$dir/out"
grep -q '^view No priority yet: differs (board table|no:assignee|' "$dir/out"
grep -qx 'view Mine: extra, not in the template' "$dir/out"
grep -qx -e '- workflow item closed: disabled; set it up as in template 1 of o.' "$dir/out"
if grep -Eq 'Kind|Area|Current phase|Phase [12]|Drafts by kind' "$dir/out"; then echo 'sync reported a board-local field, option or view'; exit 1; fi
# Writes: one field, one options update per changed field, two views; no deletes or renames.
tail -n "+$((start + 1))" "$S/log" > "$dir/w"
[ "$(grep -c '^project field-create 4 --owner o --name Waiting for --data-type TEXT$' "$dir/w")" -eq 1 ]
[ "$(grep -c '^project ' "$dir/w")" -eq 1 ]
[ "$(grep -c 'updateProjectV2Field' "$dir/w")" -eq 2 ]
[ "$(grep -c '^api -X POST orgs/o/projectsV2/4/views' "$dir/w")" -eq 2 ]
[ "$(grep -c 'mutation' "$dir/w")" -eq 2 ]
[ "$(grep -c '^api graphql -f query=query' "$dir/w")" -eq 3 ]   # board, template, board after the new field
# Existing options keep id, name, colour, description and place; new ones are appended.
awk -v p="$prio" 'index($0, p ";") == 1' "$f4" | grep -q ';o[0-9]*~P3 later~GREEN~When convenient$'
grep -qxF "$status" "$f4"
grep -q '|Phase|SINGLE_SELECT|ph1~Phase 1~BLUE~;ph2~Phase 2~GREEN~;o[0-9]*~Later~GRAY~Not in a planned phase$' "$f4"
grep -q '|Waiting for|TEXT|$' "$f4"
grep -q '|Target|TEXT|$' "$f4"
grep -q '|Estimate|NUMBER|$' "$f4"
grep -q '|In flight|board|-status:Backlog,Parked,Done||Status||Assignees,Phase,Priority,Title,Waiting for$' "$v4"
grep -q '|Initiatives|table|label:initiative||||Repository,Status,Sub-issues progress,Title$' "$v4"
[ "$(grep -c '|No priority yet|table|no:assignee|' "$v4")" -eq 1 ]
grep -q '|Mine|' "$v4"
# Visible fields keep the order of VIEWS, with the new field's id.
ids=$(for f in Title Assignees Priority Phase 'Waiting for'; do awk -F'|' -v n="$f" '$4 == n {print $3}' "$f4"; done | paste -sd, -)
grep -qF "\"name\":\"In flight\",\"layout\":\"board\",\"visible_fields\":[$ids]," "$S/posts"

# A second sync writes nothing and still reports the differences.
snap before
mark
run --sync o 4 o 1
no_writes
snap after
diff -r "$dir/before" "$dir/after"
grep -qx 'field Target: differs (board TEXT, template DATE)' "$dir/out"
grep -q '^field Priority: option P1 now differs (board PINK|Ours: "urgent"%3B now, template RED|' "$dir/out"
grep -q '|Priority|SINGLE_SELECT|o[0-9]*~P1 now~RED~Blocks' "$S/1/fields"   # the template is untouched
tail -n 1 "$dir/out" | grep -q 'nothing to do'

# A missing single-select field is created with the template's colours and
# descriptions; a missing Phase gets only Later. A user's board works too.
sed '/|Phase|SINGLE_SELECT|/d' "$S/3/fields" > "$dir/f"; cp "$dir/f" "$S/3/fields"
mark
run --sync u 3 o 1
grep -qx 'field Phase: added' "$dir/out"
grep -q '|Phase|SINGLE_SELECT|o[0-9]*~Later~GRAY~Not in a planned phase$' "$S/3/fields"
grep -q '^project field-create 3 --owner u --name Phase --data-type SINGLE_SELECT --single-select-options Later$' "$S/log"
grep -qx -e '- workflow auto-add to project: not set up; set it up as in template 1 of o.' "$dir/out"
mark
run --sync u 3 o 1
no_writes

# A board that cannot be read is exit 2.
touch "$S/fail_read"
fails 2 --sync o 4 o 1
grep -q 'cannot read board 4 of o' "$dir/out"
rm "$S/fail_read"

# Threads: the thread profile goes on the shared board only, never the template.
run create o 'Shared' o 1 --threads
[ "$(cat "$S/5/title")" = 'Shared' ]
grep -q '|Focus|SINGLE_SELECT|o[0-9]*~Now~RED~Being worked this week;o[0-9]*~Next~YELLOW~Starts when a Now thread ends;o[0-9]*~Later~GRAY~Not before the next review;o[0-9]*~Parked~PINK~Set aside on purpose$' "$S/5/fields"
grep -q '|Rank|NUMBER|$' "$S/5/fields"
grep -q '|Next step|TEXT|$' "$S/5/fields"
grep -q '|Threads|table|focus:Now,Next,Later,Parked|Focus||Rank:ASC|Assignees,Focus,Next step,Priority,Status,Sub-issues progress,Title,Waiting for$' "$S/5/views"
grep -q '|Threads by focus|board|focus:Now,Next,Later||Focus|Rank:ASC|Next step,Priority,Sub-issues progress,Title,Waiting for$' "$S/5/views"
if grep -Eq '\|(Focus|Rank|Next step)\|' "$S/1/fields"; then echo 'thread field on the template'; exit 1; fi
snap first
run create o 'Shared' o 1 --threads
snap second
diff -r "$dir/first" "$dir/second"
if grep -Eq ': (set|created)$' "$dir/out"; then echo 'threads rerun changed the board'; exit 1; fi

# Check with the thread profile passes; without it the thread fields are extra.
printf 'W|Item reopened|true\nW|Auto-archive items|true\n' >> "$S/5/workflows"
mark
run --check o 5 o 1 --threads
no_writes
grep -q 'board 5 matches template 1 with the thread profile' "$dir/out"
fails 1 --check o 5 o 1
no_writes
grep -q '^- field Focus: not in the template$' "$dir/out"
grep -q '^- field Rank: not in the template$' "$dir/out"
grep -q '^- field Next step: not in the template$' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 3 ]
fails 2 --check o 5 o 1 --other

# Focus on an existing board: own options stay, missing ones are added.
sed 's/~Later~GRAY~Not before the next review/~Someday~PINK~Ours/' "$S/5/fields" > "$dir/f"; cp "$dir/f" "$S/5/fields"
run create o 'Shared' o 1 --threads
grep -q '~Next~YELLOW~[^;]*;[a-z0-9]*~Someday~PINK~Ours;o[0-9]*~Parked~PINK~Set aside on purpose;o[0-9]*~Later~GRAY~Not before the next review$' "$S/5/fields"
run --check o 5 o 1 --threads

# A Focus field with three options lacks Parked: check says so, a rerun adds it.
sed 's/;o[0-9]*~Parked~PINK~Set aside on purpose//' "$S/5/fields" > "$dir/f"; cp "$dir/f" "$S/5/fields"
if grep "|Focus|" "$S/5/fields" | grep -q "~Parked~"; then echo "Parked not removed"; exit 1; fi
mark
fails 1 --check o 5 o 1 --threads
no_writes
grep -q '^- field Focus: is SINGLE_SELECT|.*, want SINGLE_SELECT with Now,Next,Later,Parked$' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 1 ]
run create o 'Shared' o 1 --threads
grep -q '~Someday~PINK~Ours;o[0-9]*~Later~GRAY~Not before the next review;o[0-9]*~Parked~PINK~Set aside on purpose$' "$S/5/fields"
run --check o 5 o 1 --threads

# Focus options match without regard to case, as create does.
sed 's/~Now~RED~/~now~RED~/' "$S/5/fields" > "$dir/f"; cp "$dir/f" "$S/5/fields"
grep -q '~now~RED~' "$S/5/fields"
run --check o 5 o 1 --threads

# Thread drift is reported, one line each, without writing.
sed '/|Threads by focus|/d' "$S/5/views" > "$dir/v"; cp "$dir/v" "$S/5/views"
sed 's/|Rank|NUMBER|/|Rank|TEXT|/' "$S/5/fields" > "$dir/f"; cp "$dir/f" "$S/5/fields"
mark
fails 1 --check o 5 o 1 --threads
no_writes
grep -q 'board 5 differs from template 1 with the thread profile:' "$dir/out"
grep -q '^- field Rank: is TEXT, want NUMBER$' "$dir/out"
grep -q '^- view Threads by focus: missing$' "$dir/out"
[ "$(grep -c '^- ' "$dir/out")" -eq 2 ]
echo "ensure-board self-test passed"
