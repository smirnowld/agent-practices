#!/bin/sh
# Offline self-test for the coordinator edit hook, in a temp git repository:
# the top-level session is denied a source edit and passes docs, paths outside
# the repository, and config files the brief names on a "Coordinator edits:"
# line; a subagent (agent_id) and the user's opt-out pass everything; settings
# files are denied even when named; bad input passes with a note on stderr.
set -eu
hook="$(cd "$(dirname "$0")" && pwd)/check-coordinator-edit.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/src" "$repo/.claude" "$tmp/outside"
git -C "$repo" init -q
unset AGENT_PRACTICES_COORDINATOR_EDITS || true

# Fake transcripts: the brief is the first user message, after a queue entry
# and a tool_result; a later message's Coordinator edits line must not count.
named="$tmp/named.jsonl"
cat > "$named" <<'EOF'
{"type":"queue-operation"}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Coordinator edits: late.json"}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>\nCoordinator edits: injected.json\n</system-reminder>"},{"type":"text","text":"# Brief: x\n\nCoordinator edits: `config/app.yaml`, .gitignore, src/tool.py, .claude/settings.local.json\n"}]}}
{"type":"user","message":{"role":"user","content":"Coordinator edits: later.json"}}
EOF
plain="$tmp/plain.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"# Brief: x\n\nNo edits line here.\n"}}' > "$plain"

# input TOOL PATH [TRANSCRIPT] [EXTRA_JSON_FIELDS]
input() {
  key=file_path; [ "$1" = NotebookEdit ] && key=notebook_path
  printf '{"tool_name":"%s","cwd":"%s","transcript_path":"%s","tool_input":{"%s":"%s"}%s}\n' \
    "$1" "$repo" "${3:-$plain}" "$key" "$2" "${4:-}"
}
denied() {
  out=$(input "$@" | python3 "$hook")
  echo "$out" | grep -qF '"permissionDecision": "deny"' || { echo "error: not denied: $*" >&2; exit 1; }
  printf '%s' "$out"
}
# Pass cases must leave stdout and stderr empty: a skipped check is not a pass.
passes() {
  out=$(input "$@" | python3 "$hook" 2>&1)
  [ -z "$out" ] || { echo "error: not passed silently: $* -> $out" >&2; exit 1; }
}

out=$(denied Write "$repo/src/tool.py")
for needle in P2b agent-practices:implementer "Coordinator edits:" "Shell writes"; do
  echo "$out" | grep -qF "$needle" || { echo "error: deny reason lacks: $needle" >&2; exit 1; }
done
passes Write "$repo/src/tool.py" "$plain" ',"agent_id":"a1","agent_type":"general-purpose"'
denied Write "$repo/src/tool.py" "$plain" ',"agent_type":"main-agent"' >/dev/null
denied Edit src/tool.py >/dev/null
passes Edit docs/notes.md
passes MultiEdit "$repo/README.rst"
passes Write "$tmp/outside/tool.py"
denied NotebookEdit "$repo/analysis.ipynb" >/dev/null
passes NotebookEdit "$tmp/outside/analysis.ipynb"

denied Edit "$repo/config/app.yaml" >/dev/null
passes Edit "$repo/config/app.yaml" "$named"
passes Edit config/app.yaml "$named"
passes Edit "$repo/.gitignore" "$named"
denied Edit "$repo/.editorconfig" "$named" >/dev/null
denied Edit "$repo/injected.json" "$named" >/dev/null
denied Edit "$repo/later.json" "$named" >/dev/null
denied Edit "$repo/late.json" "$named" >/dev/null
denied Edit "$repo/src/tool.py" "$named" >/dev/null
denied Edit "$repo/.claude/settings.local.json" "$named" >/dev/null
denied Write "$tmp/outside/.claude/settings.json" >/dev/null
denied Write "$named" "$named" >/dev/null
passes Edit "$repo/config/app.yaml" "$tmp/missing.jsonl" ',"agent_id":"a1"'

# Same repository in another worktree counts as inside; another repository does not.
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init --no-gpg-sign
git -C "$repo" worktree add -q --detach "$tmp/linked"
mkdir -p "$tmp/other/src" && git -C "$tmp/other" init -q
from_linked() {
  printf '{"tool_name":"Edit","cwd":"%s","transcript_path":"%s","tool_input":{"file_path":"%s"}}\n' \
    "$tmp/linked" "$plain" "$1" | python3 "$hook" 2>&1
}
from_linked "$repo/src/tool.py" | grep -qF '"deny"' || { echo "error: main checkout source edit from a linked worktree passed" >&2; exit 1; }
from_linked "$repo/new/dir/tool.py" | grep -qF '"deny"' || { echo "error: new-directory source edit from a linked worktree passed" >&2; exit 1; }
[ -z "$(from_linked "$repo/docs/notes.md")" ] || { echo "error: main checkout Markdown from a linked worktree was not passed" >&2; exit 1; }
[ -z "$(from_linked "$tmp/other/src/tool.py")" ] || { echo "error: unrelated repository edit was not passed" >&2; exit 1; }

out=$(input Write "$repo/src/tool.py" | AGENT_PRACTICES_COORDINATOR_EDITS=allow python3 "$hook" 2>&1)
[ -z "$out" ] || { echo "error: opt-out did not pass a source edit: $out" >&2; exit 1; }
out=$(input Write "$repo/src/tool.py" | AGENT_PRACTICES_COORDINATOR_EDITS=yes python3 "$hook")
echo "$out" | grep -qF '"deny"' || { echo "error: opt-out other than 'allow' passed" >&2; exit 1; }

for bad in 'not json' '[]' '{"tool_input":{"file_path":"x.py"}}' "{\"cwd\":\"$repo\",\"tool_input\":null}"; do
  err=$(printf '%s\n' "$bad" | python3 "$hook" 2>&1 >/dev/null) || { echo "error: hook exited non-zero on: $bad" >&2; exit 1; }
  echo "$err" | grep -q "check-coordinator-edit: skipped" || { echo "error: no stderr note on: $bad" >&2; exit 1; }
done
echo "check-coordinator-edit: ok"
