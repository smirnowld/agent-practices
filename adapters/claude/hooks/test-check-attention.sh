#!/bin/sh
# Offline self-test for the attention hook: a card, question or closeout that
# ends a turn without a signal is blocked once; a turn that already signalled,
# a repeat stop, pending background work and plain answers pass silently; bad
# input passes with a note on stderr. A merge without its closeout, and a PR
# the session or a subagent left open with no closeout or question, are blocked.
set -eu
dir=$(dirname "$0")
hook="$dir/check-attention.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A transcript: my message, then an assistant turn calling TOOL (none if empty).
transcript() {
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion"}]}}' \
    '{"type":"user","message":{"content":"next task"}}' \
    '{"type":"user","message":{"content":[{"type":"tool_result"}]}}' >"$tmp/t.jsonl"
  [ -z "$1" ] || printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"%s"}]}}\n' "$1" >>"$tmp/t.jsonl"
}
# input MESSAGE [EXTRA_JSON_FIELDS]
input() {
  python3 -c 'import json,sys; d={"transcript_path":sys.argv[2],"stop_hook_active":False,"last_assistant_message":sys.argv[1]}; d.update(json.loads(sys.argv[3] or "{}")); print(json.dumps(d))' \
    "$1" "$tmp/t.jsonl" "${2:-}"
}
blocks() { out=$(input "$1" "${2:-}" | python3 "$hook"); echo "$out" | grep -qF "$3" || { echo "error: not blocked with '$3' for: $1 -> $out" >&2; exit 1; }; }
# Pass cases must also leave stderr empty: a skipped check is not a pass.
passes() { out=$(input "$1" "${2:-}" | python3 "$hook" 2>&1); [ -z "$out" ] || { echo "error: expected silent pass for: $1 -> $out" >&2; exit 1; }; }

closeout=$(cat "$dir/../../../scripts/fixtures/closeout-good.md")
card='Done.

# Acceptance: New sign-in screen

**Decision needed:** accept / change / reject'
transcript Bash
blocks "$card" '' 'AskUserQuestion'
blocks '# Question: Keep 30-day sign-in?' '' 'AskUserQuestion'
blocks '**Waiting on me:** acceptance of phase 2' '' 'AskUserQuestion'
blocks "$closeout" '' 'PushNotification'
blocks "$card" '{"background_tasks":[]}' '"decision": "block"'

passes '**Waiting on me:** nothing'
passes '**Waiting on me:** "Nothing"'
passes 'Here is the answer: 42.'
passes "$card" '{"stop_hook_active":true}'
passes "$card" '{"background_tasks":[{"id":"t1","type":"subagent"}]}'
transcript AskUserQuestion; passes "$card"
transcript PushNotification; passes "$closeout"
# A signal from an earlier turn does not count for this one.
transcript ''; blocks "$closeout" '' 'PushNotification'

# An early clarifying question does not cover a closeout written after my answer.
printf '%s\n' '{"type":"user","message":{"content":"build it"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash"}]}}' >"$tmp/t.jsonl"
blocks "$closeout" '' 'PushNotification'
# Another tool result after the signal keeps it; a notification wakes nothing.
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"go"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"p1"}]}}' \
  '{"type":"user","isMeta":true,"message":{"content":"meta"}}' \
  '{"type":"user","isCompactSummary":true,"message":{"content":"summary"}}' \
  '{"type":"user","message":{"content":"<task-notification>done</task-notification>"}}' \
  '[1]' >"$tmp/t.jsonl"
passes "$closeout"
# A list of text parts is a typed message and resets the turn.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","message":{"content":[{"type":"text","text":"next"}]}}' >"$tmp/t.jsonl"
blocks "$closeout" '' 'ToolSearch'

# A typed message is known by its origin when present, even behind a harness tag.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","origin":{"kind":"human"},"message":{"content":"<system-reminder>x</system-reminder> next"}}' >"$tmp/t.jsonl"
blocks "$closeout" '' 'PushNotification'
printf '%s\n' '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","origin":{"kind":"task-notification"},"message":{"content":"done"}}' >"$tmp/t.jsonl"
passes "$closeout"

