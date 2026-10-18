#!/bin/sh
# Offline self-test for the brief hook on session starts and cards: a
# free-form prompt is denied with every missing part named and the template
# attached; a Model line without its tier's model is denied with the tier map;
# the template with its model and effort filled and a filled brief pass
# silently; a missing or unknown effort word is denied; a call without a prompt passes
# only as an offer or with a proposal_id; a passed model or effort must match
# the Model line; a call with a brief must pass both unless its context is
# "fork" (an omitted context is fresh);
# a session started now may not exceed the starter's model or effort;
# spawn_task (older builds) gets only the brief check; bad input passes
# with a note on stderr.
set -eu
dir=$(dirname "$0")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
hook="$dir/check-chip-brief.py"
run() { python3 "$hook"; }
# Pass cases must also leave stderr empty: a skipped check is not a pass.
passes() { out=$(printf '%s\n' "$1" | python3 "$hook" 2>&1); [ -z "$out" ]; }

out=$(echo '{"tool_input":{"initiation":"own_initiative","title":"x","prompt":"Fix the stale badge."}}' | run)
for needle in '"permissionDecision": "deny"' "# Brief: TITLE" "Model:" "## Goal" "## Proof" "## Handoff"; do
  echo "$out" | grep -qF "$needle" || { echo "error: deny output lacks: $needle" >&2; exit 1; }
done

template=$(python3 -c 'import json,sys; print(json.dumps({"tool_input": {"initiation": "own_initiative", "title": "x", "model": "opus", "effort": "medium", "prompt": open(sys.argv[1]).read().replace("<tier> (<model>) at <effort>", "standard (opus) at medium")}}))' "$dir/../../../templates/brief.md")
passes "$template" || { echo "error: templates/brief.md with its model and effort filled was denied; hook and template disagree" >&2; exit 1; }

out=$(printf "%s\n" '{"tool_input":{"initiation":"own_initiative","title":"x","prompt":"# Brief: Fix badge\n\n**Model:** standard at medium\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' | run)
echo "$out" | grep -qF "standard (opus)" || { echo "error: tier without model was not denied with the tier map: $out" >&2; exit 1; }
out=$(printf "%s\n" '{"tool_input":{"initiation":"own_initiative","title":"x","prompt":"# Brief: Fix badge\n\n**Model:** standard (sonnet) at medium\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' | run)
echo "$out" | grep -qF '"permissionDecision": "deny"' || { echo "error: model not matching its tier was not denied" >&2; exit 1; }

passes '{"tool_input":{"initiation":"own_initiative","title":"x","model":"sonnet","effort":"low","prompt":"  # Brief: Fix badge\n\n  **Model:** fast (Sonnet) at low\n\n  ## Goal\n\nx\n\n  ## Proof\n\n- make check\n"}}' ||
  { echo "error: indented brief was not passed: $out" >&2; exit 1; }

out=$(echo '{"tool_input":{"proposal_id":"task_ab12","prompt":"Fix the stale badge."}}' | run)
echo "$out" | grep -qF '"permissionDecision": "deny"' || { echo "error: prompt with proposal_id was not denied; the hook must not skip on proposal_id" >&2; exit 1; }

for empty in '{"tool_input":{"proposal_id":"task_ab12"}}' '{"tool_input":{"initiation":"offer","title":"Fix badge"}}'; do
  passes "$empty" || { echo "error: call with no prompt was not passed silently: $empty" >&2; exit 1; }
done
out=$(echo '{"tool_input":{"initiation":"user_asked","prompt":""}}' | run)
echo "$out" | grep -qF "needs the filled brief as its prompt" || { echo "error: empty-prompt user_asked was not denied: $out" >&2; exit 1; }

