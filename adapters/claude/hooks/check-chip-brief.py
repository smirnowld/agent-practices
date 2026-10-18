#!/usr/bin/env python3
"""PreToolUse hook for start_session (spawn_task in older app builds): a
session's prompt must be a brief (P2c).

A call with no prompt passes: starting an existing proposal sends only
proposal_id, and an offer sends only a title. Otherwise it blocks a prompt
that lacks the brief's heading, Model line, Goal or Proof, or whose Model
line lacks a tier followed by its model from tiers.json, and hands back
templates/brief.md so the retry takes one call. Any error lets
the chip through with a note on stderr; a broken check must not block chips.
"""
import json
import os
import re
import sys

REQUIRED = [
    (r"\A\s*# Brief: \S", "a first line '# Brief: TITLE'"),
    (r"^\s*\*\*Model:\*\* \S", "a '**Model:**' line"),
    (r"^\s*## Goal\s*$", "a '## Goal' section"),
    (r"^\s*## Proof\s*$", "a '## Proof' section"),
]


def main():
    prompt = json.load(sys.stdin)["tool_input"].get("prompt")
    if prompt is None or prompt == "":
        return
    missing = [what for pattern, what in REQUIRED if not re.search(pattern, prompt, re.M)]
    root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.join(os.path.dirname(__file__), "../../..")
    with open(os.path.join(root, "adapters/claude/tiers.json")) as f:
        models = json.load(f)["models"]
    pairs_re = "|".join(re.escape(t) + r"\s*\(\s*" + re.escape(m) for t, m in models.items())
    line = re.search(r"^\s*\*\*Model:\*\* .*$", prompt, re.M)
    if line and not re.search(r"\b(" + pairs_re + r")\b", line.group(0), re.I):
        pairs = ", ".join(f"{t} ({m})" for t, m in models.items())
        missing.append("the model in the Model line, as TIER (MODEL): " + pairs)
    if not missing:
        return
    with open(os.path.join(root, "templates/brief.md")) as f:
        template = f.read()
    reason = (
        "A chip's prompt is a brief (P2c). Missing: " + "; ".join(missing) + ". "
        "Refill the prompt from this template, keep what you already wrote, "
        "and set start_session's model and effort from the Model line where they "
        "are at or below this session's (spawn_task, which has neither, repeats "
        "them in its summary).\n\n" + template
    )
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-chip-brief: skipped, {type(e).__name__}: {e}", file=sys.stderr)
