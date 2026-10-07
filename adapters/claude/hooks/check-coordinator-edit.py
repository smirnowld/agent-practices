#!/usr/bin/env python3
"""PreToolUse hook for Edit, Write, MultiEdit and NotebookEdit: the top-level
session is the coordinator and does not edit source (P2b).

Inside a subagent (the input carries agent_id) every edit passes. In the
top-level session an edit inside the git repository that contains cwd, in any
of its worktrees, passes only for docs, or for a config file that the session's
first user message (the brief) names on a "Coordinator edits:" line; anything else is denied with a
pointer to the implementer. Paths outside the repository pass, except Claude
Code settings files and the session's own transcript, which stay out of the
coordinator's reach so it cannot lift this check. The user opts out by setting
AGENT_PRACTICES_COORDINATOR_EDITS=allow. Any error lets the edit through with
a note on stderr; a broken check must not block every session.
"""
import json
import os
import re
import subprocess
import sys

DOCS = {".md", ".mdx", ".markdown", ".rst", ".txt", ".adoc"}
CONFIG = {".json", ".jsonc", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".properties"}
SETTINGS = {"settings.json", "settings.local.json"}
REASON = (
    "The top-level session is the coordinator and does not edit source (P2b). "
    "Hand this change to an implementer with the Agent tool, subagent_type "
    "agent-practices:implementer. Docs pass, and a config file passes only when "
    "the brief lists it on a 'Coordinator edits:' line. Shell writes are not "
    "covered by this hook, but the rule still applies to them."
)


def deny(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def git(directory, *args):
    try:
        out = subprocess.run(["git", "-C", directory, *args],
                             capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    value = out.stdout.strip()
    return os.path.realpath(os.path.join(directory, value)) if out.returncode == 0 and value else None


def nearest_dir(path):
    directory = os.path.dirname(path)
    while not os.path.isdir(directory) and os.path.dirname(directory) != directory:
        directory = os.path.dirname(directory)
    return directory


def is_protected(path, transcript):
    parts = path.split(os.sep)
    if parts[-1] in SETTINGS and ".claude" in parts[:-1]:
        return True
    return bool(transcript) and path == os.path.realpath(transcript)


def brief_text(transcript):
    """The first user message the user typed, without injected reminders."""
    with open(transcript) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("type") != "user" or entry.get("isMeta"):
                continue
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
                    continue
                text = "\n".join(b.get("text", "") for b in content
                                 if isinstance(b, dict) and b.get("type") == "text")
            else:
                continue
            text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S)
            if text.strip():
                return text
    return ""


def named_in_brief(rel, transcript):
    if not transcript:
        return False
    try:
        text = brief_text(transcript)
    except OSError:
        return False
    for line in text.splitlines():
        m = re.search(r"coordinator edits?:(.*)", line, re.I)
        if not m:
            continue
        for token in re.split(r"[\s,;`'\"()\[\]]+", m.group(1)):
            token = token.rstrip(".:")
            if token.startswith("./"):
                token = token[2:]
            if token and token == rel:
                return True
    return False


def main():
    data = json.load(sys.stdin)
    if data.get("agent_id"):
        return
    if os.environ.get("AGENT_PRACTICES_COORDINATOR_EDITS") == "allow":
        return
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    cwd = data.get("cwd")
    if not path or not cwd:
        print("check-coordinator-edit: skipped, no file path or cwd in input", file=sys.stderr)
        return
    path = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    transcript = data.get("transcript_path")
    if is_protected(path, transcript):
        deny("The coordinator does not edit Claude Code settings or its own transcript; "
             "they hold the opt-out from the coordinator edit check. Ask the user to "
             "change them.")
        return
    # Inside means the same repository as cwd, in any of its worktrees.
    common = git(cwd, "rev-parse", "--git-common-dir")
    directory = nearest_dir(path)
    if not common or git(directory, "rev-parse", "--git-common-dir") != common:
        return
    root = git(directory, "rev-parse", "--show-toplevel")
    if not root or not path.startswith(root + os.sep):
        return
    rel = os.path.relpath(path, root)
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    if ext in DOCS:
        return
    is_config = ext in CONFIG or (name.startswith(".") and ext == "")
    if is_config and named_in_brief(rel, transcript):
        return
    deny(REASON)


try:
    main()
except Exception as e:
    print(f"check-coordinator-edit: skipped, {type(e).__name__}: {e}", file=sys.stderr)
