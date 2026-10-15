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
  *search/issues*assignee:searchfail+*) echo 'gh: Validation Failed (HTTP 422)' >&2; exit 1 ;;
  *search/issues*assignee:tester+*) cat "\$fx/search1.json" "\$fx/search2.json" ;;
  *search/issues*) echo '{"total_count": 0, "incomplete_results": false, "items": []}' ;;
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
rich() { printf '{"id": 0, "name": "%s", "data_type": "text", "value": {"raw": "%s", "html": "<p>%s</p>"}}' "$1" "$2" "$2"; }
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
  item 114 Issue 'Waits on approval' open "$new" null "$(sel Status Waiting), $(txt 'Waiting for' 'approval pending')"; echo ,
  item 115 Issue 'Waits on al' open "$new" null "$(sel Status Waiting), $(txt 'Waiting for' 'Al, by Friday')"; echo ,
  item 116 Issue 'Phase work parked' open "$new" null "$(sel Status Parked), $(sel Kind 'Work package')"; echo ,
  item 117 Issue 'Thread parked' open "$new" null "$(sel Focus Next), $(rank 2.5), $(sel Status Parked), $(sel Kind Idea), $(rich 'Next step' 'do f')"; echo ,
  item 118 Issue 'Zeta next' open "$new" null "$(sel Focus Next), $(rank 3), $(txt 'Next step' 'do z')"; echo ,
  item 119 Issue 'Eta next' open "$new" null "$(sel Focus Next), $(rank 2), $(txt 'Next step' 'do h')"; echo ,
  item 111 Issue 'Epsilon next' open "$new" null "$(sel Focus Next), $(rank 5), $(txt 'Next step' 'do e')"
  echo ']'
} > "$dir/fx/page2.json"

# Issue search: two pages, one hit already on the board (Beta now, #102).
hit() {
  printf '{"id": 9%s, "node_id": "I_%s", "number": %s, "title": "%s", "html_url": "https://github.com/example-org/%s/issues/%s", "repository_url": "https://api.github.com/repos/example-org/%s", "state": "open", "updated_at": "%s", "labels": [{"id": 1, "name": "%s"}], "body": "SECRET-BODY-TEXT"}' \
    "$2" "$2" "$2" "$3" "$1" "$2" "$1" "$4" "$5"
}
printf '{"total_count": 3, "incomplete_results": false, "items": [%s, %s]}\n' \
  "$(hit demo 102 'Beta now (search copy)' "$new" bug)" "$(hit other 7 'Elsewhere old' "$old" maintainer-step)" > "$dir/fx/search1.json"
printf '{"total_count": 3, "incomplete_results": false, "items": [%s]}\n' \
  "$(hit other 8 'Elsewhere new' "$new" chore)" > "$dir/fx/search2.json"

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
check "$dir/org.json" 'assert titles("threads") == ["Gamma now", "Beta now", "Delta now", "Eta next", "Thread parked", "Zeta next", "Epsilon next", "Alpha later"], titles("threads")'
check "$dir/org.json" 'assert d["threads"][4]["rank"] == 2.5 and d["threads"][3]["rank"] == 2'
ok "threads sorted by focus, then rank (fractional in between, missing last)"
check "$dir/org.json" 'assert not {"Done one", "Archived one", "Closed one"} & set(titles("threads") + titles("waiting_on_me"))'
ok "Done, archived and closed items excluded"
check "$dir/org.json" 'assert [t["stalled"] for t in d["threads"]] == [False, True] + [False] * 6; assert d["threads"][1]["days_since_update"] == 30'
ok "stalled flag from days since update"
check "$dir/org.json" 'assert [t["no_next_step"] for t in d["threads"]] == [True] + [False] * 7'
ok "no_next_step flag"
check "$dir/org.json" 'assert d["threads"][4]["next_step"] == "do f"'
ok "a text field sent as a raw/html dict reads as its raw text"
check "$dir/org.json" 'assert titles("waiting_on_me") == ["Gamma now", "Beta now", "Waits on maintainer", "Assigned and waiting", "Elsewhere old", "Elsewhere new"], titles("waiting_on_me")'
ok "waiting_on_me via assignee, login or \"maintainer\" in Waiting for (not \"meeting\"), by priority then age"
check "$dir/org.json" 'assert titles("parked") == ["Parked by focus", "Parked by status"]; assert d["parked"][1]["kind"] == "Idea"'
ok "parked via Focus, or Status Parked with Kind Idea, oldest first; phase work and threads not parked"
check "$dir/org.json" '
w = {x["title"]: x for x in d["waiting_on_me"]}
assert "Beta now (search copy)" not in w
b = w["Beta now"]
assert (b["priority"], b["labels"], b["item_id"], b["repo"], b["number"]) == ("P2 soon", ["bug"], 102, "example-org/demo", 102), b
e = w["Elsewhere old"]
assert e == {"item_id": None, "node_id": None, "content_type": "Issue", "repo": "example-org/other", "number": 7,
             "title": "Elsewhere old", "link": "https://github.com/example-org/other/issues/7", "status": "", "priority": "",
             "days_since_update": 30, "waiting_for": "", "kind": "", "area": "", "labels": ["maintainer-step"]}, e'
