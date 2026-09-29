#!/bin/sh
# Offline self-test for the attention hook: a card, question or closeout that
# ends a turn without a signal is blocked once; a turn that already signalled,
# a repeat stop, pending background work and plain answers pass silently; bad
# input passes with a note on stderr.
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

card='Done.

# Acceptance: New sign-in screen

**Decision needed:** accept / change / reject'
transcript Bash
blocks "$card" '' 'AskUserQuestion'
blocks '# Question: Keep 30-day sign-in?' '' 'AskUserQuestion'
blocks '**Waiting on me:** acceptance of phase 2' '' 'AskUserQuestion'
blocks '# Closeout: Fix badge' '' 'PushNotification'
blocks "$card" '{"background_tasks":[]}' '"decision": "block"'

passes '**Waiting on me:** nothing'
passes '**Waiting on me:** "Nothing"'
passes 'Here is the answer: 42.'
passes "$card" '{"stop_hook_active":true}'
passes "$card" '{"background_tasks":[{"id":"t1","type":"subagent"}]}'
transcript AskUserQuestion; passes "$card"
transcript PushNotification; passes '# Closeout: Fix badge'
# A signal from an earlier turn does not count for this one.
transcript ''; blocks '# Closeout: Fix badge' '' 'PushNotification'

# An early clarifying question does not cover a closeout written after my answer.
printf '%s\n' '{"type":"user","message":{"content":"build it"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"q1"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash"}]}}' >"$tmp/t.jsonl"
blocks '# Closeout: Fix badge' '' 'PushNotification'
# Another tool result after the signal keeps it; a notification wakes nothing.
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"go"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"p1"}]}}' \
  '{"type":"user","isMeta":true,"message":{"content":"meta"}}' \
  '{"type":"user","isCompactSummary":true,"message":{"content":"summary"}}' \
  '{"type":"user","message":{"content":"<task-notification>done</task-notification>"}}' \
  '[1]' >"$tmp/t.jsonl"
passes '# Closeout: Fix badge'
# A list of text parts is a typed message and resets the turn.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","message":{"content":[{"type":"text","text":"next"}]}}' >"$tmp/t.jsonl"
blocks '# Closeout: Fix badge' '' 'ToolSearch'

# A typed message is known by its origin when present, even behind a harness tag.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","origin":{"kind":"human"},"message":{"content":"<system-reminder>x</system-reminder> next"}}' >"$tmp/t.jsonl"
blocks '# Closeout: Fix badge' '' 'PushNotification'
printf '%s\n' '{"type":"user","message":{"content":"go"}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"p1","name":"PushNotification"}]}}' \
  '{"type":"user","origin":{"kind":"task-notification"},"message":{"content":"done"}}' >"$tmp/t.jsonl"
passes '# Closeout: Fix badge'

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

for bad in 'not json' '{"last_assistant_message":"# Closeout: x"}' '{"last_assistant_message":"# Closeout: x","transcript_path":"/nonexistent"}'; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-attention: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-attention: ok"
