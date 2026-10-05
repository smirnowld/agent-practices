#!/usr/bin/env python3
"""PreToolUse hook for AskUserQuestion: what a question depends on must be
visible (session.md, "Ask me, or wait on me").

Thinking is not shown to me; the desktop app shows only a summary of it, which
reads as if the content was sent. Sessions planned commands in thinking, asked
"tell me when you've run them" and I never saw the commands. So a question
with no chat text after the last tool result (text written before other tool
calls in the turn is an earlier step, not this question's content) is denied
until the agent writes some. The retry passes only if text is then found;
there is no length threshold and no blind retry allowance: agents that were offered "call again unchanged if self-contained"
took it almost every time, because they believed the commands in their
thinking had been sent, and long questions pointed at unseen commands too.
Any error lets the question through with a note on stderr; a broken check
must not block questions.
"""
import json
import sys

# Results of tools that only send or load something do not start a new step:
# the closeout's question follows its PushNotification.
QUIET = {"PushNotification", "ToolSearch"}
# This hook's own denial does not start one either. Text written just before a
# question is sometimes not yet in the transcript when the hook runs (3 of 13
# questions with text before them were denied on 2026-10-05); the unchanged retry then finds it and passes. With
# only thinking before the question, the retry is denied again.
DENIED = "PreToolUse:AskUserQuestion hook error"
# Replayed on 486 questions from ten days of sessions (2026-10-05), 350 had no
# chat text right before them; each costs one denial until the agent writes it.
REASON = (
    "The transcript holds no chat text since the last tool result; thinking is never "
    "shown to the user (P6b). If you planned commands, steps or a card in thinking, the "
    "user has NOT seen them: write them in full as chat text now, then ask. If you did "
    "write chat text (outside thinking) right before this call, ask again unchanged: the "
    "check runs again. "
    "If the question stands alone, write one sentence of context first, then ask."
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


def visible(path):
    """Whether chat text was written after the last tool result or typed message."""
    shown, quiet, asks = False, set(), set()
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
                           and c.get("tool_use_id") not in quiet
                           and not (c.get("tool_use_id") in asks
                                    and DENIED in json.dumps(c.get("content")))]
                if typed(entry, content) or results:
                    shown = False
            elif entry.get("type") == "assistant":
                for c in parts:
                    if c.get("type") == "text" and (c.get("text") or "").strip():
                        shown = True
                    elif c.get("type") == "tool_use" and c.get("name") in QUIET:
                        quiet.add(c.get("id"))
                    elif c.get("type") == "tool_use" and c.get("name") == "AskUserQuestion":
                        asks.add(c.get("id"))
    return shown


def main():
    data = json.load(sys.stdin)
    if visible(data["transcript_path"]):
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