ok "issue search merged across pages, deduplicated by URL keeping board fields"
check "$dir/org.json" '
g = d["threads"][0]
assert (g["item_id"], g["node_id"], g["content_type"], g["repo"], g["number"]) == (103, "PVTI_103", "DraftIssue", None, None), g
b = d["threads"][1]
assert (b["item_id"], b["node_id"], b["content_type"], b["repo"], b["number"]) == (102, "PVTI_102", "Issue", "example-org/demo", 102), b
p = d["parked"][1]
assert (p["item_id"], p["node_id"], p["repo"], p["number"]) == (108, "PVTI_108", "example-org/demo", 108), p
assert all({"item_id", "node_id", "content_type", "repo", "number"} <= set(r) for k in ("threads", "waiting_on_me", "parked") for r in d[k])'
ok "rows carry item_id, node_id, content_type, repo and number"
check "$dir/org.json" 'assert d["threads"][0]["link"] == "https://github.com/orgs/example-org/projects/3?pane=issue&itemId=103"; assert d["threads"][1]["link"] == "https://github.com/example-org/demo/issues/102"'
ok "links for drafts and issues"
check "$dir/org.json" 'assert d["signals"] == {"threads": {"Now": 3, "Next": 4, "Later": 1}, "waiting_on_me": 6, "waiting_on_board": 4, "issue_search": "ok", "stalled": 1, "no_next_step": 1}, d["signals"]'
ok "signals"
grep -q 'SECRET-BODY-TEXT' "$dir/org.json" && fail "JSON output carries an issue body"
ok "JSON output has no bodies"
grep -q '^api user$' "$dir/calls" || fail "--me did not default to the gh login"
grep -q '^api --paginate orgs/example-org/projectsV2/3/items?per_page=100&fields\[\]=2&fields\[\]=3&fields\[\]=5&fields\[\]=6&fields\[\]=7&fields\[\]=8&fields\[\]=9&fields\[\]=10$' "$dir/calls" \
  || fail "items call: $(grep items "$dir/calls")"
grep -q '^api --paginate search/issues?q=assignee:tester+is:open+is:issue&per_page=100$' "$dir/calls" \
  || fail "search call: $(grep search "$dir/calls")"
grep -q ' /' "$dir/calls" && fail "endpoint with a leading slash: $(cat "$dir/calls")"
ok "gh calls: login default, paginated items with named fields, no leading slash"

: > "$dir/calls"
run example-org 3 --me someone-else --json > "$dir/other.json"
check "$dir/other.json" 'assert titles("waiting_on_me") == ["Waits on maintainer"], titles("waiting_on_me")'
grep -q '^api user$' "$dir/calls" && fail "--me still asked gh for the login"
ok "--me overrides the login"
run example-org 3 --me al --json > "$dir/al.json"
check "$dir/al.json" 'assert titles("waiting_on_me") == ["Waits on maintainer", "Waits on al"], titles("waiting_on_me")'
ok "login matches Waiting for as a whole word (al, not approval)"

run example-org 3 --stale-days 60 --json > "$dir/stale.json"
check "$dir/stale.json" 'assert d["signals"]["stalled"] == 0'
ok "--stale-days"

run example-org 3 > "$dir/org.md"
grep -q 'SECRET-BODY-TEXT' "$dir/org.md" && fail "text output carries an issue body"
grep -q '^## Threads$' "$dir/org.md" && grep -q '^## Waiting on tester$' "$dir/org.md" \
  && grep -q '^## Parked$' "$dir/org.md" && grep -q '^## Signals$' "$dir/org.md" || fail "section headings: $(cat "$dir/org.md")"
grep -q '^- Now 2 \[Beta now\](https://github.com/example-org/demo/issues/102) — Next: do b (30 d, stalled)$' "$dir/org.md" \
  || fail "thread line: $(cat "$dir/org.md")"
grep -q '^- Next 2.5 \[Thread parked\](https://github.com/example-org/demo/issues/117) — Next: do f (1 d)$' "$dir/org.md" \
  || fail "fractional rank line: $(cat "$dir/org.md")"
grep -q '^- \[Elsewhere old\](https://github.com/example-org/other/issues/7) (example-org/other#7, not on the shared board, 30 d)$' "$dir/org.md" \
  || fail "search-only line: $(cat "$dir/org.md")"
grep -q '|' "$dir/org.md" && fail "text output has a table"
ok "text output: sections, one bullet per item, no bodies, no tables"

run example-user 3 --me tester --json > "$dir/user.json" || fail "user board exited non-zero"
check "$dir/user.json" 'assert d["threads"][0]["link"] == "https://github.com/users/example-user/projects/3?pane=issue&itemId=103"'
grep -q '^api orgs/example-user/projectsV2/3/fields' "$dir/calls" && grep -q '^api --paginate users/example-user/projectsV2/3/items' "$dir/calls" \
  || fail "no fallback to the user board: $(cat "$dir/calls")"
ok "user-owned board fallback"

# A failed issue search still prints the board, flagged; exit 0.
run example-org 3 --me searchfail --json > "$dir/sf.json" 2> "$dir/err" || fail "search failure exited non-zero"
grep -q '^board-threads: issue search failed: .*HTTP 422' "$dir/err" || fail "search failure warning: $(cat "$dir/err")"
check "$dir/sf.json" 'assert d["signals"]["issue_search"] == "failed"; assert titles("waiting_on_me") == ["Waits on maintainer"]; assert d["signals"]["waiting_on_board"] == 1; assert len(d["threads"]) == 8'
run example-org 3 --me searchfail > "$dir/sf.md" 2> /dev/null || fail "search failure (text) exited non-zero"
grep -q '^Issue search failed; assigned issues not shown\.$' "$dir/sf.md" && grep -q '^## Threads$' "$dir/sf.md" \
  || fail "search failure text: $(cat "$dir/sf.md")"
grep -q 'Issue search failed' "$dir/org.md" && fail "search-failed line printed after a good search"
ok "issue search failure keeps the board sections, flags it and exits 0"

# Empty board: every section says none.
echo '[]' > "$dir/fx/page1.json"; echo '[]' > "$dir/fx/page2.json"
run example-org 3 --me someone-else > "$dir/empty.md"
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
