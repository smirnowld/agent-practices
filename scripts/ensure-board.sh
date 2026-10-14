#!/bin/sh
# Create, copy and audit GitHub Projects boards (practices/tracking.md, baseline R7).
# Usage:
#   ensure-board.sh template OWNER
#     Create or update the board "Board template" under OWNER and mark it a template.
#   ensure-board.sh create OWNER TITLE TEMPLATE_NUMBER [--repo OWNER/REPO] [--with-kind]
#     Copy the template into a new board, link the repository, add the Kind field.
#   ensure-board.sh --check OWNER NUMBER TEMPLATE_NUMBER
#     Read-only: compare a board with the template; exit 1 listing the differences.
# Workflows, auto-add and the base role have no API; the script prints them as steps.
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

# Views: name|layout|filter|group by|columns|sort|visible fields.
VIEWS='In flight|board|-status:Backlog,Parked,Done||Status||Title,Assignees,Priority,Phase,Waiting for
Assigned to me|table|assignee:@me -status:Done|||Priority:ASC|Title,Status,Priority,Waiting for,Repository
Phase|table|label:work-package|Phase|||Title,Status,Priority,Linked pull requests,Waiting for
Backlog|table|status:Backlog|Priority|||Title,Labels,Priority,Repository
No priority yet|table|no:priority||||Title,Status,Labels,Repository
Long-lead|roadmap|label:long-lead|||Target:ASC|Title,Status,Assignees,Target,Waiting for
Initiatives|table|label:initiative||||Title,Status,Sub-issues progress,Repository'

# One GraphQL read per board, flattened to lines:
#   P|id|template|title
#   F|id|databaseId|name|dataType|optionId~name~colour~description;...
#   V|id|name|layout|filter|group by|columns|field:direction
#   W|name|enabled
BOARD_QUERY='projectV2(number:$n){id title template
fields(first:50){nodes{...on ProjectV2FieldCommon{id databaseId name dataType}
...on ProjectV2SingleSelectField{options{id name color description}}}}
views(first:50){nodes{id name layout filter
groupByFields(first:5){nodes{...on ProjectV2FieldCommon{name}}}
verticalGroupByFields(first:5){nodes{...on ProjectV2FieldCommon{name}}}
sortByFields(first:5){nodes{direction field{...on ProjectV2FieldCommon{name}}}}}}
workflows(first:50){nodes{name enabled}}}'
BOARD_JQ='.data[].projectV2 |
"P|\(.id)|\(.template)|\(.title)",
(.fields.nodes[] | "F|\(.id)|\(.databaseId)|\(.name)|\(.dataType)|\((.options // []) | map("\(.id)~\(.name)~\(.color)~\(.description)") | join(";"))"),
(.views.nodes[] | "V|\(.id)|\(.name)|\(.layout | sub("_LAYOUT$"; "") | ascii_downcase)|\(.filter // "")|\([.groupByFields.nodes[].name] | join(","))|\([.verticalGroupByFields.nodes[].name] | join(","))|\([.sortByFields.nodes[] | "\(.field.name):\(.direction)"] | join(","))"),
(.workflows.nodes[] | "W|\(.name)|\(.enabled)")'

die() { echo "ensure-board: $*" >&2; exit 2; }
usage() { sed -n '3,8p' "$0" | sed 's/^# //' >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Sets key (GraphQL owner field), rest (REST prefix) and web (board URL prefix).
owner_info() {
  info=$(gh api "users/$owner" --jq '"\(.type)|\(.id)"' </dev/null)
  case $info in
    Organization\|*) key=organization; rest="orgs/$owner"; web="https://github.com/orgs/$owner" ;;
    *) key=user; rest="users/${info#*|}"; web="https://github.com/users/$owner" ;;
  esac
}

read_board() { # NUMBER FILE
  gh api graphql -f query="query(\$o:String!,\$n:Int!){$key(login:\$o){$BOARD_QUERY}}" \
    -f o="$owner" -F n="$1" --jq "$BOARD_JQ" > "$2" </dev/null
}

