#!/usr/bin/env python3
"""Stop hook: a turn that ends waiting on me must signal it (P6b).

The desktop app marks a session as needing input only while a structured
prompt is open, and prose alone sends no notification. When the final
message carries an acceptance card, a question, a decision or a closeout and
neither PushNotification nor AskUserQuestion was called since I last spoke,
block the stop once and ask for a PushNotification; the questions stay in the
chat message. My last words are my last typed message or my last answer to
AskUserQuestion, so an early notification does not cover a card or closeout
written an hour later. When the turn began with my dismissing a question, it
is waiting on me and the rule does not fire for a question or card.

It also holds the closeout to its template (P15): a chat closeout missing a
required summary field of templates/closeout.md (Status, TL;DR) is blocked,
and so is a turn that merged a PR without rewriting the PR description
afterwards or without any closeout in chat this session.

A turn that says it waits on CI, a run or a merge while no background task is
running is blocked: nothing will wake the session, since the app's monitor
wakes it only on failures, conflicts and review comments. Sentences that
address me ("you", "your") are left alone. Any running background task lets
the turn end, as does a repeat stop. Any error lets the turn end with a note
on stderr; a broken check must not trap a session.
"""
import importlib.util
import json
import os
import re
import sys

SIGNALS = {"AskUserQuestion", "PushNotification"}
# Markers from templates/acceptance-card.md, question.md, closeout.md, docs/plan.md.
ASK = [
    (r"^\s*# Acceptance: \S", "an acceptance card"),
    (r"^\s*# Question: \S", "a question"),
    (r"^\s*(?:\*\*)?Q\d+[.:)]", "a question"),
    (r"^\s*\*\*Decision needed:\*\* \S", "a decision"),
    (r"^\s*\*\*Waiting on (?:me|the maintainer):\*\* (?![\"'`*_]*(?i:nothing|none|n/a)(?![a-z]))\S", "a 'Waiting on me' line"),
]
NOTIFY = [(r"^\s*# Closeout: \S", "a closeout")]
FENCE = re.compile(r"^\s*(```|~~~).*?^\s*\1", re.M | re.S)
# Shell commands split into simple commands; a merge or body edit must be one.
SPLIT = re.compile(r"&&|\|\||[;|\n]")
MERGE = re.compile(r"gh pr merge\b")
NOT_MERGE = re.compile(r"\s(--auto|--disable-auto|--help|-h)\b")
# Heredoc bodies, quoted strings, comments (a `#` starting a word) and echo or
# printf arguments are text, not commands (a PR body, a commit message, a note).
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1([^\n]*)\n.*?^\s*\2\s*$", re.M | re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"|(?<![^\s;&|()])#[^\n]*")
QUOTED_VAR = re.compile(r'"\$(?:\w+|\{\w+\})"')
ECHO = re.compile(r"(^|[\s(`=])(echo|printf)\s(?:[^)`$]|\$(?!\())*")
EDIT = re.compile(r"gh pr edit\b.*\s(--body|--body-file|-b|-F)\b|gh api\b.*\sbody=")
# The tool result of a question I dismissed (observed 2026-10-05, not documented).
DISMISSED = "User dismissed"
# A question a hook denied was never shown to me (observed tool result prefix).
DENIED = "PreToolUse:AskUserQuestion hook error"
# Waiting on CI with nothing running: a waiting phrase and a CI noun in one sentence.
SENTENCE = re.compile(r"[.!?]+(?=\s|$)|\n")
YOU = re.compile(r"\byour?\b", re.I)
WAITING = re.compile(
    r"\bwaiting (?:for|on)\b|\bwait for\b"
    r"|['\u2019]ll (?:wait|report|be notified|be woken|confirm|merge|clean up|check)\b"
    r"|\bwill (?:wait|report|notify|wake)\b|\bnotif(?:y|ies) me\b"
    r"|\bwakes? (?:me|this session)\b"
    r"|\b(?:when|once) (?:it|ci|the run|the checks?|the build|everything) "
    r"(?:finishes|passes|completes|is green|goes green)\b", re.I)
CI_NOUN = re.compile(
    r"\b(?:ci|checks?|runs?|builds?|tests?|lanes?|workflow|pipeline|deploy\w*|release"
    r"|auto-merge|merges?|verifier)\b", re.I)
WAIT_REASON = (
    "You say you are waiting on CI, a run or a merge, but no background task is running, "
    "so nothing will wake this session. The app's Auto-fix monitor wakes it only on CI "
    "failures, merge conflicts and review comments, never on success. Start the wait as a "
    "background task (merge skill step 4: `gh run watch RUN_ID --exit-status` with "
    "run_in_background and a long timeout) and end the turn; or, if what remains is mine, "
    "say so and send PushNotification.")
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


def entries(path):
    """A transcript's entries as (entry, content, its dict parts); bad lines skipped."""
    with open(path) as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if isinstance(entry, dict):
                content = (entry.get("message") or {}).get("content")
                parts = [c for c in content if isinstance(c, dict)] if isinstance(content, list) else []
                yield entry, content, parts


