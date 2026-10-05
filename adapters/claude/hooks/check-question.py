#!/usr/bin/env python3
"""PreToolUse hook for AskUserQuestion: what a question depends on must be
visible (session.md, "Ask me, or wait on me").

Thinking is not shown to me; the desktop app shows only a summary of it, which
reads as if the content was sent. Sessions planned commands in thinking, asked
"tell me when you've run them" and I never saw the commands. So a call holding
a short question (under SHORT characters; such questions lean on content
elsewhere, while long ones carry their own) with no chat text after the last tool result (text written before other tool
calls in the turn is an earlier step, not this question's content) is denied
once with a reason; the same call right after that denial passes, so a
self-contained question costs one retry. Any error lets the question through
with a note on stderr; a broken check must not block questions.
"""
import json
import sys

# Results of tools that only send or load something do not start a new step:
# the closeout's question follows its PushNotification.
QUIET = {"PushNotification", "ToolSearch"}
# Of 411 questions in ten days of sessions, 288 had no chat text right before
# them; the 78 under this length held every one I found that I could not answer.
SHORT = 100

REASON = (
    "No chat text came right before this question, and thinking is not shown to the user (P6b). "
    "If this question depends on commands, steps, a card or anything else the user must "
    "see, write it as chat text first, then ask. If the question is self-contained, call "
    "AskUserQuestion again unchanged."
)


def typed(entry, content):
    """A message I typed, not a tool result, compact summary or harness notice
    (the same test as check-attention.py)."""
    if entry.get("isMeta") or entry.get("isCompactSummary"):
        return False
    origin = entry.get("origin")
    if isinstance(origin, dict) and "kind" in origin:  # observed, not documented
        return origin["kind"] == "human"
    if isinstance(content, str):
        return not content.lstrip().startswith("<")
    return any(isinstance(c, dict) and c.get("type") == "text" for c in content or [])


def visible_or_retry(path):
    """Whether chat text was written after the last tool result, or the last
    question since then was denied by this hook."""
    shown, denied, asks, quiet = False, False, set(), set()
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
                results = [c for c in parts if c.get("type") == "tool_result"
                           and c.get("tool_use_id") not in quiet]
                if any(c.get("tool_use_id") in asks and REASON in json.dumps(c.get("content"))
                       for c in results):
                    denied = True
                elif typed(entry, content) or results:
                    shown, denied = False, False
            elif entry.get("type") == "assistant":
                for c in parts:
                    if c.get("type") == "text" and (c.get("text") or "").strip():
                        shown = True
                    elif c.get("type") == "tool_use" and c.get("name") == "AskUserQuestion":
                        asks.add(c.get("id"))
                    elif c.get("type") == "tool_use" and c.get("name") in QUIET:
                        quiet.add(c.get("id"))
    return shown or denied


def main():
    data = json.load(sys.stdin)
    questions = (data.get("tool_input") or {}).get("questions") or []
    if not any(len(str(q.get("question") or "")) < SHORT for q in questions if isinstance(q, dict)):
        return
    if visible_or_retry(data["transcript_path"]):
        return
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": REASON,
    }}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-question: skipped, {type(e).__name__}: {e}", file=sys.stderr)