field_line() { awk -F'|' -v n="$2" '$1 == "F" && $4 == n' "$1"; }
field_id() { awk -F'|' -v n="$2" '$1 == "F" && $4 == n {print $3; exit}' "$1"; }

find_board() { # TITLE -> number or nothing
  gh project list --owner "$owner" --limit 500 --format json \
    --jq '.projects[] | "\(.number)|\(.title)"' </dev/null |
    awk -F'|' -v t="$1" '$2 == t {print $1; exit}'
}

# Set a single-select field's options to SPEC, keeping the id of each option
# whose name (or old name) already exists, so items and workflows keep it.
sync_options() { # FILE FIELD SPEC
  line=$(field_line "$1" "$2")
  [ -n "$line" ] || die "no field $2"
  fid=$(printf '%s\n' "$line" | cut -d'|' -f2)
  printf '%s\n' "$line" | cut -d'|' -f6 | tr ';' '\n' > "$tmp/opts"
  have=$(awk -F'~' 'NF {printf "%s%s~%s~%s", (n++ ? ";" : ""), $2, $3, $4}' "$tmp/opts")
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
$3
EOF
  if [ "$have" = "$want" ]; then echo "field $2: ok"; return 0; fi
  gh api graphql -f query="mutation{updateProjectV2Field(input:{fieldId:\"$fid\",singleSelectOptions:[$literal]}){projectV2Field{...on ProjectV2SingleSelectField{id}}}}" \
    >/dev/null </dev/null
  echo "field $2: set"
}

