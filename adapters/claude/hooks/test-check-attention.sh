#!/bin/sh
# Offline self-test for the attention hook: a card, question or closeout that
# ends a turn without a signal is blocked once; a turn that already signalled,
# a repeat stop and plain answers pass silently; bad input passes with a note
# on stderr. A merge without its closeout, a turn that says it waits on CI
# with none of its background tasks or subagents running, and a turn that ends
# with its own wait-for running and no word of waiting, are blocked; so is a
# closeout written without the closeout skill, and an auto-merge that landed
# without its closeout.
set -eu
dir=$(dirname "$0")
hook="$dir/check-attention.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A transcript: the closeout skill loaded, my message, then an assistant turn
# calling TOOL (none if empty).
skill='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"sk","name":"Skill","input":{"skill":"agent-practices:closeout"}}]}}'
transcript() {
  printf '%s\n' "$skill" '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion"}]}}' \
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
# Running background tasks in the hook input excuse nothing.
blocks "$card" '{"background_tasks":[{"id":"t1","type":"subagent"}]}' 'PushNotification'
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
printf '%s\n' "$skill" '{"type":"user","message":{"content":[{"type":"text","text":"go"}]}}' \
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
printf '%s\n' "$skill" '{"type":"user","message":{"content":"go"}}' \
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
# is an earlier assistant message. The closeout skill was loaded earlier.
merge_turn() {
  text=$1; shift
  printf '%s\n' "$skill" '{"type":"user","message":{"content":"merge it"}}' >"$tmp/t.jsonl"
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
# A session's entries: u:TYPED, a:ASSISTANT_TEXT, b:BASH_COMMAND, w:BASH_COMMAND (in
# the background), q (AskUserQuestion), p (PushNotification), s (the closeout skill),
# k:TASK_ID (TaskStop), r[:OUTPUT] (answer to the last tool call), e (the last tool
# call failed), n:EXIT (the last background call ended with EXIT). Entry N is
# stamped at time 10*N.
entries() {
  python3 -c '
import json, sys
k, start, step = 0, int(sys.argv[1]), int(sys.argv[2])
for n, arg in enumerate(sys.argv[3:]):
    kind, _, v = arg.partition(":")
    if kind == "u": e = {"type": "user", "message": {"content": v}}
    elif kind == "a": e = {"type": "assistant", "message": {"content": [{"type": "text", "text": v}]}}
    elif kind in ("b", "w", "q", "p", "s", "k"):
        k += 1
        tool = {"type": "tool_use", "id": "s%d" % k, "name": "Bash", "input": {"command": v}}
        if kind == "w": tool["input"]["run_in_background"] = True
        if kind in "qp": tool.update(name={"q": "AskUserQuestion", "p": "PushNotification"}[kind], input={})
        if kind == "s": tool.update(name="Skill", input={"skill": "agent-practices:closeout"})
        if kind == "k": tool.update(name="TaskStop", input={"task_id": v})
        e = {"type": "assistant", "message": {"content": [tool]}}
    elif kind == "n":
        e = {"type": "user", "origin": {"kind": "task-notification"}, "message": {"content":
             "<task-notification>\n<tool-use-id>s%d</tool-use-id>\n<status>%s</status>\n<summary>Background "
             "command \"Wait\" %s with exit code %s</summary>\n</task-notification>"
             % (k, "completed" if v == "0" else "failed", "completed (exit code 0)" if v == "0" else "failed", v)}}
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
# A closeout needs the closeout skill loaded this session; a slash command counts.
session u:go p r
blocks "$closeout" '' 'Skill `agent-practices:closeout`'
session u:go s r p r
passes "$closeout"
session u:go s e p r
blocks "$closeout" '' 'Skill `agent-practices:closeout`'
session 'u:<command-name>/agent-practices:closeout</command-name>' p r
passes "$closeout"

# An auto-merge that lands in a later wake of the same turn is a merge: by the
# background wait's exit 0, wait-for's final line, or gh's MERGED state.
auto='b:gh pr merge 5 --auto --squash --match-head-commit abc'
waitci='w:/p/bin/wait-for pr-ci 5'
edit='b:gh pr edit 5 --body-file b.md'
session u:go "$auto" r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'Skill `agent-practices:closeout`'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 p r "$edit" r
passes 'Merged as abc.'
session u:go s r "$auto" r "$waitci" r n:0 p r "$edit" r
blocks 'Merged as abc.' '' 'send the closeout summary in chat'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r "$edit" r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r "$waitci; echo \$?" r n:0 'b:cat out' 'r:merged: PR 5 at abc' p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r 'b:gh pr view 5 --json state' 'r:{"state":"MERGED"}' p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r 'b:cat out' 'r:passed: CI on PR 5 at abc (runs 1)' p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go "$auto" r "$waitci" r n:0 p r
blocks "$closeout" '' 'Skill `agent-practices:closeout`'
# A redirection after the wait keeps its exit code; a PR named by URL, or none
# (the branch's own), is the same PR.
session u:go s r a:"$closeout" "$auto" r "$waitci 2>&1" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" 'b:gh pr merge https://github.com/o/r/pull/5 --auto --squash' r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" 'b:gh pr merge --auto --squash' r 'b:gh pr view --json state' 'r:{"state":"MERGED"}' p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
# Another PR merging, or a file that mentions the state, is not this landing and
# does not hide it.
session u:go s r a:"$closeout" "$auto" r 'b:gh pr view 9 --json state' 'r:{"state":"MERGED"}' 'b:cat README.md' 'r:"state":"MERGED"' 'w:wait-for pr-merged 9' r n:0 p r
passes 'PR 9 merged; PR 5 still waits.'
session u:go s r a:"$closeout" "$auto" r 'b:gh pr view 9 --json state' 'r:{"state":"MERGED"}' "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
# Not landings: a failed wait, a wrapped exit code alone, no auto-merge of this
# session's, auto-merge refused or turned off, a landing in an earlier turn.
session u:go "$auto" r "$waitci" r n:1 p r
passes 'CI failed on PR 5.'
session u:go "$auto" r "$waitci; echo \$?" r n:0 p r
passes 'The wait ended.'
session u:go 'w:wait-for pr-merged 9' r n:0 'b:gh pr view 9 --json state' 'r:{"state":"MERGED"}' p r
passes 'PR 9 merged; continuing.'
session u:go "$auto" e "$waitci" r n:0 'b:gh pr view 5' 'r:{"state":"MERGED"}' p r
passes 'Auto-merge was refused.'
session u:go "$auto" r 'b:gh pr merge 5 --disable-auto' r "$waitci" r n:0 p r
passes 'CI passed; auto-merge is off.'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 "$edit" r u:status 'b:gh pr view 5' 'r:{"state":"MERGED"}'
passes 'It is merged.'
# A redirection's fd or a pinned head SHA is not the PR a command names.
session u:go s r a:"$closeout" 'b:gh pr merge --auto --squash --match-head-commit abc 2>&1' r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" 'b:gh pr merge --auto --squash --match-head-commit 1234567' r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" 'b:gh pr merge --auto --squash --match-head-commit=1234567' r "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r 'b:gh pr view --json state 2>&1' 'r:{"state":"MERGED"}' p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
# Turning auto-merge off for a PR also turns off the branch's own.
session u:go 'b:gh pr merge --auto --squash' r 'b:gh pr merge 5 --disable-auto' r "$waitci" r n:0 p r
passes 'CI passed; auto-merge is off.'
# Passed CI with auto-merge still pending re-arms it: the later merge is a landing,
# in the same turn or a later one. A closed-out merge seen again is not.
pending='r:{"autoMergeRequest":{"enabledAt":"2026-01-01T00:00:00Z"},"state":"OPEN"}'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 'b:gh pr view 5 --json state,autoMergeRequest' "$pending" \
  "$edit" r u:'approved it' 'b:gh pr view 5 --json state' 'r:{"state":"MERGED"}'
blocks 'Merged as abc.' '' 'gh pr edit --body-file'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 'b:gh pr view 5 --json state,autoMergeRequest' "$pending" \
  u:'approved it' 'b:gh pr view 5 --json state' 'r:{"state":"MERGED"}' "$edit" r
passes 'Merged as abc.'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 'b:gh pr view 5 --json state,autoMergeRequest' 'r:{"autoMergeRequest":null,"state":"OPEN"}' \
  "$edit" r u:status 'b:gh pr view 5 --json state' 'r:{"state":"MERGED"}'
passes 'It is merged.'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 'b:gh pr view 5 --json state,autoMergeRequest' \
  'r:{"autoMergeRequest":{"enabledAt":"x"},"state":"MERGED"}' "$edit" r u:status 'b:gh pr view 5 --json state' 'r:{"state":"MERGED"}'
passes 'It is merged.'
session u:go s r a:"$closeout" 'b:gh pr view 9 --json state,autoMergeRequest' "$pending" u:next 'b:gh pr view 9' 'r:{"state":"MERGED"}'
passes 'PR 9 merged.'
# A number-less arming re-arms only the PR whose landing was seen, and a
# number-less disable turns a re-armed one off too.
session u:go s r a:"$closeout" 'b:gh pr merge --auto --squash' r "$waitci" r n:0 "$edit" r \
  u:next 'b:gh pr view 9 --json state,autoMergeRequest' "$pending" 'b:gh pr view 9' 'r:{"state":"MERGED"}'
passes 'PR 9 merged.'
session u:go 'b:gh pr merge --auto --squash' r "$waitci" r n:0 'b:gh pr view 5 --json state,autoMergeRequest' "$pending" \
  'b:gh pr merge --disable-auto' r u:next 'b:gh pr view 5' 'r:{"state":"MERGED"}'
passes 'PR 5 merged.'
# A number-less view re-arms what was armed, not any PR.
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 "$edit" r u:status 'b:gh pr view --json state,autoMergeRequest' "$pending" \
  u:next 'w:wait-for pr-merged 9' r n:0 p r
passes 'PR 9 merged; 5 still waits on review.'
session u:go s r a:"$closeout" "$auto" r "$waitci" r n:0 "$edit" r u:status 'b:gh pr view --json state,autoMergeRequest' "$pending" \
  u:next "$waitci" r n:0 p r
blocks 'Merged as abc.' '' 'gh pr edit --body-file'

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
  blocks "$msg" '{"background_tasks":[{"id":"t1","type":"bash"}]}' "$wait"
  passes "\`\`\`
$msg
\`\`\`"
done
passes "I'll merge it once you accept the card."
passes 'Waiting for your answer before I merge.'
# Mentioning me elsewhere in the sentence does not hide a wait on CI.
blocks "CI is running; I'll report back when it finishes so you can review." '' "$wait"
blocks 'Waiting for CI on #70; let me know if you want anything else.' '' "$wait"
passes 'Merged as abc123; CI passed and the branch is deleted.'
# Combined with a missing signal in one block.
blocks "$card
CI is running, and I'll report when it finishes." '' 'PushNotification'
blocks "$card
CI is running, and I'll report when it finishes." '' "$wait"

# The session's own waits, read from the transcript. A background result names
# the task; a notification or TaskStop ends it.
bg='r:Command running in background with ID: bg1. Output is being written to: /tmp/bg1.output'
moved='r:Command did not finish within its 600s timeout and was moved to the background (ID: bg1). Output'
note='<task-notification>
<task-id>bg1</task-id>
<tool-use-id>s2</tool-use-id>
<status>completed</status>
</task-notification>'
open='This session'"'"'s own wait still runs'
claim="CI is running, and I'll report when it finishes."
for start in 'w:wait-for pr-ci 5' 'w:/p/bin/wait-for -R o/r pr-merged 5' 'w:cd x && wait-for run 9' \
  'w:(wait-for pr-ci 5)' 'w:env X=1 time wait-for pr-ci 5' 'w:for p in 5 6; do wait-for pr-ci $p; done' \
  'w:sh bin/wait-for pr-ci 5'; do
  session u:go 'b:ls' r "$start" "$bg"
  blocks "$closeout" '' "$open"
  blocks "$closeout" '' 'TaskStop'
  blocks 'Done.' '' "$open"
  blocks "Merged as abc. I'll clean up the worktree now." '' "$open"
  passes "$claim"
  passes 'wait-for runs in the background; I will report when it ends.'
  passes "I'm waiting for it to finish."
  blocks '' '' "$open"
  blocks '```
fenced only
```' '' "$open"
done
# A foreground wait moved to the background on timeout is still running.
session u:go 'b:ls' r 'b:wait-for pr-ci 5' "$moved"
blocks 'Done.' '' "$open"
# It ended: notified by task id or tool-use id, or stopped.
session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg" u:"$note"
passes 'Merged as abc.'
session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg" u:"<task-notification><tool-use-id>s2</tool-use-id></task-notification>"
passes 'Merged as abc.'
session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg" k:bg1 r
passes 'Merged as abc.'
session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x1","name":"KillShell","input":{"shell_id":"bg1"}}]}}' >>"$tmp/t.jsonl"
passes 'Merged as abc.'
session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg"
python3 -c 'import json,sys; print(json.dumps({"type":"user","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$note" >>"$tmp/t.jsonl"
passes 'Merged as abc.'
# Mid-turn, the notification is a queued-command attachment or a queue operation.
for shape in '{"type":"attachment","attachment":{"type":"queued_command","prompt":NOTE}}' \
  '{"type":"queue-operation","operation":"enqueue","content":NOTE}'; do
  session u:go 'b:ls' r 'w:wait-for pr-ci 5' "$bg"
  python3 -c 'import json,sys; print(sys.argv[1].replace("NOTE", json.dumps(sys.argv[2])))' "$shape" "$note" >>"$tmp/t.jsonl"
  passes 'Merged as abc.'
done
# A notification only quoted in a tool result ends nothing.
session u:go 'w:wait-for pr-ci 5' "$bg" 'b:cat log' r:"$note"
blocks 'Done.' '' "$open"
# A failed call or one without its background result is not a running wait.
session u:go 'w:wait-for pr-ci 5' e:"$bg"
passes 'Done.'
session u:go 'b:wait-for pr-ci 5'
passes 'Done.'
# Not the session's own waits: a script with the name in it, a quoted mention.
session u:go 'w:sh bin/test-wait-for.sh' "$bg" 'w:grep "wait-for pr-ci" README.md' "$bg"
passes 'Done.'
# Any other running background task excuses a waiting claim, since its end wakes
# the session: a local test run, and a dev server too (accepted); once it ends,
# the claim is blocked again.
docs='The docs check (`make check`) is running in the background and will wake this session.'
session u:go 'w:make check' "$bg"
passes "$docs"
passes 'Done.'
session u:go 'w:make check' "$bg" u:"$note"
blocks "$docs" '' "$wait"
session u:go 'w:npm run dev' "$bg"
passes "$claim"
# A command moved to the background on timeout is a running task too.
session u:go 'b:make check' "$moved"
passes "$docs"
passes 'Done.'
# Output that only quotes a background result is no task: a foreground call's,
# a quote after the first line, or a grep line that quotes it.
session u:go 'b:cat adapters/claude/hooks/test-check-attention.sh' "$bg"
blocks "$claim" '' "$wait"
session u:go 'w:cat test.sh' "r:#!/bin/sh
bg='${bg#r:}'
moved='${moved#r:}'"
blocks "$claim" '' "$wait"
session u:go 'b:grep -n moved test.sh' "r:351:moved='${moved#r:}'"
blocks "$claim" '' "$wait"
session u:go 'w:grep -n bg= test.sh' "r:350:bg='${bg#r:}'"
blocks "$claim" '' "$wait"
# A background subagent excuses it until its notification, by task id or
# tool-use id, arrives or it is stopped; a synchronous one, or a failed launch,
# does not, nor does a synchronous report that quotes the launch line.
agent() {
  session u:go
  python3 -c '
import json, sys
print(json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "ag1",
    "name": sys.argv[1], "input": {"description": "Review the diff", "run_in_background": True}}]}}))
print(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "ag1",
    "is_error": sys.argv[3:] == ["e"], "content": [{"type": "text", "text": sys.argv[2]}]}]}}))' "$@" >>"$tmp/t.jsonl"
}
launched='Async agent launched successfully.
agentId: a1b2c3 (use SendMessage with to: a1b2c3 to continue this agent)'
review="I'm waiting on the review run; it'll report when it finishes."
for name in Agent Task; do
  agent "$name" "$launched"
  passes "$review"
  passes 'Done.'
done
agent Agent "$launched"
printf '%s\n' '{"type":"user","message":{"content":"<task-notification>\n<task-id>a1b2c3</task-id>\n<status>completed</status>\n</task-notification>"}}' >>"$tmp/t.jsonl"
blocks "$review" '' "$wait"
agent Agent "$launched"
python3 -c 'import json,sys; print(json.dumps({"type":"attachment","attachment":{"type":"queued_command","prompt":sys.argv[1]}}))' \
  '<task-notification><tool-use-id>ag1</tool-use-id><status>completed</status></task-notification>' >>"$tmp/t.jsonl"
blocks "$review" '' "$wait"
agent Agent "$launched"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x1","name":"TaskStop","input":{"task_id":"a1b2c3"}}]}}' >>"$tmp/t.jsonl"
blocks "$review" '' "$wait"
agent Agent 'The review found no problems.'
blocks "$review" '' "$wait"
agent Agent "The hook reads the launch result:
$launched"
blocks "$review" '' "$wait"
agent Agent "$launched" e
blocks "$review" '' "$wait"
# A true wait on a merge with nothing running is still blocked.
session u:go "$auto" r
blocks "I'm waiting for the merge, and it'll wake me." '' "$wait"
# GitHub watches excuse a waiting claim but are not the closeout's to stop.
for watch in 'w:gh run watch 9 --exit-status' 'w:gh pr checks 5 --watch' \
  'w:timeout 1500 gh pr checks 5 --watch' 'w:GH_REPO=o/r gh run watch 9' 'w:gh -R o/r run watch 9'; do
  session u:go "$watch" "$bg"
  passes "$claim"
  passes 'Done.'
done
# A sentence that describes waits, not a wait, passes.
transcript Bash
passes 'A wait on CI or a merge now always ends and wakes the session: when CI passes or fails, on a conflict or a new push, and at a time limit.'
for msg in 'Auto-merge is on; the PR will merge once CI passes.' 'The PR auto-merges when CI passes.' \
  'The branch merges once the build finishes.'; do
  blocks "$msg" '' "$wait"
done
blocks "I'll merge it when CI passes." '' "$wait"
blocks 'Merging once the checks pass is next; I will report when CI is green.' '' "$wait"

# My answer to a question with no text after it leaves the final message the
# one I answered (#45): it is not checked again.
session u:go a:"$card" q 'r:The user answered: accept'
passes "$card"
session u:go a:"$card" q 'r:The user answered: accept' a:'Thanks, merging.'
blocks "$card" '' 'PushNotification'
# A final message the transcript does not hold yet is still checked.
session u:go a:"$card" q 'r:The user answered: accept'
blocks "$closeout" '' 'PushNotification'
session u:go 'w:wait-for pr-ci 5' "$bg" a:"$card" q 'r:The user answered: accept'
passes "$card"

# Missing fields and a missing signal are reported together.
transcript Bash
blocks "$short" '' 'PushNotification'

for bad in 'not json' '{"last_assistant_message":"# Closeout: x"}' '{"last_assistant_message":"# Closeout: x","transcript_path":"/nonexistent"}'; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-attention: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-attention: ok"
