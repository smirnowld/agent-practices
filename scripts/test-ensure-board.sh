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
# fail_read make listing or reading boards fail.
cat > "$dir/bin/gh" <<'FAKE'
#!/bin/sh
S=$FAKE_STATE
printf '%s\n' "$*" >> "$S/log"
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
          name=$(printf '%s' "$line" | sed 's/.*name:"\([^"]*\)".*/\1/')
          colour=$(printf '%s' "$line" | sed 's/.*color:\([A-Z]*\).*/\1/')
          desc=$(printf '%s' "$line" | sed 's/.*description:"\([^"]*\)".*/\1/')
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
    cp "$S/$3/fields" "$S/$3/views" "$S/$n/"
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
echo "ensure-board self-test passed"