def turn_tools(path):
    """Tool calls since I last spoke (typed, or answered AskUserQuestion), in
    order as (name, input), whether any earlier message held a closeout, and
    whether I dismissed the question that started the turn."""
    names, asks, failed, closeout, dismissed = [], set(), set(), False, False
    for entry, content, parts in entries(path):
        if entry.get("type") == "user":
            failed |= {c.get("tool_use_id") for c in parts
                       if c.get("type") == "tool_result"
                       and (c.get("is_error") or (c.get("tool_use_id") in asks
                                                  and DENIED in json.dumps(c.get("content"))))}
            answers = [c for c in parts if c.get("type") == "tool_result" and c.get("tool_use_id") in asks
                       and DENIED not in json.dumps(c.get("content"))]
            if typed(entry, content) or answers:
                names = []
                dismissed = any(DISMISSED in json.dumps(c.get("content")) for c in answers)
        elif entry.get("type") == "assistant":
            for c in parts:
                if c.get("type") == "text" and re.search(
                        NOTIFY[0][0], FENCE.sub("", c.get("text") or ""), re.M):
                    closeout = True
                if c.get("type") == "tool_use":
                    names.append((c.get("name"), c.get("input") or {}, c.get("id")))
                    if c.get("name") == "AskUserQuestion":
                        asks.add(c.get("id"))
    return [(n, i) for n, i, k in names if k not in failed], closeout, dismissed


def unheredoc(command):
    """The command without its heredoc bodies, however many open on one line."""
    while True:
        bare = HEREDOC.sub(r"\3", command)
        if bare == command:
            return bare
        command = bare


def emptied(match):
    """A quoted string or comment emptied, except a lone quoted variable, which
    is one word a settle may name its PR by."""
    text = match.group()
    return "" if text.startswith("#") else text if QUOTED_VAR.fullmatch(text) else '""'


def steps_of(commands):
    """Simple commands, in order, of a list of shell commands, with heredoc
    bodies, quoted strings, comments and echo or printf arguments emptied."""
    bare = (QUOTED.sub(emptied, unheredoc(c.replace("\\\n", " "))) for c in commands)
    return [ECHO.sub(r"\1\2", seg).strip() for c in bare for seg in SPLIT.split(c)]


def missing_fields(text):
    """Template fields the closeout lacks, from scripts/check-links.py. A
    broken checker skips only this check."""
    try:
        return _missing_fields(text)
    except Exception as e:
        print(f"check-attention: field check skipped, {type(e).__name__}: {e}", file=sys.stderr)
        return []


def _missing_fields(text):
    root = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "..")
    spec = importlib.util.spec_from_file_location(
        "check_links", os.path.join(root, "scripts", "check-links.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return [e.partition("missing: ")[2] for e in mod.missing_fields(text)]


def merge_gaps(calls, closeout):
    """What a turn that merged a PR still owes: the PR description rewritten
    after the merge, and a closeout in chat (P15, closeout skill step 5)."""
    steps = steps_of(str(i.get("command", "")) for n, i in calls if n == "Bash")
    merged = [k for k, c in enumerate(steps) if MERGE.match(c) and not NOT_MERGE.search(c)]
    if not merged:
        return []
    gaps = []
    if not any(EDIT.match(c) for c in steps[merged[-1] + 1:]):
        gaps.append("rewrite the closeout in the PR description with `gh pr edit --body-file` "
                    "(Status, Needs you, Proof with the post-merge run, Blocked on, Cleanup, "
                    "Continuation); a comment does not replace it")
    if not closeout:
        gaps.append("send the closeout summary in chat if the session's work ends here; none "
                    "was sent this session")
    return ["if this turn merged a PR of this session's: " + "; ".join(gaps)] if gaps else []


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active") or data.get("background_tasks"):
        return
    text = FENCE.sub("", data.get("last_assistant_message") or "")
    found = lambda rules: [what for pattern, what in rules if re.search(pattern, text, re.M)]
    ask, notify = found(ASK), found(NOTIFY)
    calls, earlier, dismissed = turn_tools(data["transcript_path"])
    gaps = merge_gaps(calls, earlier or bool(notify))
    missing = missing_fields(text) if notify else []
    if missing:
        gaps.append("add the summary fields the closeout lacks, in plain words "
                    "(the full record goes in the PR): " + ", ".join(missing))
    reasons = ["Closeout incomplete (closeout skill): " + "; ".join(gaps) + "."] if gaps else []
    if ((ask and not dismissed) or notify) and not {n for n, _ in calls} & SIGNALS:
        reasons.append(signal_reason(ask))
    if waits_unwatched(text):
        reasons.append(WAIT_REASON)
    if reasons:
        json.dump({"decision": "block", "reason": " ".join(reasons)}, sys.stdout)


def signal_reason(ask):
    what = ", ".join(ask) if ask else "a closeout"
    return (
        "Your message ends waiting on me or closes the session (" + what + "), but prose "
        "sends no notification and I may have walked away (P6b). Call PushNotification"
        + LOAD.format("PushNotification") + " with one line under 200 characters naming "
        "what waits on me; it is skipped if I am at the session. Do not repeat the "
        "message: the questions stay in the chat message, numbered Q1, Q2."
    )


def waits_unwatched(text):
    """Whether a sentence not addressed to me says it waits on CI, a run or a merge."""
    for sentence in SENTENCE.split(text):
        if YOU.search(sentence):
            continue
        if WAITING.search(sentence) and CI_NOUN.search(sentence):
            return True
    return False


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
