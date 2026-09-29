#!/usr/bin/env python3
"""Stop hook: a turn that ends waiting on me must signal it (P6b).

The desktop app marks a session as needing input only while a structured
prompt is open, and prose alone sends no notification. When the final
message carries an acceptance card, a question, a decision or a closeout and
this turn called neither AskUserQuestion nor PushNotification, block the stop
once and say which to call. Any error lets the turn end with a note on
stderr; a broken check must not trap a session.
"""
import json
import re
import sys

SIGNALS = {"AskUserQuestion", "PushNotification"}
# Markers from templates/acceptance-card.md, question.md, plan.md, closeout.md.
ASK = [
    (r"^\s*# Acceptance: \S", "an acceptance card"),
    (r"^\s*# Question: \S", "a question"),
    (r"^\s*\*\*Decision needed:\*\* \S", "a decision"),
    (r"^\s*\*\*Waiting on me:\*\* (?![\"'`]?(?i:nothing))\S", "a 'Waiting on me' line"),
]
NOTIFY = [(r"^\s*# Closeout: \S", "a closeout")]


def turn_tools(path):
    """Tool names called since the last message I typed."""
    names = set()
    with open(path) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            content = (entry.get("message") or {}).get("content")
            if entry.get("type") == "user" and not entry.get("isMeta"):
                if isinstance(content, str) or any(
                        isinstance(c, dict) and c.get("type") == "text" for c in content or []):
                    names = set()
            elif entry.get("type") == "assistant" and isinstance(content, list):
                names |= {c.get("name") for c in content
                          if isinstance(c, dict) and c.get("type") == "tool_use"}
    return names


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active") or data.get("background_tasks"):
        return
    text = data.get("last_assistant_message") or ""
    found = lambda rules: [what for pattern, what in rules if re.search(pattern, text, re.M)]
    ask, notify = found(ASK), found(NOTIFY)
    if not (ask or notify):
        return
    if turn_tools(data["transcript_path"]) & SIGNALS:
        return
    if ask:
        reason = (
            "Your message ends waiting on me (" + ", ".join(ask) + "), but prose does not "
            "mark the session as needing input (P6b). Call AskUserQuestion: an acceptance "
            "as accept / change / reject, a question with its options, proposed first. "
            "Do not repeat the message."
        )
    else:
        reason = (
            "You wrote a closeout; I may have walked away (P6b). Call PushNotification "
            "with the outcome and what, if anything, waits on me, in one line under 200 "
            "characters. It is skipped if I am at the session. Then end the turn "
            "without repeating the message."
        )
    json.dump({"decision": "block", "reason": reason}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
