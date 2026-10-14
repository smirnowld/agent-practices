#!/usr/bin/env python3
"""Stop hook: a desktop-app session titles itself (P2a).

Every session carries a title in the format of templates/session-title.md,
`MARKER Type·Size — DESCRIPTION` or `⏱ Routine — DESCRIPTION`. Where the
rename tool is available (the desktop app; CLI and cloud sessions lack it),
a stop whose current title does not match is blocked once and asked to rename
the session. The current title is the latest custom-title line in the
transcript. A session that already called the rename tool passes, even if the
title still does not match: a declined rename is not retried. A repeat stop
always ends the turn. Any error lets the turn end with a note on stderr; a
broken check must not trap a session.
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
    available, and whether it was called."""
    title, available, called = None, False, False
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
            elif kind == "assistant":
                content = (entry.get("message") or {}).get("content")
                if isinstance(content, list):
                    for item in content:
                        if (isinstance(item, dict) and item.get("type") == "tool_use"
                                and item.get("name") == TOOL):
                            available = called = True
    return title, available, called


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return
    title, available, called = scan(data["transcript_path"])
    if not available or called or (title is not None and TITLE.match(title.strip())):
        return
    current = f' The current title is "{title}".' if title else ""
    reason = (
        "This session has no title in the session-title format (P2a); rename it with "
        + TOOL + ' and session_id "self" before you stop.' + current
        + " Format: `MARKER Type\u00B7Size \u2014 DESCRIPTION` (marker \U0001F7E2 \U0001F535 "
        "\U0001F7E1 \U0001F534, size XS, S or M, from templates/session-title.md), for example `"
        + EXAMPLE + "`; if you have not sized the task yet, size it first."
    )
    json.dump({"decision": "block", "reason": reason}, sys.stdout)


try:
    main()
except Exception as e:
    print(f"check-session-title: skipped, {type(e).__name__}: {e}", file=sys.stderr)
