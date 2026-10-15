#!/bin/sh
# Create, copy and audit GitHub Projects boards (practices/tracking.md, baseline R7).
# Usage:
#   ensure-board.sh template OWNER
#     Create or update the board "Board template" under the organisation OWNER
#     and mark it a template (GitHub allows templates in organisations only).
#   ensure-board.sh create OWNER TITLE TEMPLATE_OWNER TEMPLATE_NUMBER [--repo OWNER/REPO] [--with-kind] [--threads]
#     Copy the template into a board under OWNER (a user or an organisation),
#     link the repository; --with-kind adds the Kind and Area fields and a
#     Drafts by kind view; --threads adds the thread profile of the shared
#     board (Focus, Rank and Next step fields, Threads views).
#   ensure-board.sh --check OWNER NUMBER TEMPLATE_OWNER TEMPLATE_NUMBER [--threads]
#     Read-only: compare a board with the template, and with --threads also
#     with the thread profile. Exit 1 lists the differences; exit 2 means a
#     board could not be read.
# Workflows, auto-add, the description and the base role have no API; the
# script prints them as steps.
set -eu

TEMPLATE_TITLE='Board template'

# Single-select options: name|colour|description|old name kept by id.
# Status renames GitHub's built-in Todo, In Progress and Done in place, so the
# built-in workflows keep pointing at them.
STATUS_OPTIONS='Backlog|GRAY|Filed, not in the current phase|Todo
Planned|PURPLE|In the phase plan, not yet briefed|
Ready|BLUE|Briefed, can start|
In progress|YELLOW|A session is on it|
In review|ORANGE|A PR is open|
Waiting|RED|Needs something outside the session, see Waiting for|
Parked|PINK|Out of scope for now|
Done|GREEN|Closed, archived after two weeks|'
PRIORITY_OPTIONS='P1 now|RED|Blocks planned work, or risks users or data|
P2 soon|YELLOW|Belongs in the current or next phase|
P3 later|GREEN|When convenient|'
PHASE_OPTIONS='Current phase|BLUE|Renamed to the phase plan the package sits in|
Later|GRAY|Not in a planned phase|'
KIND_OPTIONS='Work package|BLUE|A package in a phase plan|
Finding|ORANGE|A review finding|
Maintainer step|PURPLE|A step only the maintainer can take|
Idea|GRAY|Not planned yet|'
# Area: which repository or theme a draft belongs to. Its options are each
# board's own, so a new field gets one placeholder and reruns never touch it.
AREA_OPTIONS='General|GRAY|No one repository or theme|'

# Views: name|layout|filter|group by|columns|sort|visible fields.
# A roadmap ignores the visible fields it is given, so they are not compared.
VIEWS='In flight|board|-status:Backlog,Parked,Done||Status||Title,Assignees,Priority,Phase,Waiting for
Assigned to me|table|assignee:@me -status:Done|||Priority:ASC|Title,Status,Priority,Waiting for,Repository
Phase|table|label:work-package|Phase|||Title,Status,Priority,Linked pull requests,Waiting for
Backlog|table|status:Backlog|Priority|||Title,Labels,Priority,Repository
No priority yet|table|no:priority -status:Done||||Title,Status,Labels,Repository
Long-lead|roadmap|label:long-lead|||Target:ASC|Title,Status,Assignees,Target,Waiting for
Initiatives|table|label:initiative||||Title,Status,Sub-issues progress,Repository'
# Drafts carry no labels, and a filter cannot OR a label with a field, so a
# board with drafts gets one more view instead of changed filters.
KIND_VIEW='Drafts by kind|table|is:draft|Kind|||Title,Status,Priority,Assignees,Area'
# Thread profile: Focus, Rank and Next step plus these views, only on the
# shared board, never on the template (practices/tracking.md, Threads).
FOCUS_OPTIONS='Now|RED|Being worked this week|
Next|YELLOW|Starts when a Now thread ends|
Later|GRAY|Not before the next review|'
THREAD_VIEWS='Threads|table|focus:Now,Next,Later,Parked|Focus||Rank:ASC|Title,Focus,Priority,Status,Assignees,Waiting for,Next step,Sub-issues progress
Threads by focus|board|focus:Now,Next,Later||Focus|Rank:ASC|Title,Priority,Waiting for,Next step,Sub-issues progress'

