#!/bin/sh
# Offline self-test for the attention hook: a card, question or closeout that
# ends a turn without a signal is blocked once; a turn that already signalled,
# a repeat stop, pending background work and plain answers pass silently; bad
# input passes with a note on stderr. A merge without its closeout, and a turn
# that says it waits on CI with nothing running to wake it, are blocked.
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
blocks "$card" '' 'PushNotification'
blocks '# Question: Keep 30-day sign-in?' '' 'PushNotification'
for q in 'Q1. Keep it?' 'Q1: Keep it?' '**Q1.** Keep it?' '**Q1:** Keep it?' 'Q1) Keep it?'; do
  blocks "Two questions.

$q
Q2. Ship today?" '' 'numbered Q1, Q2'
done
passes 'The Q1 numbers are in. Q4 looks slower.'
blocks '**Waiting on me:** acceptance of phase 2' '' 'PushNotification'
blocks '**Waiting on the maintainer:** acceptance of phase 2' '' 'PushNotification'
blocks "$closeout" '' 'PushNotification'
blocks "$card" '{"background_tasks":[]}' '"decision": "block"'

passes '**Waiting on me:** nothing'
passes '**Waiting on me:** "Nothing"'
passes '**Waiting on the maintainer:** nothing'
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
# Acceptance: Real card' '' 'PushNotification'

# A closeout missing template fields is blocked, naming each.
transcript PushNotification
short=$(printf '%s\n' "$closeout" | grep -v -e '^\*\*TL;DR:' -e '^\*\*Status:')
blocks "$short" '' '**Status:**, **TL;DR:**'
# A summary-only chat closeout, its record left to the PR, passes once signalled.
chat=$(cat "$dir/../../../scripts/fixtures/closeout-chat.md")
passes "$chat"
transcript ''; blocks "$chat" '' 'PushNotification'

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
blocks 'Merged as abc.' '' 'send the closeout summary in chat'
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
# call failed). A session's entry N is stamped at time 10*N.
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
session() { entries 0 10 "$@" >"$tmp/t.jsonl"; }
# A dismissed question leaves the turn waiting on me: no repeat question is
# forced, even with a card. Another answer does not.
dismissed='r:The user answered: "Tell me when it is done."="[User dismissed — do not proceed, wait for next instruction]"'
session u:go 'b:ls' r q "$dismissed"
passes 'I will wait.'
passes '**Waiting on me:** the commands above'
session u:go 'b:ls' r q "$dismissed" u:'carry on' 'b:git status' r
blocks "$card" '' 'PushNotification'
# A dismissal does not excuse a merge without its closeout.
session u:go 'b:ls' r q "$dismissed" 'b:gh pr merge 5 --squash' r
blocks 'Merged.' '' 'Closeout incomplete'
# A question a hook denied was not an answer from me: the turn did not restart.
session u:go 'b:ls' r q 'r:PreToolUse:AskUserQuestion hook error: write it first'
blocks "$card" '' 'PushNotification'

# Waiting on CI with no background task running is blocked; nothing wakes it.
transcript Bash
wait='nothing will wake this session'
for msg in "I'm waiting for CI and the auto-merge on [#70](https://github.com/o/r/pull/70), then I'll write the closeout with the merge SHAs and clean up." \
  'Cleanup is done: the worktree and branch are removed. Now waiting for the scheduled verifier run.' \
  "The API tests passed (642). The ts lane is still on its remaining steps; I'll wait for it to finish." \
  'Auto-merge is on for #630, and CI is running. The app will notify me when the checks finish.' \
  "CI is running on all three heads, and I'll report when it finishes."; do
  blocks "$msg" '' "$wait"
  blocks "$msg" '{"background_tasks":[]}' "$wait"
  passes "$msg" '{"background_tasks":[{"id":"t1","type":"bash"}]}'
  passes "\`\`\`
$msg
\`\`\`"
done
passes "I'll merge it once you accept the card."
passes 'Merged as abc123; CI passed and the branch is deleted.'
# Combined with a missing signal in one block.
blocks "$card
CI is running, and I'll report when it finishes." '' 'PushNotification'
blocks "$card
CI is running, and I'll report when it finishes." '' "$wait"

# Missing fields and a missing signal are reported together.
transcript Bash
blocks "$short" '' 'PushNotification'

for bad in 'not json' '{"last_assistant_message":"# Closeout: x"}' '{"last_assistant_message":"# Closeout: x","transcript_path":"/nonexistent"}'; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-attention: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-attention: ok"