ensure_field() { # NUMBER FILE NAME TYPE [SPEC]
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
  elif [ "$(printf '%s\n' "$line" | cut -d'|' -f5)" != "$4" ]; then
    die "field $3 exists with another type; change or delete it in the UI"
  fi
  if [ "$4" = SINGLE_SELECT ]; then sync_options "$2" "$3" "$5"; fi
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

ensure_views() { # NUMBER FILE
  while IFS='|' read -r name layout filter group cols sort visible; do
    cur=$(awk -F'|' -v n="$name" '$1 == "V" && $3 == n {print $4 "|" $5 "|" $6 "|" $7 "|" $8; exit}' "$2")
    vid=$(awk -F'|' -v n="$name" '$1 == "V" && $3 == n {print $2; exit}' "$2")
    if [ -n "$vid" ] && [ "$cur" = "$layout|$filter|$group|$cols|$sort" ]; then
      echo "view $name: ok"
      continue
    fi
    if [ -n "$vid" ]; then delete_view "$vid"; fi
    create_view "$1" "$2" "$name" "$layout" "$filter" "$group" "$cols" "$sort" "$visible"
    echo "view $name: set"
  done <<EOF
$VIEWS
EOF
  printf '%s\n' "$VIEWS" | cut -d'|' -f1 > "$tmp/names"
  read_board "$1" "$2"
  awk -F'|' 'NR == FNR {keep[$0] = 1; next} $1 == "V" && !($3 in keep) {print $2 "|" $3}' \
    "$tmp/names" "$2" > "$tmp/extra"
  while IFS='|' read -r vid name; do
    delete_view "$vid"
    echo "view $name: removed"
  done < "$tmp/extra"
}

ui_steps_template() {
  cat <<EOF
Steps with no API, in the board's Workflows settings ($web/projects/$1/workflows):
- Item added to project: set Status to Backlog.
- Item closed: set Status to Done.
- Item reopened: turn on, set Status to Backlog.
- Auto-archive items: turn on, archive closed items after 14 days.
- Pull request linked to issue: set Status to In review (or turn it off).
- Long-lead view: check its roadmap dates use Target.
EOF
}

template_mode() {
  owner_info
  number=$(find_board "$TEMPLATE_TITLE")
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
  ensure_views "$number" "$b"
  if [ "$(awk -F'|' '$1 == "P" {print $3}' "$b")" != true ]; then
    gh project mark-template "$number" --owner "$owner" >/dev/null </dev/null
    echo "board $number: marked as template"
  fi
  echo "template board $number: $web/projects/$number"
  ui_steps_template "$number"
}

create_mode() {
  title=$1; tpl=$2; shift 2
  repo=''; kind=0
  while [ $# -gt 0 ]; do
    case $1 in
      --repo) [ $# -ge 2 ] || usage; repo=$2; shift ;;
      --with-kind) kind=1 ;;
      *) usage ;;
    esac
    shift
  done
  owner_info
  number=$(find_board "$title")
  if [ -n "$number" ]; then
    echo "board $number: exists, not copied again"
  else
    number=$(gh project copy "$tpl" --source-owner "$owner" --target-owner "$owner" \
      --title "$title" --format json --jq .number </dev/null)
    echo "board $number: copied from template $tpl"
  fi
  b="$tmp/board"
  read_board "$number" "$b"
  pid=$(awk -F'|' '$1 == "P" {print $2}' "$b")
  gh api graphql -f query="mutation{updateProjectV2(input:{projectId:\"$pid\",public:false}){projectV2{id}}}" \
    >/dev/null </dev/null
  echo "board $number: private"
  if [ -n "$repo" ]; then
    gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null </dev/null
    echo "board $number: linked to $repo"
  fi
  if [ "$kind" -eq 1 ]; then ensure_field "$number" "$b" Kind SINGLE_SELECT "$KIND_OPTIONS"; fi
  echo "board $number: $web/projects/$number"
  echo "Steps with no API, in the board's settings ($web/projects/$number/settings):"
  if [ -n "$repo" ]; then
    echo "- Workflows > Auto-add to project: repository $repo, filter is:issue -label:initiative."
  fi
  echo "- Manage access: set the base role to No access."
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

check_mode() {
  number=$1; tpl=$2
  owner_info
  read_board "$number" "$tmp/board"
  read_board "$tpl" "$tmp/tpl"
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
  awk -F'|' 'NR == FNR {t[$1] = 1; next} !($1 in t) && $1 != "Kind" {print "field " $1 ": not in the template"}' \
    "$tmp/tf" "$tmp/bf" >> "$tmp/diff"
  awk -F'|' '$1 == "V" {print $3 "|" $4 "|" $5 "|" $6 "|" $7 "|" $8}' "$tmp/tpl" > "$tmp/tv"
  while IFS='|' read -r name rest_of; do
    got=$(awk -F'|' -v n="$name" '$1 == "V" && $3 == n {print $4 "|" $5 "|" $6 "|" $7 "|" $8; exit}' "$tmp/board")
    if [ -z "$got" ]; then
      echo "view $name: missing" >> "$tmp/diff"
    elif [ "$got" != "$rest_of" ]; then
      echo "view $name: is $got, template has $rest_of" >> "$tmp/diff"
    fi
  done < "$tmp/tv"
  # Workflow names as GitHub lists them; one not yet configured is not listed,
  # so the names of Item reopened, Auto-archive items and Auto-add to project
  # follow the settings page (unverified through the API).
  wanted='item added to project
item closed
item reopened
auto-archive items'
  if [ "$number" != "$tpl" ]; then wanted="$wanted
auto-add to project"; fi
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
  echo "Not checked (no API): workflow settings, the auto-add filter, the base role."
  if [ -s "$tmp/diff" ]; then
    echo "board $number differs from template $tpl:"
    sed 's/^/- /' "$tmp/diff"
    exit 1
  fi
  echo "board $number matches template $tpl"
}

case ${1:-} in
  template) [ $# -eq 2 ] || usage; owner=$2; template_mode ;;
  create) [ $# -ge 4 ] || usage; owner=$2; shift 2; create_mode "$@" ;;
  --check) [ $# -eq 4 ] || usage; owner=$2; check_mode "$3" "$4" ;;
  *) usage ;;
esac