# One GraphQL read per board, flattened to lines:
#   P|id|template|title
#   F|id|databaseId|name|dataType|optionId~name~colour~description;...
#   V|id|name|layout|filter|group by|columns|field:direction|visible fields, sorted
#   W|name|enabled
#   R|number of linked repositories
BOARD_QUERY='projectV2(number:$n){id title template
fields(first:50){nodes{...on ProjectV2FieldCommon{id databaseId name dataType}
...on ProjectV2SingleSelectField{options{id name color description}}}}
views(first:50){nodes{id name layout filter
fields(first:50){nodes{...on ProjectV2FieldCommon{name}}}
groupByFields(first:5){nodes{...on ProjectV2FieldCommon{name}}}
verticalGroupByFields(first:5){nodes{...on ProjectV2FieldCommon{name}}}
sortByFields(first:5){nodes{direction field{...on ProjectV2FieldCommon{name}}}}}}
workflows(first:50){nodes{name enabled}}
repositories(first:1){totalCount}}'
BOARD_JQ='.data[].projectV2 |
"P|\(.id)|\(.template)|\(.title)",
(.fields.nodes[] | "F|\(.id)|\(.databaseId)|\(.name)|\(.dataType)|\((.options // []) | map("\(.id)~\(.name)~\(.color)~\(.description)") | join(";"))"),
(.views.nodes[] | "V|\(.id)|\(.name)|\(.layout | sub("_LAYOUT$"; "") | ascii_downcase)|\(.filter // "")|\([.groupByFields.nodes[].name] | join(","))|\([.verticalGroupByFields.nodes[].name] | join(","))|\([.sortByFields.nodes[] | "\(.field.name):\(.direction)"] | join(","))|\([.fields.nodes[].name] | sort | join(","))"),
(.workflows.nodes[] | "W|\(.name)|\(.enabled)"),
"R|\(.repositories.totalCount)"'

die() { echo "ensure-board: $*" >&2; exit 2; }
usage() { sed -n '/^# Usage:/,/^# Workflows/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

owner_kind() { # OWNER -> "Organization|id" or "User|id"
  gh api "users/$1" --jq '"\(.type)|\(.id)"' </dev/null || die "cannot read owner $1"
}

# Sets key (GraphQL owner field), rest (REST prefix) and web (board URL prefix).
owner_info() {
  info=$(owner_kind "$owner")
  case $info in
    Organization\|*) key=organization; rest="orgs/$owner"; web="https://github.com/orgs/$owner" ;;
    *) key=user; rest="users/${info#*|}"; web="https://github.com/users/$owner" ;;
  esac
}

read_board() { # NUMBER FILE [OWNER KEY]
  gh api graphql -f query="query(\$o:String!,\$n:Int!){${4:-$key}(login:\$o){$BOARD_QUERY}}" \
    -f o="${3:-$owner}" -F n="$1" --jq "$BOARD_JQ" > "$2" </dev/null ||
    die "cannot read board $1 of ${3:-$owner}"
  grep -q '^P|' "$2" || die "cannot read board $1 of ${3:-$owner}"
}

# Reads the template board into FILE and stops unless it is the template.
read_template() { # OWNER NUMBER FILE
  tinfo=$(owner_kind "$1")
  case $tinfo in
    Organization\|*) read_board "$2" "$3" "$1" organization ;;
    *) die "$1 is not an organisation, so it holds no template" ;;
  esac
  [ "$(awk -F'|' '$1 == "P" {print $3 "|" $4}' "$3")" = "true|$TEMPLATE_TITLE" ] ||
    die "board $2 of $1 is not a template titled \"$TEMPLATE_TITLE\""
}

field_line() { awk -F'|' -v n="$2" '$1 == "F" && $4 == n' "$1"; }
field_id() { awk -F'|' -v n="$2" '$1 == "F" && $4 == n {print $3; exit}' "$1"; }
sorted() { printf '%s\n' "$1" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -; }

find_board() { # TITLE -> sets found to its number, or empty
  gh project list --owner "$owner" --limit 500 --format json \
    --jq '.projects[] | "\(.number)|\(.title)"' > "$tmp/list" </dev/null ||
    die "cannot list the boards of $owner"
  found=$(awk -F'|' -v t="$1" '$2 == t {print $1; exit}' "$tmp/list")
}

