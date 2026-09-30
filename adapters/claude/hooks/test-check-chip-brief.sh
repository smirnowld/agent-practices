#!/bin/sh
# Offline self-test for the chip brief hook: a free-form prompt is denied with
# every missing part named and the template attached; a Model line without
# its tier's model is denied with the tier map; the template with its model filled and
# a filled brief pass silently; bad input passes with a note on stderr.
set -eu
dir=$(dirname "$0")
hook="$dir/check-chip-brief.py"
run() { python3 "$hook"; }
# Pass cases must also leave stderr empty: a skipped check is not a pass.
passes() { out=$(printf '%s\n' "$1" | python3 "$hook" 2>&1); [ -z "$out" ]; }

out=$(echo '{"tool_input":{"prompt":"Fix the stale badge."}}' | run)
for needle in '"permissionDecision": "deny"' "# Brief: TITLE" "Model:" "## Goal" "## Proof" "## Handoff"; do
  echo "$out" | grep -qF "$needle" || { echo "error: deny output lacks: $needle" >&2; exit 1; }
done

template=$(python3 -c 'import json,sys; print(json.dumps({"tool_input": {"prompt": open(sys.argv[1]).read().replace("<tier> (<model>)", "standard (opus)")}}))' "$dir/../../../templates/brief.md")
passes "$template" || { echo "error: templates/brief.md with its model filled was denied; hook and template disagree" >&2; exit 1; }

out=$(printf "%s\n" '{"tool_input":{"prompt":"# Brief: Fix badge\n\n**Model:** standard at medium\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' | run)
echo "$out" | grep -qF "standard (opus)" || { echo "error: tier without model was not denied with the tier map: $out" >&2; exit 1; }
out=$(printf "%s\n" '{"tool_input":{"prompt":"# Brief: Fix badge\n\n**Model:** standard (sonnet) at medium\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' | run)
echo "$out" | grep -qF '"permissionDecision": "deny"' || { echo "error: model not matching its tier was not denied" >&2; exit 1; }

passes '{"tool_input":{"prompt":"  # Brief: Fix badge\n\n  **Model:** fast (Sonnet) at low\n\n  ## Goal\n\nx\n\n  ## Proof\n\n- make check\n"}}' ||
  { echo "error: indented brief was not passed: $out" >&2; exit 1; }

for bad in 'not json' '{"tool_input":null}' '{"tool_input":{"prompt":["x"]}}'; do
  err=$(printf '%s\n' "$bad" | run 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-chip-brief: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-chip-brief: ok"
