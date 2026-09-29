#!/usr/bin/env python3
"""Stop hook: a turn that ends waiting on me must signal it (P6b).

The desktop app marks a session as needing input only while a structured
prompt is open, and prose alone sends no notification. When the final
message carries an acceptance card, a question, a decision or a closeout and
neither AskUserQuestion nor PushNotification was called since I last spoke,
block the stop once and say which to call. My last words are my last typed
message or my last answer to AskUserQuestion, so an early clarifying
question does not cover a card or closeout written an hour later. Any error
lets the turn end with a note on stderr; a broken check must not trap a
session.
"""
import json
import re
import sys

SIGNALS = {"AskUserQuestion", "PushNotification"}
# Markers from templates/acceptance-card.md, question.md, closeout.md, docs/plan.md.
ASK = [
    (r"^\s*# Acceptance: \S", "an acceptance card"),
    (r"^\s*# Question: \S", "a question"),
    (r"^\s*\*\*Decision needed:\*\* \S", "a decision"),
    (r"^\s*\*\*Waiting on me:\*\* (?![\"'`*_]*(?i:nothing|none|n/a)(?![a-z]))\S", "a 'Waiting on me' line"),
]
NOTIFY = [(r"^\s*# Closeout: \S", "a closeout")]
FENCE = re.compile(r"^\s*(```|~~~).*?^\s*\1", re.M | re.S)
LOAD = " (if it is not in your tools, load it with ToolSearch 'select:{0}' first)"


def typed(entry, content):
    """A message I typed, not a tool result, compact summary or harness notice."""
    if entry.get("isMeta") or entry.get("isCompactSummary"):
        return False
    origin = entry.get("origin")
    if isinstance(origin, dict) and "kind" in origin:  # observed, not documented
        return origin["kind"] == "human"
    if isinstance(content, str):
        return not content.lstrip().startswith("<")
    return any(isinstance(c, dict) and c.get("type") == "text" for c in content or [])


def turn_tools(path):
    """Tool names called since I last spoke: typed, or answered AskUserQuestion."""
    names, asks = set(), set()
    with open(path) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            content = (entry.get("message") or {}).get("content")
            parts = [c for c in content if isinstance(c, dict)] if isinstance(content, list) else []
            if entry.get("type") == "user":
                if typed(entry, content) or any(
                        c.get("type") == "tool_result" and c.get("tool_use_id") in asks for c in parts):
                    names = set()
            elif entry.get("type") == "assistant":
                for c in parts:
                    if c.get("type") == "tool_use":
                        names.add(c.get("name"))
                        if c.get("name") == "AskUserQuestion":
                            asks.add(c.get("id"))
    return names


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active") or data.get("background_tasks"):
        return
    text = FENCE.sub("", data.get("last_assistant_message") or "")
    found = lambda rules: [what for pattern, what in rules if re.search(pattern, text, re.M)]
    ask, notify = found(ASK), found(NOTIFY)
    if not (ask or notify):
        return
    if turn_tools(data["transcript_path"]) & SIGNALS:
        return
    if ask:
        reason = (
            "Your message ends waiting on me (" + ", ".join(ask) + "), but prose does not "
            "mark the session as needing input (P6b). Call AskUserQuestion" + LOAD.format("AskUserQuestion")
            + ": an acceptance as accept / change / reject, a question with its options, "
            "proposed first. Do not repeat the message."
        )
    else:
        reason = (
            "You wrote a closeout; I may have walked away (P6b). Call PushNotification"
            + LOAD.format("PushNotification") + " with the outcome and what, if anything, "
            "waits on me, in one line under 200 characters; it is skipped if I am at the "
            "session. If the next step is my decision, call AskUserQuestion instead. Then "
            "end the turn without repeating the message."
        )
    json.dump({"decision": "block", "reason": reason}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