# Set a single-select field's options to SPEC, keeping the id of each option
# whose name (or old name) already exists, so items and workflows keep it.
# With "add", existing options stay as they are and missing ones are appended.
sync_options() { # FILE FIELD SPEC [add]
  line=$(field_line "$1" "$2")
  [ -n "$line" ] || die "no field $2"
  fid=$(printf '%s\n' "$line" | cut -d'|' -f2)
  printf '%s\n' "$line" | cut -d'|' -f6 | tr ';' '\n' > "$tmp/opts"
  have=$(awk -F'~' 'NF {printf "%s%s~%s~%s", (n++ ? ";" : ""), $2, $3, $4}' "$tmp/opts")
  spec=$3
  if [ "${4:-}" = add ]; then
    spec=$(awk -F'~' 'NF {print $2 "|" $3 "|" $4 "|"}' "$tmp/opts"
      printf '%s\n' "$3" | while IFS='|' read -r name rest_of; do
          if ! awk -F'~' -v n="$name" 'tolower($2) == tolower(n) {f = 1} END {exit !f}' "$tmp/opts"; then
            echo "$name|$rest_of"
          fi
        done)
  fi
  literal=''
  want=''
  while IFS='|' read -r name colour desc old; do
    id=$(awk -F'~' -v n="$name" -v o="$old" \
      'tolower($2) == tolower(n) || (o != "" && $2 == o) {print $1; exit}' "$tmp/opts")
    item="name:\"$name\",color:$colour,description:\"$desc\""
    if [ -n "$id" ]; then item="id:\"$id\",$item"; fi
    literal="$literal${literal:+,}{$item}"
    want="$want${want:+;}$name~$colour~$desc"
  done <<EOF
$spec
EOF
  if [ "$have" = "$want" ]; then echo "field $2: ok"; return 0; fi
  gh api graphql -f query="mutation{updateProjectV2Field(input:{fieldId:\"$fid\",singleSelectOptions:[$literal]}){projectV2Field{...on ProjectV2SingleSelectField{id}}}}" \
    >/dev/null </dev/null
  echo "field $2: set"
}

ensure_field() { # NUMBER FILE NAME TYPE [SPEC [add]]
  line=$(field_line "$2" "$3")
  if [ -z "$line" ]; then
    if [ "$4" = SINGLE_SELECT ]; then
      names=$(printf '%s\n' "$5" | cut -d'|' -f1 | paste -sd, -)
      gh project field-create "$1" --owner "$owner" --name "$3" \
        --data-type SINGLE_SELECT --single-select-options "$names" >/dev/null </dev/null
    else
      gh project field-create "$1" --owner "$owner" --name "$3" \
        --data-type "$4" >/dev/null </dev/null
    fi
    echo "field $3: created"
    read_board "$1" "$2"
    set -- "$1" "$2" "$3" "$4" "${5:-}"   # a new field takes the whole list
  elif [ "$(printf '%s\n' "$line" | cut -d'|' -f5)" != "$4" ]; then
    die "field $3 exists with another type; change or delete it in the UI"
  fi
  case ${6:-} in
    keep) ;;   # an existing field keeps its own options untouched
    *) if [ "$4" = SINGLE_SELECT ]; then sync_options "$2" "$3" "$5" "${6:-}"; fi ;;
  esac
}

delete_view() { # VIEW_ID
  gh api graphql -f query="mutation{deleteProjectV2View(input:{viewId:\"$1\"}){clientMutationId}}" \
    >/dev/null </dev/null
}

create_view() { # NUMBER FILE NAME LAYOUT FILTER GROUP COLUMNS SORT VISIBLE
  ids=''
  oldifs=$IFS
  IFS=','
  for f in $9; do
    id=$(field_id "$2" "$f")
    if [ -n "$id" ]; then ids="$ids${ids:+,}$id"; else echo "view $3: no field $f to show" >&2; fi
  done
  IFS=$oldifs
  json="{\"name\":\"$3\",\"layout\":\"$4\",\"visible_fields\":[$ids]"
  if [ -n "$5" ]; then json="$json,\"filter\":\"$5\""; fi
  if [ -n "$6" ]; then json="$json,\"group_by\":[$(field_id "$2" "$6")]"; fi
  if [ -n "$7" ]; then json="$json,\"vertical_group_by\":[$(field_id "$2" "$7")]"; fi
  if [ -n "$8" ]; then
    dir=$(printf '%s' "${8#*:}" | tr 'A-Z' 'a-z')
    json="$json,\"sort_by\":[[$(field_id "$2" "${8%:*}"),\"$dir\"]]"
  fi
  printf '%s}' "$json" > "$tmp/view.json"
  gh api -X POST "$rest/projectsV2/$1/views" --input "$tmp/view.json" >/dev/null </dev/null
}

