#!/usr/bin/env python3
"""PreToolUse hook for spawn_task: a chip's prompt must be a brief (P2c).

Blocks a prompt that lacks the brief's heading, Model line, Goal or Proof,
and hands back templates/brief.md so the retry takes one call. Any error lets
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
    prompt = json.load(sys.stdin)["tool_input"].get("prompt") or ""
    missing = [what for pattern, what in REQUIRED if not re.search(pattern, prompt, re.M)]
    if not missing:
        return
    root = os.environ.get("CLAUDE_PLUGIN_ROOT") or os.path.join(os.path.dirname(__file__), "../../..")
    with open(os.path.join(root, "templates/brief.md")) as f:
        template = f.read()
    reason = (
        "A chip's prompt is a brief (P2c). Missing: " + "; ".join(missing) + ". "
        "Refill the prompt from this template, keep what you already wrote, "
        "and repeat the Model line's model and effort in the summary (tldr).\n\n" + template
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
