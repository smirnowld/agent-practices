#!/bin/sh
# Offline self-test for the session-title hook: where the rename tool is
# available, a stop without a title in the session-title format is blocked
# once; a good title, a session without the tool, one that already called it,
# a scheduled routine and a repeat stop pass silently; bad input never blocks.
set -eu
dir=$(dirname "$0")
hook="$dir/check-session-title.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tool=mcp__ccd_session_mgmt__set_session_title
avail='{"type":"attachment","attachment":{"type":"deferred_tools_delta","addedNames":["Monitor","'$tool'"]}}'
other='{"type":"attachment","attachment":{"type":"deferred_tools_delta","addedNames":["Monitor"]}}'
called='{"type":"assistant","message":{"content":[{"type":"tool_use","name":"'$tool'","input":{"session_id":"self"}}]}}'
# title TEXT: a custom-title line.
title() { python3 -c 'import json,sys; print(json.dumps({"type":"custom-title","customTitle":sys.argv[1]}, ensure_ascii=False))' "$1"; }
# transcript LINE...: the transcript, with a malformed line and my message first.
transcript() {
  printf '%s\n' 'not json' '{"type":"user","message":{"content":"go"}}' "$@" >"$tmp/t.jsonl"
}
input() {
  python3 -c 'import json,sys; print(json.dumps({"transcript_path":sys.argv[1],"stop_hook_active":sys.argv[2]=="1","session_id":"x"}))' \
    "$tmp/t.jsonl" "${1:-0}"
}
blocks() { out=$(input | python3 "$hook"); echo "$out" | grep -qF "$1" || { echo "error: not blocked with '$1' -> $out" >&2; exit 1; }; }
# Pass cases must also leave stderr empty: a skipped check is not a pass.
passes() { out=$(input "${1:-0}" | python3 "$hook" 2>&1); [ -z "$out" ] || { echo "error: expected silent pass -> $out" >&2; exit 1; }; }

transcript "$avail"
blocks '"decision": "block"'
blocks "$tool"
blocks 'session_id \"self\"'
blocks 'WP12 checkout contract for guest orders'
blocks 'size it first'
blocks 'Rename only; change nothing else in this continuation.'
passes 1

transcript "$avail" "$(title 'Fix the login bug')"
blocks 'The current title is \"Fix the login bug\"'

for t in '🟢 Fix·XS — login redirect loop' '🔵 Build·M — WP12 checkout contract for guest orders' \
  '🟡 Decide·S — choose next tasks' '🔴 Research·M — cache eviction under load' \
  '🔵️ Land·XS — #12 merge' '⏱ Routine — PROJECT: triage, daily 07:00 UTC' '⏱️ Routine — issue review'; do
  transcript "$avail" "$(title "$t")"; passes
done
for t in '🔵 Build·M - WP12 hyphen' '🔵 Fix-M — wrong separator' '🔵 Build·L — too big' \
  '🔵 Build·M — ' 'Build·M — no marker' '🟣 Build·M — wrong marker' '🔵 Routine·S — routine with size' \
  '⏱ Build·M — routine marker on a build'; do
  transcript "$avail" "$(title "$t")"; blocks '"decision": "block"'
done

# The latest title wins.
transcript "$avail" "$(title '🔵 Build·M — first')" "$(title 'renamed by the app')"
blocks 'renamed by the app'
transcript "$avail" "$(title 'renamed by the app')" "$(title '🔵 Build·M — fixed')"
passes

# Surrounding whitespace is ignored.
transcript "$avail" "$(title '  🔵 Build·M — padded  ')"; passes

# No rename tool (CLI, cloud): nothing to do.
transcript "$other"; passes
transcript; passes
# The tool was called (a declined rename is not retried), even if the title is still bad.
transcript "$avail" "$(title 'Fix the login bug')" "$called"; passes
# A call alone shows the tool is available.
transcript "$called"; passes
# Loading the rename tool with ToolSearch is not a rename: it still blocks.
transcript "$avail" '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"ToolSearch","input":{"query":"select:'$tool'"}}]}}'
blocks '"decision": "block"'

# A scheduled routine passes, as a string or a text item; a later mention does not count.
printf '%s\n' '{"type":"user","message":{"content":"<scheduled-task name=\"triage\">run</scheduled-task>"}}' "$avail" >"$tmp/t.jsonl"; passes
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"<scheduled-task name=\"x\">"}]}}' "$avail" >"$tmp/t.jsonl"; passes
printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"<system-reminder>ctx</system-reminder>"},{"type":"text","text":" <scheduled-task name=\"x\">"}]}}' "$avail" >"$tmp/t.jsonl"; passes
printf '%s\n' '{"type":"user","message":{"content":"go"}}' '{"type":"user","message":{"content":"<scheduled-task>"}}' "$avail" >"$tmp/t.jsonl"
blocks '"decision": "block"'

for bad in 'not json' '{"stop_hook_active":false}' '{"transcript_path":"/nonexistent"}'; do
  out=$(printf '%s\n' "$bad" | python3 "$hook" 2>/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  [ -z "$out" ] || { echo "error: blocked on bad input: $bad -> $out" >&2; exit 1; }
done
echo "check-session-title: ok"