ensure_views() { # NUMBER FILE SPEC [prune]
  while IFS='|' read -r name layout filter group cols sort visible; do
    want="$layout|$filter|$group|$cols|$sort"
    if [ "$layout" != roadmap ]; then want="$want|$(sorted "$visible")"; fi
    cur=$(awk -F'|' -v n="$name" -v r="$layout" '$1 == "V" && $3 == n {
      s = $4 "|" $5 "|" $6 "|" $7 "|" $8; if (r != "roadmap") s = s "|" $9; print s; exit}' "$2")
    vid=$(awk -F'|' -v n="$name" '$1 == "V" && $3 == n {print $2; exit}' "$2")
    if [ -n "$vid" ] && [ "$cur" = "$want" ]; then
      echo "view $name: ok"
      continue
    fi
    if [ -n "$vid" ]; then delete_view "$vid"; fi
    create_view "$1" "$2" "$name" "$layout" "$filter" "$group" "$cols" "$sort" "$visible"
    echo "view $name: set"
  done <<EOF
$3
EOF
  if [ "${4:-}" != prune ]; then return 0; fi
  printf '%s\n' "$3" | cut -d'|' -f1 > "$tmp/names"
  read_board "$1" "$2"
  awk -F'|' 'NR == FNR {keep[$0] = 1; next} $1 == "V" && !($3 in keep) {print $2 "|" $3}' \
    "$tmp/names" "$2" > "$tmp/extra"
  while IFS='|' read -r vid name; do
    delete_view "$vid"
    echo "view $name: removed"
  done < "$tmp/extra"
}

template_mode() {
  owner_info
  [ "$key" = organization ] ||
    die "$owner is a user; GitHub allows template boards in organisations only"
  find_board "$TEMPLATE_TITLE"
  number=$found
  if [ -z "$number" ]; then
    number=$(gh project create --owner "$owner" --title "$TEMPLATE_TITLE" \
      --format json --jq .number </dev/null)
    echo "board $number: created"
  fi
  b="$tmp/board"
  read_board "$number" "$b"
  sync_options "$b" Status "$STATUS_OPTIONS"
  ensure_field "$number" "$b" Priority SINGLE_SELECT "$PRIORITY_OPTIONS"
  ensure_field "$number" "$b" 'Waiting for' TEXT
  ensure_field "$number" "$b" Phase SINGLE_SELECT "$PHASE_OPTIONS"
  ensure_field "$number" "$b" Target DATE
  read_board "$number" "$b"
  ensure_views "$number" "$b" "$VIEWS" prune
  if [ "$(awk -F'|' '$1 == "P" {print $3}' "$b")" != true ]; then
    gh project mark-template "$number" --owner "$owner" >/dev/null </dev/null
    echo "board $number: marked as template"
  fi
  echo "template board $number: $web/projects/$number"
  cat <<EOF
Steps with no API, in the board's Workflows settings ($web/projects/$number/workflows):
- Item added to project: set Status to Backlog.
- Item closed: set Status to Done.
- Item reopened: turn on, set Status to Backlog.
- Auto-archive items: turn on, archive closed items after 14 days.
- Pull request linked to issue: set Status to In review (or turn it off).
- Long-lead view: check its roadmap dates use Target.
EOF
}

