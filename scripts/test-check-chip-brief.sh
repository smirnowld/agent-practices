#!/bin/sh
# Offline self-test for the chip brief hook: a free-form prompt is denied with
# every missing part named and the template attached; a brief passes silently.
set -eu
hook="$(dirname "$0")/../adapters/claude/hooks/check-chip-brief.py"
out=$(echo '{"tool_input":{"prompt":"Fix the stale badge."}}' | python3 "$hook")
for needle in '"permissionDecision": "deny"' "# Brief: TITLE" "Model:" "## Goal" "## Proof" "## Handoff"; do
  echo "$out" | grep -qF "$needle" || { echo "error: deny output lacks: $needle" >&2; exit 1; }
done
out=$(printf '%s' '{"tool_input":{"prompt":"# Brief: Fix badge\n\n**Model:** small at low\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' | python3 "$hook")
[ -z "$out" ] || { echo "error: valid brief was denied: $out" >&2; exit 1; }
echo "check-chip-brief: ok"
