#!/bin/sh
# Self-test for board-threads against a fake gh; touches no repository or
# board. PYTHON overrides the interpreter (default: run the tool directly).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/board-threads"
py=${PYTHON:-python3}
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin" "$dir/fx"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; }
run() { if [ -n "${PYTHON:-}" ]; then "$PYTHON" "$tool" "$@"; else "$tool" "$@"; fi; }

# Fake gh: answers by endpoint from fixture files and logs every call.
cat > "$dir/bin/gh" <<FAKE
#!/bin/sh
echo "\$*" >> "$dir/calls"
fx="$dir/fx"
case "\$*" in
  'api user') cat "\$fx/user.json" ;;
  *orgs/broken-org/*) echo 'gh: Resource not accessible: missing project scope (HTTP 403)' >&2; exit 1 ;;
  *orgs/example-user/*|*/nobody/*) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
  *projectsV2/3/fields*) cat "\$fx/fields.json" ;;
  *projectsV2/3/items*) cat "\$fx/page1.json" "\$fx/page2.json" ;;
  *) echo "fake gh: unexpected \$*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$dir/bin/gh"
PATH="$dir/bin:$PATH"; export PATH

new=$("$py" -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
old=$("$py" -c 'import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ"))')

echo '{"login": "tester", "id": 1}' > "$dir/fx/user.json"
cat > "$dir/fx/fields.json" <<'JSON'
[{"id": 1, "name": "Title", "data_type": "title"},
 {"id": 2, "name": "Assignees", "data_type": "assignees"},
 {"id": 3, "name": "Status", "data_type": "single_select"},
 {"id": 4, "name": "Labels", "data_type": "labels"},
 {"id": 5, "name": "Priority", "data_type": "single_select"},
 {"id": 6, "name": "Waiting for", "data_type": "text"},
 {"id": 7, "name": "Kind", "data_type": "single_select"},
 {"id": 8, "name": "Focus", "data_type": "single_select"},
 {"id": 9, "name": "Rank", "data_type": "number"},
 {"id": 10, "name": "Next step", "data_type": "text"}]
JSON
# item ID TYPE TITLE STATE UPDATED ARCHIVED FIELDS: one board item.
item() {
  url=null
  [ "$2" = DraftIssue ] || url="\"https://github.com/example-org/demo/issues/$1\""
  printf '{"id": %s, "node_id": "PVTI_%s", "content_type": "%s", "content": {"title": "%s", "html_url": %s, "number": %s, "state": "%s", "body": "SECRET-BODY-TEXT"}, "archived_at": %s, "updated_at": "%s", "fields": [%s]}' \
    "$1" "$1" "$2" "$3" "$url" "$1" "$4" "$6" "$5" "$7"
}
sel() { printf '{"id": 0, "name": "%s", "data_type": "single_select", "value": {"name": {"raw": "%s", "html": "%s"}, "color": "GRAY"}}' "$1" "$2" "$2"; }
txt() { printf '{"id": 0, "name": "%s", "data_type": "text", "value": "%s"}' "$1" "$2"; }
rank() { printf '{"id": 9, "name": "Rank", "data_type": "number", "value": %s}' "$1"; }
who() { printf '{"id": 2, "name": "Assignees", "data_type": "assignees", "value": [{"login": "%s", "id": 7}]}' "$1"; }
{
  echo '['
  item 101 Issue 'Alpha later' open "$new" null "$(sel Focus Later), $(rank 1), $(sel Status 'In progress'), $(txt 'Next step' 'do a')"; echo ,
  item 102 Issue 'Beta now' open "$old" null "$(sel Focus Now), $(rank 2), $(txt 'Next step' 'do b'), $(who tester), $(sel Priority 'P2 soon')"; echo ,
  item 103 DraftIssue 'Gamma now' open "$new" null "$(sel Focus now), $(rank 1), $(sel Status Waiting), $(txt 'Waiting for' 'review by @Tester'), $(sel Priority 'P1 now')"; echo ,
  item 104 Issue 'Delta now' open "$new" null "$(sel Focus Now), $(txt 'Next step' 'do d')"
  echo ']'
} > "$dir/fx/page1.json"
{
  echo '['
  item 105 Issue 'Done one' open "$new" null "$(sel Focus Now), $(sel Status Done), $(who tester)"; echo ,
  item 106 Issue 'Archived one' open "$new" '"2026-01-01T00:00:00Z"' "$(sel Focus Now), $(who tester)"; echo ,
  item 107 Issue 'Closed one' closed "$new" null "$(sel Focus Next), $(who tester)"; echo ,
  item 108 Issue 'Parked by status' open "$new" null "$(sel Status Parked), $(sel Kind Idea)"; echo ,
  item 109 DraftIssue 'Parked by focus' open "$old" null "$(sel Focus Parked)"; echo ,
  item 110 Issue 'Assigned and waiting' open "$new" null "$(sel Status Waiting), $(txt 'Waiting for' 'tester'), $(who tester), $(sel Priority 'P3 later')"; echo ,
  item 112 Issue 'Waits on maintainer' open "$old" null "$(sel Status Waiting), $(txt 'Waiting for' 'Maintainer review'), $(sel Priority 'P3 later')"; echo ,
  item 113 Issue 'Waits on meeting' open "$new" null "$(sel Status Waiting), $(txt 'Waiting for' 'meeting notes, time slot')"; echo ,
  item 111 Issue 'Epsilon next' open "$new" null "$(sel Focus Next), $(rank 5), $(txt 'Next step' 'do e')"
  echo ']'
} > "$dir/fx/page2.json"

# check JSONFILE PYTHON-ASSERTIONS: run assertions with d = the parsed output.
check() {
  "$py" - "$1" "$2" <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
titles = lambda k: [x["title"] for x in d[k]]
try:
    exec(sys.argv[2])
except AssertionError as e:
    print("FAIL: assertion: " + sys.argv[2] + (" (%s)" % e if str(e) else ""), file=sys.stderr)
    print(json.dumps(d, indent=1), file=sys.stderr)
    sys.exit(1)
PY
}

run example-org 3 --json > "$dir/org.json" || fail "org board exited non-zero"
check "$dir/org.json" 'assert titles("threads") == ["Gamma now", "Beta now", "Delta now", "Epsilon next", "Alpha later"], titles("threads")'
ok "threads sorted by focus, then rank (missing last)"
check "$dir/org.json" 'assert not {"Done one", "Archived one", "Closed one"} & set(titles("threads") + titles("waiting_on_me"))'
ok "Done, archived and closed items excluded"
check "$dir/org.json" 'assert [t["stalled"] for t in d["threads"]] == [False, True, False, False, False]; assert d["threads"][1]["days_since_update"] == 30'
ok "stalled flag from days since update"
check "$dir/org.json" 'assert [t["no_next_step"] for t in d["threads"]] == [True, False, False, False, False]'
ok "no_next_step flag"
check "$dir/org.json" 'assert titles("waiting_on_me") == ["Gamma now", "Beta now", "Waits on maintainer", "Assigned and waiting"], titles("waiting_on_me")'
ok "waiting_on_me via assignee, login or \"maintainer\" in Waiting for (not \"meeting\"), deduplicated, by priority"
check "$dir/org.json" 'assert titles("parked") == ["Parked by focus", "Parked by status"]; assert d["parked"][1]["kind"] == "Idea"'
ok "parked via Status and via Focus, oldest first"
check "$dir/org.json" 'assert d["threads"][0]["link"] == "https://github.com/orgs/example-org/projects/3?pane=issue&itemId=103"; assert d["threads"][1]["link"] == "https://github.com/example-org/demo/issues/102"'
ok "links for drafts and issues"
check "$dir/org.json" 'assert d["signals"] == {"threads": {"Now": 3, "Next": 1, "Later": 1}, "waiting_on_me": 4, "stalled": 1, "no_next_step": 1}, d["signals"]'
ok "signals"
grep -q 'SECRET-BODY-TEXT' "$dir/org.json" && fail "JSON output carries an issue body"
ok "JSON output has no bodies"
grep -q '^api user$' "$dir/calls" || fail "--me did not default to the gh login"
grep -q '^api --paginate orgs/example-org/projectsV2/3/items?per_page=100&fields\[\]=2&fields\[\]=3&fields\[\]=5&fields\[\]=6&fields\[\]=7&fields\[\]=8&fields\[\]=9&fields\[\]=10$' "$dir/calls" \
  || fail "items call: $(grep items "$dir/calls")"
grep -q ' /' "$dir/calls" && fail "endpoint with a leading slash: $(cat "$dir/calls")"
ok "gh calls: login default, paginated items with named fields, no leading slash"

: > "$dir/calls"
run example-org 3 --me someone-else --json > "$dir/other.json"
check "$dir/other.json" 'assert titles("waiting_on_me") == ["Waits on maintainer"], titles("waiting_on_me")'
grep -q '^api user$' "$dir/calls" && fail "--me still asked gh for the login"
ok "--me overrides the login"

run example-org 3 --stale-days 60 --json > "$dir/stale.json"
check "$dir/stale.json" 'assert d["signals"]["stalled"] == 0'
ok "--stale-days"

run example-org 3 > "$dir/org.md"
grep -q 'SECRET-BODY-TEXT' "$dir/org.md" && fail "text output carries an issue body"
grep -q '^## Threads$' "$dir/org.md" && grep -q '^## Waiting on tester$' "$dir/org.md" \
  && grep -q '^## Parked$' "$dir/org.md" && grep -q '^## Signals$' "$dir/org.md" || fail "section headings: $(cat "$dir/org.md")"
grep -q '^- Now \[Beta now\](https://github.com/example-org/demo/issues/102) — Next: do b (30 d, stalled)$' "$dir/org.md" \
  || fail "thread line: $(cat "$dir/org.md")"
grep -q '|' "$dir/org.md" && fail "text output has a table"
ok "text output: sections, one bullet per item, no bodies, no tables"

run example-user 3 --me tester --json > "$dir/user.json" || fail "user board exited non-zero"
check "$dir/user.json" 'assert d["threads"][0]["link"] == "https://github.com/users/example-user/projects/3?pane=issue&itemId=103"'
grep -q '^api orgs/example-user/projectsV2/3/fields' "$dir/calls" && grep -q '^api --paginate users/example-user/projectsV2/3/items' "$dir/calls" \
  || fail "no fallback to the user board: $(cat "$dir/calls")"
ok "user-owned board fallback"

# Empty board: every section says none.
echo '[]' > "$dir/fx/page1.json"; echo '[]' > "$dir/fx/page2.json"
run example-org 3 --me tester > "$dir/empty.md"
[ "$(grep -c '^none$' "$dir/empty.md")" = 3 ] || fail "empty sections: $(cat "$dir/empty.md")"
ok "empty sections print none"

set +e
run broken-org 3 --me tester > "$dir/out" 2> "$dir/err"; rc=$?
set -e
[ "$rc" = 1 ] || fail "gh failure exit $rc"
[ "$(wc -l < "$dir/err")" -eq 1 ] && grep -q '^board-threads: .*project scope' "$dir/err" || fail "gh failure message: $(cat "$dir/err")"
[ -s "$dir/out" ] && fail "printed output on failure"
ok "gh failure exits 1 with one stderr line"

set +e
run nobody 3 --me tester > /dev/null 2> "$dir/err"; rc=$?
set -e
[ "$rc" = 1 ] && grep -q 'not found' "$dir/err" || fail "missing board: exit $rc, $(cat "$dir/err")"
ok "missing board exits 1"

set +e
run example-org > /dev/null 2>&1; rc=$?
set -e
[ "$rc" = 2 ] || fail "usage error exit $rc"
ok "usage error exits 2"
