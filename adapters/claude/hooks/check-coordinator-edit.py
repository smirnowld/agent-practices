#!/usr/bin/env python3
"""PreToolUse hook for Edit, Write, MultiEdit and NotebookEdit: the top-level
session is the coordinator and does not edit source (P2b).

Decision order:
1. Any caller, subagents included: deny an edit to the session's own
   transcript, and an edit whose new content names the opt-out variable
   AGENT_PRACTICES_COORDINATOR_EDITS, so no session can lift this check.
2. Inside a subagent (the input carries agent_id) every other edit passes.
3. The user opts out by setting AGENT_PRACTICES_COORDINATOR_EDITS=allow.
4. The coordinator is denied Claude Code settings files and anything under
   $CLAUDE_PLUGIN_ROOT or ~/.claude/plugins/, where this hook lives.
5. Paths outside the git repository of $CLAUDE_PROJECT_DIR (else the input
   cwd), in any of its worktrees, pass.
6. Inside it, docs pass, and so does the one config file that the brief names
   on a "Coordinator edits:" line. The brief is the first user message that is
   not a slash command or its output; the line must start with that label
   (after an optional bullet and bold), and only its first path counts.
   Anything else is denied with a pointer to the implementer.

Any error lets the edit through with a note on stderr; a broken check must not
block every session.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

DOCS = {".md", ".markdown", ".rst", ".txt", ".adoc"}
# Files with a docs extension that are build or dependency inputs, by basename.
SOURCE_NAMES = ("cmakelists.txt", "requirements*.txt", "constraints*.txt")
OPT_OUT = "AGENT_PRACTICES_COORDINATOR_EDITS"
EDITS_LINE = re.compile(r"^\s*(?:[-*]\s*)?(?:\*\*)?coordinator edits?:(?:\*\*)?(.*)$", re.I)
COMMAND_PREFIXES = ("<command-name>", "<command-message>", "<local-command-", "/")
CONFIG = {".json", ".jsonc", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".properties"}
SETTINGS = {"settings.json", "settings.local.json"}
REASON = (
    "The top-level session is the coordinator and does not edit source (P2b). "
    "Hand this change to an implementer with the Agent tool, subagent_type "
    "agent-practices:implementer. Docs pass, and one config file passes when "
    "the brief names it first on a 'Coordinator edits:' line. Shell writes are not "
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


def under(path, directory):
    directory = os.path.realpath(directory)
    return path == directory or path.startswith(directory.rstrip(os.sep) + os.sep)


def new_content(tool_input):
    parts = [tool_input.get("content"), tool_input.get("new_string"),
             tool_input.get("new_source")]
    for edit in tool_input.get("edits") or []:
        if isinstance(edit, dict):
            parts.append(edit.get("new_string"))
    return "\n".join(p for p in parts if isinstance(p, str))


def is_protected(path):
    """Paths that hold the opt-out or this hook: off limits to the coordinator."""
    parts = path.split(os.sep)
    if parts[-1] in SETTINGS and ".claude" in parts[:-1]:
        return True
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root and under(path, plugin_root):
        return True
    return under(path, os.path.expanduser("~/.claude/plugins"))


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
            if not text.strip() or text.lstrip().startswith(COMMAND_PREFIXES):
                continue
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
        m = EDITS_LINE.match(line)
        if not m:
            continue
        tokens = [t for t in re.split(r"[\s,;`'\"()\[\]]+", m.group(1)) if t]
        if not tokens:
            continue
        token = tokens[0].rstrip(".:")
        if token.startswith("./"):
            token = token[2:]
        if token == rel:
            return True
    return False


def main():
    data = json.load(sys.stdin)
    tool_input = data.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path")
    cwd = data.get("cwd")
    if not path or not cwd:
        print("check-coordinator-edit: skipped, no file path or cwd in input", file=sys.stderr)
        return
    path = os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))
    transcript = data.get("transcript_path")
    # Opt-out tampering: denied to every caller, subagents included.
    if transcript and path == os.path.realpath(transcript):
        deny("No session edits its own transcript; it holds the brief that the "
             "coordinator edit check reads. Ask the user to change it.")
        return
    if OPT_OUT in new_content(tool_input):
        deny(f"No session writes {OPT_OUT}; it is the user's opt-out from the "
             "coordinator edit check. Ask the user to set it.")
        return
    if data.get("agent_id"):
        return
    if os.environ.get(OPT_OUT) == "allow":
        return
    if is_protected(path):
        deny("The coordinator does not edit Claude Code settings or plugin files; "
             "they hold the opt-out from the coordinator edit check and the check "
             "itself. Ask the user to change them.")
        return
    # Inside means the same repository as the project, in any of its worktrees.
    anchor = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    common = git(anchor, "rev-parse", "--git-common-dir")
    directory = nearest_dir(path)
    if not common or git(directory, "rev-parse", "--git-common-dir") != common:
        return
    root = git(directory, "rev-parse", "--show-toplevel")
    if not root or not path.startswith(root + os.sep):
        return
    rel = os.path.relpath(path, root)
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1].lower()
    if ext in DOCS and not any(fnmatch.fnmatchcase(name.lower(), p) for p in SOURCE_NAMES):
        return
    is_config = ext in CONFIG or (name.startswith(".") and ext == "")
    if is_config and named_in_brief(rel, transcript):
        return
    deny(REASON)


try:
    main()
except Exception as e:
    print(f"check-coordinator-edit: skipped, {type(e).__name__}: {e}", file=sys.stderr)
