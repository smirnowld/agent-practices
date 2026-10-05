#!/bin/sh
# Offline self-test for the question hook: a question with no chat text after
# the last tool result is denied, however long, and so is its unchanged retry;
# text right before it passes; text before an earlier tool call does not count;
# bad input passes with a note on stderr.
set -eu
dir=$(dirname "$0")
hook="$dir/check-question.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Transcript entries: u:TYPED, a:ASSISTANT_TEXT, t (thinking), b (a Bash call),
# q (AskUserQuestion), p (PushNotification), r[:OUTPUT] (result of the last
# tool call), l:OUTPUT (the same, as a list of text blocks).
session() {
  python3 -c '
import json, sys
k = 0
for arg in sys.argv[1:]:
    kind, _, v = arg.partition(":")
    if kind == "u": e = {"type": "user", "message": {"content": v}}
    elif kind == "a": e = {"type": "assistant", "message": {"content": [{"type": "text", "text": v}]}}
    elif kind == "t": e = {"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": "I laid out the commands."}]}}
    elif kind in ("b", "q", "p"):
        k += 1
        e = {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": "s%d" % k,
             "name": {"b": "Bash", "q": "AskUserQuestion", "p": "PushNotification"}[kind], "input": {}}]}}
    else:
        body = [{"type": "text", "text": v}] if kind == "l" else v
        e = {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "s%d" % k, "content": body}]}}
    print(json.dumps(e))' "$@" >"$tmp/t.jsonl"
}
# ask QUESTION...: the hook input for an AskUserQuestion call.
ask() {
  python3 -c 'import json,sys; print(json.dumps({"transcript_path": sys.argv[1], "tool_input": {"questions": [{"question": q} for q in sys.argv[2:]]}}))' \
    "$tmp/t.jsonl" "$@" | python3 "$hook" 2>&1
}
denied() { ask "$1" | grep -qF '"permissionDecision": "deny"' || { echo "error: not denied: $2" >&2; exit 1; }; }
passes() { out=$(ask "$1"); [ -z "$out" ] || { echo "error: expected silent pass: $2 -> $out" >&2; exit 1; }; }
short="Tell me when you've run them."
long="The deploy is paused and staging still runs yesterday's image. Should I redeploy it now, or wait until the phone checks are done?"

session u:go t
denied "$short" 'thinking only'
session u:go a:'Status.' b r t
denied "$short" 'text before an earlier tool call'
session u:go b r 'a:Run these: `make deploy`'
passes "$short" 'text right before'
session u:go t
denied "$long" 'long question'
session u:go t
ask "$long" "$short" | grep -qF '"permissionDecision": "deny"' || { echo "error: not denied: two questions" >&2; exit 1; }
# The unchanged retry after a denial is denied again, as a string or as blocks;
# writing text first lets it through.
reason=$(ask "$short" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])')
session u:go t q "r:PreToolUse:AskUserQuestion hook error: $reason"
denied "$short" 'unchanged retry'
session u:go t q "l:PreToolUse:AskUserQuestion hook error: $reason" t
denied "$short" 'unchanged retry, result in blocks'
session u:go t q "r:PreToolUse:AskUserQuestion hook error: $reason" 'a:Run: `make deploy`'
passes "$short" 'retry after writing text'
# Text not yet in the transcript when the first call ran: the retry finds it.
session u:go b r 'a:Run: `make deploy`' q "r:PreToolUse:AskUserQuestion hook error: $reason"
passes "$short" 'retry after a race with text already written'
# A ToolSearch result is not a step; whitespace is not text; stop-hook
# feedback (isMeta) is not my message.
session u:go b r a:'Card.' b
python3 - "$tmp/t.jsonl" <<'PY'
import json, sys
p = sys.argv[1]
lines = open(p).read().splitlines()
lines[-1] = lines[-1].replace('"Bash"', '"ToolSearch"')
lines.append(json.dumps({"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": "s2", "content": "loaded"}]}}))
lines.append(json.dumps({"type": "user", "isMeta": True, "message": {"content": "Stop hook feedback: ask now"}}))
open(p, "w").write("\n".join(lines) + "\n")
PY
passes "$short" 'after ToolSearch and stop-hook feedback'
session u:go b r 'a:   '
denied "$short" 'whitespace-only text'
# A closeout, its notification, then its question: the notification is not a step.
session u:go b r a:'# Closeout: Done' p r:'Mobile push requested.'
passes "$short" 'question after a closeout and its notification'
# An answered question starts a new step; so does my typed message.
session u:go a:'Commands.' q r:'User answered' t
denied "$short" 'after an answer'
session a:'Commands.' u:'I see nothing' t
denied "$short" 'after my message'

for bad in 'not json' '{"tool_input":{"questions":[{"question":"x"}]}}' '{"tool_input":{"questions":[{"question":"x"}]},"transcript_path":"/nonexistent"}'; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-question: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-question: ok"
