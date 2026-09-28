#!/bin/sh
# Offline self-test for session-usage.py against a synthetic transcript:
# streamed chunks of one message count once, a response without a usage
# block counts, compactions and their starting context are read from the
# boundary record, read-style calls, waits, images, large results and
# re-read files are counted, the subagent is found through its meta file,
# `--row` prints one table row, and an unknown or ambiguous id exits 2.
set -eu
dir=$(dirname "$0")
export CLAUDE_CONFIG_DIR="$dir/fixtures/session"
out=$(python3 "$dir/session-usage.py" abcd)
for needle in \
  "responses 5  model model-a  elapsed 1h30m" \
  "tokens: input 10  cache read 230k  cache write 10k  output 280" \
  "context per response: first 65k  mean by quarter 65k / 71k / 81k / 23k  max 81k" \
  "compactions 1  from 150k" \
  "tool calls 5: 3 Bash, 1 Read, 1 Agent:agent-practices:reviewer" \
  "read-style shell calls 3  waits 1  images 1  results over 5k chars 1 (6k chars)" \
  "files opened more than twice (1): a.py x3" \
  "agent-practices:reviewer  model-b  responses 2  cache read 65k  cache write 2k  output 700  Review the slice" \
  "total cache read including subagents: 295k" \
; do
  echo "$out" | grep -qF "$needle" || { echo "error: not reported: $needle" >&2; echo "$out" >&2; exit 1; }
done

row=$(python3 "$dir/session-usage.py" abcd1234-0000-0000-0000-000000000001 --row)
want="| 2026-01-01 | Claude Code | <project and slice> | parent model-a; reviewer model-b | 5 (+2 in subagents) | 10 / 295k / 980 | 1 | 1h30m | <proof done> | <rework> |"
[ "$row" = "$want" ] || { echo "error: row differs:" >&2; echo "$row" >&2; exit 1; }

# The transcript path works too.
python3 "$dir/session-usage.py" "$dir/fixtures/session/projects/-tmp-proj/abcd1234-0000-0000-0000-000000000001.jsonl" >/dev/null

for bad in nosuch abc; do
  rc=0; python3 "$dir/session-usage.py" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "error: $bad exited $rc, not 2" >&2; exit 1; }
done

echo "session-usage self-test passed"
