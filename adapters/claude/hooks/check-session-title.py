#!/usr/bin/env python3
"""Stop hook: a desktop-app session titles itself (P2a).

Every session carries a title in the format of templates/session-title.md,
`MARKER Type·Size — DESCRIPTION` or `⏱ Routine — DESCRIPTION`. Where the
rename tool is available (the desktop app; CLI and cloud sessions lack it),
a stop whose current title does not match is blocked once and asked to rename
the session. The current title is the latest custom-title line in the
transcript. A session that already called the rename tool, or searched for it
with ToolSearch, passes even if the title still does not match: a declined or
unloadable rename is not retried. A scheduled routine (its first user message
starts with `<scheduled-task`) passes. A repeat stop always ends the turn.
Any error lets the turn end with a note on stderr; a broken check must not
trap a session.
"""
import json
import re
import sys

TOOL = "mcp__ccd_session_mgmt__set_session_title"
TITLE = re.compile(
    "\\A(?:[\U0001F7E2\U0001F535\U0001F7E1\U0001F534]\uFE0F? "
    "(?:Build|Fix|Follow|Chore|Land|Ops|Research|Decide)\u00B7(?:XS|S|M)"
    "|\u23F1\uFE0F? Routine)"
    " \u2014 \\S"
)
EXAMPLE = "\U0001F535 Build\u00B7M \u2014 WP12 checkout contract for guest orders"


def scan(path):
    """The latest custom title (None if none), whether the rename tool is
    available, whether a rename was tried, and whether the session is a
    scheduled routine."""
    title, available, called, routine, first = None, False, False, False, True
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            kind = entry.get("type")
            if kind == "custom-title" and isinstance(entry.get("customTitle"), str):
                title = entry["customTitle"]
            elif kind == "attachment":
                att = entry.get("attachment")
                if (isinstance(att, dict) and att.get("type") == "deferred_tools_delta"
                        and TOOL in (att.get("addedNames") or [])):
                    available = True
            elif kind == "user" and first:
                first = False
                content = (entry.get("message") or {}).get("content")
                if isinstance(content, list):
                    content = next((i.get("text") for i in content
                                    if isinstance(i, dict) and i.get("type") == "text"), "")
                routine = isinstance(content, str) and content.lstrip().startswith("<scheduled-task")
            elif kind == "assistant":
                content = (entry.get("message") or {}).get("content")
                if isinstance(content, list):
                    for item in content:
                        if not (isinstance(item, dict) and item.get("type") == "tool_use"):
                            continue
                        if item.get("name") == TOOL:
                            available = called = True
                        elif item.get("name") == "ToolSearch" and "set_session_title" in str(
                                (item.get("input") or {}).get("query", "")):
                            called = True
    return title, available, called, routine


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return
    title, available, called, routine = scan(data["transcript_path"])
    if routine or not available or called or (title is not None and TITLE.match(title.strip())):
        return
    current = f' The current title is "{title}".' if title else ""
    reason = (
        "This session has no title in the session-title format (P2a); rename it with "
        + TOOL + ' and session_id "self" before you stop.' + current
        + " Format: `MARKER Type\u00B7Size \u2014 DESCRIPTION` (marker \U0001F7E2 \U0001F535 "
        "\U0001F7E1 \U0001F534, size XS, S or M, from templates/session-title.md), for example `"
        + EXAMPLE + "`; if you have not sized the task yet, size it first. Rename only; change "
        "nothing else in this continuation."
    )
    json.dump({"decision": "block", "reason": reason}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-session-title: skipped, {type(e).__name__}: {e}", file=sys.stderr)