create_mode() {
  title=$1; towner=$2; tpl=$3; shift 3
  repo=''; kind=0; threads=0
  while [ $# -gt 0 ]; do
    case $1 in
      --repo) [ $# -ge 2 ] || usage; repo=$2; shift ;;
      --with-kind) kind=1 ;;
      --threads) threads=1 ;;
      *) usage ;;
    esac
    shift
  done
  owner_info
  read_template "$towner" "$tpl" "$tmp/tpl"
  find_board "$title"
  number=$found
  if [ -n "$number" ]; then
    echo "board $number: exists, not copied again"
  else
    number=$(gh project copy "$tpl" --source-owner "$towner" --target-owner "$owner" \
      --title "$title" --format json --jq .number </dev/null)
    echo "board $number: copied from template $tpl of $towner"
  fi
  b="$tmp/board"
  read_board "$number" "$b"
  pid=$(awk -F'|' '$1 == "P" {print $2}' "$b")
  gh api graphql -f query="mutation{updateProjectV2(input:{projectId:\"$pid\",public:false}){projectV2{id}}}" \
    >/dev/null </dev/null
  echo "board $number: private"
  if [ -n "$repo" ]; then
    if ! gh project link "$number" --owner "$owner" --repo "$repo" > "$tmp/link" 2>&1 </dev/null; then
      grep -qi 'already' "$tmp/link" || { cat "$tmp/link" >&2; die "cannot link $repo"; }
    fi
    echo "board $number: linked to $repo"
  fi
  if [ "$kind" -eq 1 ]; then
    ensure_field "$number" "$b" Kind SINGLE_SELECT "$KIND_OPTIONS" add
    ensure_field "$number" "$b" Area SINGLE_SELECT "$AREA_OPTIONS" keep
    read_board "$number" "$b"
    ensure_views "$number" "$b" "$KIND_VIEW"
  fi
  if [ "$threads" -eq 1 ]; then
    ensure_field "$number" "$b" Focus SINGLE_SELECT "$FOCUS_OPTIONS" add
    ensure_field "$number" "$b" Rank NUMBER
    ensure_field "$number" "$b" 'Next step' TEXT
    read_board "$number" "$b"
    ensure_views "$number" "$b" "$THREAD_VIEWS"
  fi
  echo "board $number: $web/projects/$number"
  echo "Steps with no API, in the board's settings ($web/projects/$number/settings):"
  if [ -n "$repo" ]; then
    echo "- Workflows > Auto-add to project: repository $repo, filter is:issue -label:initiative."
  fi
  echo "- Manage access: set the base role to No access."
  echo "- Description: link the board's Assigned to me view and the project's docs/questions.md (for a public repository's board, leave the repository link out)."
  echo "- Workflows: check Item added, Item closed, Item reopened and Auto-archive items match the template."
}

# Field line for comparison: name|type|option names. Phase options are the
# project's own phase plans, so only its "Later" option is compared.
fields_summary() {
  awk -F'|' '$1 == "F" {
    n = split($6, o, ";"); names = ""
    for (i = 1; i <= n; i++) { split(o[i], p, "~"); names = names (i > 1 ? "," : "") p[2] }
    if ($4 == "Phase") names = (index("," names ",", ",Later,") ? "...,Later" : names)
    print $4 "|" $5 "|" names
  }' "$1"
}

# Thread profile on a board: fields by type, views as ensure_views compares them.
check_threads() { # BOARD_FILE FIELDS_SUMMARY
  got=$(awk -F'|' '$1 == "Focus" {print $2 "|" $3; exit}' "$2")
  if [ -z "$got" ]; then
    echo "field Focus: missing" >> "$tmp/diff"
  else
    ok=1
    case $got in SINGLE_SELECT\|*) ;; *) ok=0 ;; esac
    opts=$(printf '%s' "${got#*|}" | tr '[:upper:]' '[:lower:]')
    for o in now next later; do
      case ",$opts," in *",$o,"*) ;; *) ok=0 ;; esac
    done
    if [ "$ok" -eq 0 ]; then
      echo "field Focus: is $got, want SINGLE_SELECT with Now,Next,Later" >> "$tmp/diff"
    fi
  fi
  for ft in Rank:NUMBER 'Next step:TEXT'; do
    name=${ft%:*}; type=${ft##*:}
    got=$(awk -F'|' -v n="$name" '$1 == n {print $2; exit}' "$2")
    if [ -z "$got" ]; then
      echo "field $name: missing" >> "$tmp/diff"
    elif [ "$got" != "$type" ]; then
      echo "field $name: is $got, want $type" >> "$tmp/diff"
    fi
  done
  while IFS='|' read -r name layout filter group cols sort visible; do
    want="$layout|$filter|$group|$cols|$sort"
    if [ "$layout" != roadmap ]; then want="$want|$(sorted "$visible")"; fi
    cur=$(awk -F'|' -v n="$name" -v r="$layout" '$1 == "V" && $3 == n {
      s = $4 "|" $5 "|" $6 "|" $7 "|" $8; if (r != "roadmap") s = s "|" $9; print s; exit}' "$1")
    if [ -z "$cur" ]; then
      echo "view $name: missing" >> "$tmp/diff"
    elif [ "$cur" != "$want" ]; then
      echo "view $name: is $cur, want $want" >> "$tmp/diff"
    fi
  done <<EOF
$THREAD_VIEWS
EOF
}