transcript Bash
for none in '**Waiting on me:** none' '**Waiting on me:** n/a' '**Waiting on me:** *nothing*' '**Waiting on me:** _None_'; do
  passes "$none"
done
passes 'The template:

```markdown
# Closeout: <title>
**Decision needed:** accept
```'
blocks '```
x
```
# Acceptance: Real card' '' 'AskUserQuestion'

# A closeout missing template fields is blocked, naming each.
transcript PushNotification
short=$(printf '%s\n' "$closeout" | grep -v -e '^\*\*Proof:' -e '^\*\*Next:')
blocks "$short" '' '**Proof:**, **Next:**'

# A turn that merged a PR: bash CMD... as tool calls m1, m2... after my message; TEXT
# is an earlier assistant message.
merge_turn() {
  text=$1; shift
  printf '%s\n' '{"type":"user","message":{"content":"merge it"}}' >"$tmp/t.jsonl"
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$text" >>"$tmp/t.jsonl"
  k=0
  for c in "$@"; do
    k=$((k + 1))
    python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"content":[{"type":"tool_use","id":sys.argv[2],"name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$c" "m$k" >>"$tmp/t.jsonl"
  done
}
merge_turn "$closeout" 'gh pr merge 5 --squash'
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
merge_turn "$closeout" 'gh pr merge 5 --squash' 'gh pr comment 5 --body merged'
blocks 'Merged as abc.' '' 'a comment does not replace it'
merge_turn "$closeout" 'gh pr edit 5 --body-file b.md' 'gh pr merge 5 --squash'
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
merge_turn "$closeout" 'gh pr merge 5 --squash' 'gh pr edit 5 --body-file b.md'
passes 'Merged as abc.'
merge_turn 'Merged, all good.' 'gh pr merge 5 --squash' 'gh pr edit 5 --body-file b.md'
blocks 'Merged as abc.' '' 'send the full closeout in chat'
merge_turn 'Paused.' 'gh pr merge 5 --disable-auto'
passes 'Paused.'
# Not merges: help, a search, a pending auto-merge, a quoted mention.
merge_turn 'Done.' 'gh pr merge --help' 'grep -rn "gh pr merge" skills' 'gh pr merge 5 --auto --squash' 'git log | grep merge'
passes 'Done.'
# A merge whose call failed or was refused is not a merge.
merge_turn "$closeout" 'gh pr merge 5 --squash'
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"m1","is_error":true}]}}' >>"$tmp/t.jsonl"
passes 'Merge refused.'
# Body rewrites in other forms count.
for edit in 'gh pr merge 5 --squash && gh pr edit 5 --body-file b.md' \
  'gh pr merge 5 --squash; gh pr edit 5 -F b.md' \
  "gh pr merge 5 \\
  --squash && gh api -X PATCH repos/o/r/pulls/5 -f body=x"; do
  merge_turn "$closeout" "$edit"; passes 'Merged as abc.'
done
# A command after a heredoc's opener on the same line still counts.
merge_turn "$closeout" 'gh pr merge 5 --squash' "cat > b.md <<'EOF' && gh pr edit 5 --body-file b.md
body
EOF"
passes 'Merged as abc.'
merge_turn "$closeout" "cat <<'EOF' && gh pr merge 5 --squash
gh pr edit 5 --body-file b.md
EOF"
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
merge_turn "$closeout" "gh pr merge 5 \\
  --disable-auto"
passes 'Paused.'
# A session's entries: u:TYPED, a:ASSISTANT_TEXT, b:BASH_COMMAND, q (AskUserQuestion),
# p (PushNotification), r[:OUTPUT] (answer to the last tool call), e (the last tool
# call failed). A session's entry N is stamped at time 10*N; subagent START PATH
# writes one agent's transcript, stamped START, START+1 and on.
entries() {
  python3 -c '
import json, sys
k, start, step = 0, int(sys.argv[1]), int(sys.argv[2])
for n, arg in enumerate(sys.argv[3:]):
    kind, _, v = arg.partition(":")
    if kind == "u": e = {"type": "user", "message": {"content": v}}
    elif kind == "a": e = {"type": "assistant", "message": {"content": [{"type": "text", "text": v}]}}
    elif kind in ("b", "q", "p"):
        k += 1
        tool = {"type": "tool_use", "id": "s%d" % k, "name": "Bash", "input": {"command": v}}
        if kind != "b": tool.update(name={"q": "AskUserQuestion", "p": "PushNotification"}[kind], input={})
        e = {"type": "assistant", "message": {"content": [tool]}}
    else: e = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "s%d" % k, "content": v, "is_error": kind == "e"}]}}
    e["timestamp"] = "2026-01-01T%04d" % (start + step * n)
    print(json.dumps(e))' "$@"
}
session() { rm -rf "$tmp/t"; entries 0 10 "$@" >"$tmp/t.jsonl"; }
subagent() {
  mkdir -p "$(dirname "$tmp/t/subagents/$2")"
  start=$1; name=$2; shift 2
  entries "$start" 1 "$@" >"$tmp/t/subagents/$name.jsonl"
}
open='A PR this session created is still open'
session u:go 'b:git push && gh pr create --fill' r
blocks 'Opened the PR.' '' "$open"
# The block reason names the whole path to done.
blocks 'Opened the PR.' '' 'the `merge` skill or hand the merge to me'
session u:go 'b:gh pr create --fill' r u:'merge it' 'b:gh pr merge 5 --squash' r \
  'b:gh pr edit 5 --body-file b.md' r p r
passes "$closeout"
session u:go 'b:gh pr create --fill' r q
passes 'Asked whether to merge.'
session u:go 'b:gh pr create --fill' r a:"$closeout" u:'thanks'
passes 'You are welcome.'
# An answered question does not cover a stop after it.
session u:go 'b:gh pr create --fill' r q r 'b:git status' r
blocks 'Carried on.' '' "$open"
# A pending auto-merge or a close settles it; a failed or help create opens nothing.
session u:go 'b:gh pr create --fill' r 'b:gh pr merge 5 --auto --squash' r
passes 'Auto-merge on.'
session u:go 'b:gh pr create --fill' r 'b:gh pr close 5' r
passes 'Closed.'
session u:go 'b:gh pr create --fill' e
passes 'Create failed.'
session u:go 'b:gh pr create --help' r 'b:grep -rn "gh pr create" skills' r
passes 'Read the help.'
# A second PR created after the first merged is open again.
session u:go 'b:gh pr create' r 'b:gh pr merge 5 --squash' r 'b:gh pr create' r
blocks 'Second PR opened.' '' "$open"
session u:go 'b:gh pr create' r 'b:gh pr merge 5 --disable-auto' r
blocks 'Paused.' '' "$open"
session u:go 'b:gh pr create' r 'b:gh pr merge 5 --auto --squash' r 'b:gh pr merge 5 --disable-auto' r
blocks 'Paused before a push.' '' "$open"
# Creates by substitution, prefix or loop count.
for c in 'url=$(gh pr create --fill)' 'GH_REPO=o/r gh pr create --fill' 'for b in x; do gh pr create --fill; done'; do
  session u:go "b:$c" r; blocks 'Opened.' '' "$open"
done
# Mentions in quotes, heredocs or a PR body are not commands; a dry run opens nothing.
session u:go "b:git commit -F - <<'EOF'
gh pr create calls without a merge now block.
EOF" r 'b:git commit -m "docs; gh pr create now blocks"' r 'b:grep -rnE "foo|gh pr create" .' r \
  'b:gh pr create --dry-run --fill' r
passes 'Committed.'
session u:go "b:gh pr create --title 'Add -h flag' --body \"\$(cat <<'EOF'
gh pr merge 5 --squash
EOF
)\"" r
blocks 'Opened.' '' "$open"
# A closeout shown inside a code fence earlier was not sent.
session u:go 'b:gh pr create' r a:"\`\`\`
$closeout
\`\`\`" u:next
blocks 'Next done.' '' "$open"
# Comments and echo or printf arguments are text; a substitution inside echo runs.
session u:go 'b:git push # next: gh pr create' r "b:git push # don't gh pr create yet" r \
  'b:echo run gh pr create next' r "b:printf '%s' x gh pr create" r 'b:x=$(echo gh pr create) && ls' r \
  'b:ls ;# gh pr create' r 'b:# gh pr merge 5 --squash' r
passes 'Noted.'
for c in 'echo $(gh pr create --fill)' "git push # it's pushed
gh pr create --fill" 'n=${#x} && gh pr create'; do
  session u:go "b:$c" r; blocks 'Opened.' '' "$open"
done
merge_turn "$closeout" 'gh pr merge 5 --squash # then the body'
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
# Every heredoc opened on a line is emptied, and a command after the last runs.
session u:go 'b:cat <<A <<B
gh pr create
A
gh pr create
B' r
passes 'Printed.'
session u:go 'b:cat <<A <<-B
x
A
	y
	B
gh pr create' r
blocks 'Opened.' '' "$open"
# Disabling auto-merge does not reopen a PR already merged or closed.
session u:go 'b:gh pr create' r 'b:gh pr merge 5 --squash' r u:next 'b:gh pr merge 5 --disable-auto' r
passes 'Paused.'
session u:go 'b:gh pr create' r 'b:gh pr close 5' r 'b:gh pr merge --disable-auto' r
passes 'Paused.'
# Each PR is tracked: by the URL its create printed, else by the first number a
# settle names; a settle naming no PR acts on the latest one still open.
url=https://github.com/o/r/pull
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r
blocks 'One on auto-merge.' '' "$open"
session u:go 'b:gh pr create' r 'b:gh pr create' r 'b:gh pr merge 7 --auto' r
blocks 'One on auto-merge.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr merge 9 --auto' r
blocks 'Merged another PR.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  "b:gh pr merge $url/2 --auto" r 'b:gh pr merge --auto 1' r
passes 'Both on auto-merge.'
session u:go 'b:gh pr create' r 'b:gh pr create' r 'b:gh pr merge 7 --auto' r 'b:gh pr merge --auto' r
passes 'Both on auto-merge.'
session u:go 'b:gh pr create' r 'b:gh pr merge 7 --auto' r 'b:gh pr merge 7 --disable-auto' r \
  'b:gh pr merge 7 --auto' r
passes 'Auto-merge back on.'
# A settle naming its PR by variable, as in a loop, settles every PR it can.
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in 1 2; do gh pr merge $n --auto; done' r
passes 'Both on auto-merge.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in 1 2; do gh pr merge $n --auto; done' r 'b:for n in 1 2; do gh pr merge $n --disable-auto; done' r
blocks 'Both paused.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:gh pr merge --disable-auto' r
blocks 'One paused.' '' "$open"
# A variable bound by a literal `for` list settles only those numbers; a list that
# is not literal keeps settling all.
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:for n in 1; do gh pr merge $n --disable-auto; done' r
blocks 'Paused one.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:for n in 1; do gh pr merge ${n} --disable-auto; done' r \
  'b:gh pr merge 1 --auto' r
passes 'Paused one, then back on.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:for n in 1 2; do gh pr merge $n --auto; done' r
passes 'Both on auto-merge.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:for n in $(gh pr list -q .[].number); do gh pr merge $n --disable-auto; done' r \
  'b:gh pr merge 1 --auto' r
blocks 'Paused all, one back on.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:for n in 1; do gh pr merge $m --disable-auto; done' r \
  'b:gh pr merge 1 --auto' r
blocks 'Another variable paused all.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  "b:for n in $url/1 $url/2; do gh pr merge \$n --auto; done" r
passes 'Both on auto-merge by URL.'
session u:go 'b:gh pr create' r 'b:gh pr create' r 'b:for n in 7 8; do gh pr merge $n --auto; done' r
passes 'Both on auto-merge, numbers unseen.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in 1; do gh pr merge $n --auto; done; n=2; gh pr merge $n --auto' r
passes 'The variable was reassigned.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:if true; then for n in 1; do gh pr merge $n --auto; done; fi' r
blocks 'A loop after then.' '' "$open"
# A quoted variable names its PR like an unquoted one.
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in 1 2; do gh pr merge "$n" --auto; done' r
passes 'Both on auto-merge, quoted.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge 1 --auto' r \
  'b:gh pr merge 2 --auto' r 'b:for n in 1; do gh pr merge "${n}" --disable-auto; done' r \
  'b:gh pr merge 1 --auto' r
passes 'Paused one, then back on, quoted.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in $(gh pr list -q .[].number); do gh pr merge "$n" --auto; done' r
passes 'Both on auto-merge, quoted and not literal.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" \
  'b:for n in 1; do n="$m"; gh pr merge "$n" --auto; done' r
passes 'Reassigned after do.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr create' "r:$url/2" 'b:gh pr merge -t "$t" 1 --auto' r
blocks 'A quoted flag value is not the PR.' '' "$open"
# A flag's value is not the PR; the first other argument is.
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr merge --auto -t 2026 --match-head-commit 1234567' r
passes 'Auto-merge on.'
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr merge --subject=2026 9 --auto 2>&1' r
blocks 'Merged another PR.' '' "$open"
session u:go 'b:gh pr create' "r:$url/1" 'b:gh pr merge --match-head-commit $(git rev-parse HEAD) 9 --auto' r
blocks 'Merged another PR.' '' "$open"
# A push's /pull/new/ link is not a PR; output with several PR URLs names none.
session u:go 'b:git push -u origin x && gh pr create --fill' \
  "r:remote: Create a pull request for 'x' on GitHub by visiting: $url/new/x
$url/4" 'b:gh pr merge 4 --auto' r
passes 'Auto-merge on.'
session u:go 'b:gh pr create --fill && gh pr view 2 --json url' "r:$url/4
$url/2" 'b:gh pr merge 4 --auto' r
passes 'Auto-merge on.'
# A create that printed output but no PR URL failed; one that printed nothing counts.
session u:go 'b:gh pr create --fill 2>&1 | tail -3' 'r:pull request create failed: GraphQL: No commits between main and x'
passes 'Nothing to open.'
session u:go 'b:url=$(gh pr create --fill)' 'r:   '
blocks 'Opened.' '' "$open"
# A create that printed an existing PR's URL is that PR.
session u:go 'b:gh pr create --fill' "r:$url/1" 'b:gh pr create --fill || true' "r:already exists: $url/1" \
  'b:gh pr merge 1 --auto' r
passes 'Auto-merge on.'
# A subagent's creates count, in time order with the session's own commands.
session u:go 'b:ls' r u:next 'b:git status' r
subagent 5 agent-impl 'u:brief' 'b:gh pr create --fill' "r:$url/3"
blocks 'The implementer opened it.' '' "$open"
session u:go 'b:ls' r u:next 'b:gh pr merge 3 --auto' r
subagent 5 agent-impl 'u:brief' 'b:gh pr create --fill' "r:$url/3"
passes 'Auto-merge on.'
session u:go 'b:gh pr merge 3 --auto' r u:next 'b:git status' r
subagent 25 agent-impl 'u:brief' 'b:gh pr create --fill' "r:$url/3"
blocks 'The implementer opened it.' '' "$open"
session u:go 'b:ls' r u:next 'b:git status' r
subagent 5 agent-impl 'u:brief' 'b:gh pr create --fill' e
subagent 6 agent-other 'u:brief' 'b:echo gh pr create' r
passes 'Nothing opened.'
# Workflow agents sit one level deeper; their journal is not a transcript.
session u:go 'b:ls' r u:next 'b:git status' r
subagent 5 workflows/wf_1/agent-x 'u:brief' 'b:gh pr create --fill' "r:$url/3"
blocks 'The workflow opened it.' '' "$open"
session u:go 'b:ls' r u:next 'b:git status' r
subagent 5 workflows/wf_1/journal 'b:gh pr create --fill' "r:$url/3"
passes 'Nothing opened.'
# An unreadable subagent transcript skips the check with a note.
session u:go 'b:gh pr create --fill' r
mkdir -p "$tmp/t/subagents/agent-x.jsonl"
out=$(input 'Opened.' | python3 "$hook" 2>&1)
case $out in "check-attention: skipped"*) ;; *) echo "error: no skip note for a bad subagent: $out" >&2; exit 1 ;; esac
rm -rf "$tmp/t"

# Missing fields and a missing signal are reported together.
transcript Bash
blocks "$short" '' 'PushNotification'

for bad in 'not json' '{"last_assistant_message":"# Closeout: x"}' '{"last_assistant_message":"# Closeout: x","transcript_path":"/nonexistent"}'; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-attention: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-attention: ok"
