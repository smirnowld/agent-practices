#!/bin/sh
# Offline self-test for the chip brief hook: a free-form prompt is denied with
# every missing part named and the template attached; the template itself and
# a filled brief pass silently; bad input passes with a note on stderr.
set -eu
dir=$(dirname "$0")
hook="$dir/check-chip-brief.py"
run() { python3 "$hook"; }

out=$(echo '{"tool_input":{"prompt":"Fix the stale badge."}}' | run)
for needle in '"permissionDecision": "deny"' "# Brief: TITLE" "Model:" "## Goal" "## Proof" "## Handoff"; do
  echo "$out" | grep -qF "$needle" || { echo "error: deny output lacks: $needle" >&2; exit 1; }
done

template=$(python3 -c 'import json,sys; print(json.dumps({"tool_input": {"prompt": open(sys.argv[1]).read()}}))' "$dir/../../../templates/brief.md")
out=$(echo "$template" | run)
[ -z "$out" ] || { echo "error: templates/brief.md itself was denied; hook and template disagree" >&2; exit 1; }

out=$(printf '%s' '{"tool_input":{"prompt":"  # Brief: Fix badge\n\n  **Model:** small at low\n\n  ## Goal\n\nx\n\n  ## Proof\n\n- make check\n"}}' | run)
[ -z "$out" ] || { echo "error: indented brief was denied: $out" >&2; exit 1; }

for bad in 'not json' '{"tool_input":null}' '{"tool_input":{"prompt":["x"]}}'; do
  err=$(echo "$bad" | run 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-chip-brief: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-chip-brief: ok"