check_mode() {
  number=$1; towner=$2; tpl=$3; threads=${4:-0}
  owner_info
  read_board "$number" "$tmp/board"
  read_template "$towner" "$tpl" "$tmp/tpl"
  : > "$tmp/diff"
  fields_summary "$tmp/tpl" > "$tmp/tf"
  fields_summary "$tmp/board" > "$tmp/bf"
  while IFS='|' read -r name type opts; do
    got=$(awk -F'|' -v n="$name" '$1 == n {print $2 "|" $3; exit}' "$tmp/bf")
    if [ -z "$got" ]; then
      echo "field $name: missing" >> "$tmp/diff"
    elif [ "$got" != "$type|$opts" ]; then
      echo "field $name: is $got, template has $type|$opts" >> "$tmp/diff"
    fi
  done < "$tmp/tf"
  awk -F'|' -v th="$threads" 'NR == FNR {t[$1] = 1; next}
    !($1 in t) && $1 != "Kind" && $1 != "Area" &&
    !(th && ($1 == "Focus" || $1 == "Rank" || $1 == "Next step")) {print "field " $1 ": not in the template"}' \
    "$tmp/tf" "$tmp/bf" >> "$tmp/diff"
  awk -F'|' '$1 == "V" {print $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8 "|" $9}' "$tmp/tpl" > "$tmp/tv"
  while IFS='|' read -r name rest_of; do
    got=$(awk -F'|' -v n="$name" '$1 == "V" && $3 == n {print $4 "|" $5 "|" $6 "|" $7 "|" $8 "|" $9; exit}' "$tmp/board")
    if [ -z "$got" ]; then
      echo "view $name: missing" >> "$tmp/diff"
    elif [ "$got" != "$rest_of" ]; then
      echo "view $name: is $got, template has $rest_of" >> "$tmp/diff"
    fi
  done < "$tmp/tv"
  if [ "$threads" -eq 1 ]; then check_threads "$tmp/board" "$tmp/bf"; profile=' with the thread profile'; else profile=''; fi
  # Workflow names as GitHub lists them; one not yet configured is not listed.
  # "Auto-add to project" follows the settings page (unverified through the API).
  wanted='item added to project
item closed
item reopened
auto-archive items'
  # Auto-add needs a linked repository; the shared board may have none.
  # "Linked" stands in for "should auto-add": a board linked only for display is still asked.
  repos=$(awk -F'|' '$1 == "R" {print $2}' "$tmp/board")
  case $repos in
    ''|*[!0-9]*) die "cannot read linked repositories of board $number" ;;
  esac
  if [ "$repos" -gt 0 ]; then
    wanted="$wanted
auto-add to project"
  else
    echo "board $number: no linked repository, auto-add not needed"
  fi
  while IFS= read -r wf; do
    state=$(awk -F'|' -v n="$wf" '$1 == "W" && tolower($2) == n {print $3; exit}' "$tmp/board")
    case $state in
      true) ;;
      '') echo "workflow $wf: not set up" >> "$tmp/diff" ;;
      *) echo "workflow $wf: disabled" >> "$tmp/diff" ;;
    esac
  done <<EOF
$wanted
EOF
  echo "Not checked (no API): workflow settings, the auto-add filter, the description, the base role."
  if [ -s "$tmp/diff" ]; then
    echo "board $number differs from template $tpl$profile:"
    sed 's/^/- /' "$tmp/diff"
    exit 1
  fi
  echo "board $number matches template $tpl$profile"
}

case ${1:-} in
  template) [ $# -eq 2 ] || usage; owner=$2; template_mode ;;
  create) [ $# -ge 5 ] || usage; owner=$2; shift 2; create_mode "$@" ;;
  --check)
    case $#:${6:-} in
      5:) owner=$2; check_mode "$3" "$4" "$5" ;;
      6:--threads) owner=$2; check_mode "$3" "$4" "$5" 1 ;;
      *) usage ;;
    esac ;;
  *) usage ;;
esac