for bad in 'not json' '{"tool_input":null}' '{"tool_input":{"initiation":"own_initiative","title":"x","prompt":["x"]}}'; do
  err=$(printf '%s\n' "$bad" | run 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-chip-brief: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done

# Calls without a prompt: an offer with a title only, starting a proposal.
passes '{"tool_input":{"initiation":"offer","title":"Fix badge"}}' || { echo "error: title-only offer was not passed: $out" >&2; exit 1; }
passes '{"tool_input":{"proposal_id":"p_123"}}' || { echo "error: proposal_id-only call was not passed: $out" >&2; exit 1; }
out=$(echo '{"tool_input":{"initiation":"user_asked","title":"Fix badge"}}' | run)
echo "$out" | grep -qF '"permissionDecision": "deny"' && echo "$out" | grep -qF "needs the filled brief as its prompt" ||
  { echo "error: prompt-less user_asked was not denied: $out" >&2; exit 1; }

# spawn_task (older builds) has no model or effort: only the brief check applies.
passes '{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"x","prompt":"# Brief: Fix badge\n\n**Model:** strong (fable) at max\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"}}' ||
  { echo "error: spawn_task with a valid brief and no model or effort was denied" >&2; exit 1; }
out=$(echo '{"tool_name":"mcp__ccd_session__spawn_task","tool_input":{"title":"x","prompt":"Fix the stale badge."}}' | run)
echo "$out" | grep -qF "repeat the Model line's model and effort in the summary" || { echo "error: spawn_task deny lacks the summary hint: $out" >&2; exit 1; }

# A starter transcript on sonnet, and a call builder: MODEL_LINE then JSON fields.
printf '%s\n' '{"type":"user","message":{"role":"user"}}' '{"type":"assistant","message":{"model":"claude-opus-5-5"}}' \
  '{"type":"assistant","message":{"model":"claude-sonnet-5-5"}}' 'not json' >"$tmp/t.jsonl"
call() {
  python3 -c 'import json,sys
p = "# Brief: Fix badge\n\n**Model:** " + sys.argv[1] + "\n\n## Goal\n\nx\n\n## Proof\n\n- make check\n"
d = {"tool_input": dict(prompt=p, **json.loads(sys.argv[2])), "transcript_path": sys.argv[3]}
print(json.dumps(d))' "$1" "$2" "$tmp/${3:-t.jsonl}"
}
export CLAUDE_EFFORT=medium
denied() { echo "$1" | grep -qF '"permissionDecision": "deny"'; }
reason() { echo "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])'; }

passes "$(call 'standard (opus) at medium (x)' '{"model":"claude-opus-5-5","effort":"medium"}')" ||
  { echo "error: matching model and effort was not passed: $out" >&2; exit 1; }
passes "$(call 'strong (fable) at extra-high (x)' '{"model":"claude-fable-5-1","effort":"xhigh","initiation":"own_initiative"}')" ||
  { echo "error: extra-high brief with effort xhigh was not passed: $out" >&2; exit 1; }
passes "$(call 'strong (fable) at extra high (x)' '{"model":"claude-fable-5-1","effort":"xhigh","initiation":"own_initiative"}')" ||
  { echo "error: 'extra high' brief with effort xhigh was not passed: $out" >&2; exit 1; }
out=$(call 'strong (fable) at extra-high (x)' '{"effort":"high","initiation":"own_initiative"}' | run)
denied "$out" && echo "$out" | grep -qF 'effort \"xhigh\"' || { echo "error: extra-high brief with effort high was not denied: $out" >&2; exit 1; }
for line in 'standard (opus) at <effort> (x)' 'standard (opus) at turbo (x)' 'standard (opus) (x)' 'standard (opus)'; do
  out=$(call "$line" '{"initiation":"own_initiative"}' | run)
  denied "$out" && echo "$out" | grep -qF "low, medium, high, extra-high" ||
    { echo "error: Model line '$line' was not denied with the valid efforts: $out" >&2; exit 1; }
done
out=$(call 'standard (opus), at high (x)' '{"effort":"medium","initiation":"own_initiative"}' | run)
denied "$out" && echo "$out" | grep -qF 'effort \"high\"' || { echo "error: ', at high' was not parsed as high: $out" >&2; exit 1; }
passes "$(call 'standard (opus) at medium.' '{"model":"opus","effort":"medium","initiation":"own_initiative"}')" ||
  { echo "error: 'at medium.' was not passed: $out" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"model":"claude-sonnet-5-5"}' | run)
denied "$out" && echo "$out" | grep -qF 'Pass model \"opus\"' || { echo "error: mismatched model was not denied: $out" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"effort":"high"}' | run)
denied "$out" && echo "$out" | grep -qF 'effort \"medium\"' || { echo "error: mismatched effort was not denied: $out" >&2; exit 1; }

# A brief without context or with a non-fork context must pass model and effort.
out=$(call 'standard (opus) at medium (x)' '{"effort":"medium","initiation":"own_initiative","context":"fresh"}' | run)
denied "$out" && echo "$out" | grep -qF 'missing: model' && echo "$out" | grep -qF 'Pass model \"opus\" and effort \"medium\" from the Model line' ||
  { echo "error: missing model was not denied: $out" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"model":"opus","initiation":"own_initiative","context":"fresh"}' | run)
denied "$out" && echo "$out" | grep -qF 'missing: effort' || { echo "error: missing effort was not denied: $out" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"initiation":"own_initiative"}' | run)
denied "$out" && echo "$out" | grep -qF 'missing: model and effort' || { echo "error: omitted context was not treated as fresh: $out" >&2; exit 1; }
passes "$(call 'standard (opus) at medium (x)' '{"initiation":"own_initiative","context":"fork"}')" ||
  { echo "error: fork without model and effort was denied: $out" >&2; exit 1; }

route=$(python3 -c 'import importlib.util,sys
s = importlib.util.spec_from_file_location("h", sys.argv[1]); m = importlib.util.module_from_spec(s)
s.loader.exec_module(m); print(m.ROUTE)' "$hook")
[ -n "$route" ] || { echo "error: ROUTE constant not found" >&2; exit 1; }
for ctx in fresh fork; do
  out=$(call 'standard (opus) at medium (x)' '{"model":"opus","effort":"medium","initiation":"user_asked","context":"'$ctx'"}' | run)
  denied "$out" && reason "$out" | grep -qF "$route" || { echo "error: user_asked above starter model ($ctx) was not denied with ROUTE: $out" >&2; exit 1; }
done
out=$(call 'fast (sonnet) at high (x)' '{"model":"sonnet","effort":"high","initiation":"user_asked"}' | run)
denied "$out" && echo "$out" | grep -qF "effort high is above the starter's medium" ||
  { echo "error: user_asked above starter effort was not denied: $out" >&2; exit 1; }
passes "$(call 'standard (opus) at high (x)' '{"model":"opus","effort":"high","initiation":"own_initiative"}')" ||
  { echo "error: own_initiative above the cap was not passed: $out" >&2; exit 1; }
passes "$(call 'fast (sonnet) at low (x)' '{"initiation":"user_asked","model":"claude-sonnet-5-5","effort":"low"}')" ||
  { echo "error: user_asked within the cap was not passed: $out" >&2; exit 1; }

out=$(call 'standard (opus) at medium (x)' '{"model":"opus","effort":"medium","initiation":"user_asked"}' missing.jsonl | python3 "$hook" 2>"$tmp/err")
[ -z "$out" ] && grep -q "check-chip-brief: cap unknown" "$tmp/err" ||
  { echo "error: missing transcript did not pass with a cap-unknown note: $out $(cat "$tmp/err")" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"model":"opus","effort":"medium","initiation":"user_asked"}' | CLAUDE_EFFORT= python3 "$hook" 2>"$tmp/err")
[ -z "$out" ] && grep -q "check-chip-brief: cap unknown" "$tmp/err" ||
  { echo "error: unset CLAUDE_EFFORT did not pass with a cap-unknown note: $out $(cat "$tmp/err")" >&2; exit 1; }
printf '%s\n' '{"type":"assistant","message":{"model":"claude-newfamily-1"}}' >"$tmp/u.jsonl"
out=$(call 'standard (opus) at medium (x)' '{"model":"opus","effort":"medium","initiation":"user_asked"}' u.jsonl | python3 "$hook" 2>"$tmp/err")
[ -z "$out" ] && grep -q "unknown model family in 'claude-newfamily-1'; starter cap not checked" "$tmp/err" ||
  { echo "error: unknown starter family did not pass with a cap-unknown note: $out $(cat "$tmp/err")" >&2; exit 1; }
out=$(call 'standard (opus) at medium (x)' '{"initiation":"user_asked","model":"claude-haiku-5-5"}' missing.jsonl | python3 "$hook" 2>/dev/null)
denied "$out" || { echo "error: unknown cap also skipped the model match: $out" >&2; exit 1; }
echo "check-chip-brief: ok"
