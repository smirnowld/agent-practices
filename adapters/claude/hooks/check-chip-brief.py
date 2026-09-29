#!/usr/bin/env python3
"""PreToolUse hook for spawn_task: a chip's prompt must be a brief (P2c).

Blocks a prompt that lacks the brief's heading, Model line, Goal or Proof,
and hands back templates/brief.md so the retry takes one call.
"""
import json
import os
import re
import sys

REQUIRED = [
    (r"\A\s*# Brief: \S", "a first line '# Brief: TITLE'"),
    (r"^\*\*Model:\*\* \S", "a '**Model:**' line"),
    (r"^## Goal\s*$", "a '## Goal' section"),
    (r"^## Proof\s*$", "a '## Proof' section"),
]

prompt = json.load(sys.stdin).get("tool_input", {}).get("prompt") or ""
missing = [what for pattern, what in REQUIRED if not re.search(pattern, prompt, re.M)]
if not missing:
    sys.exit(0)

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
