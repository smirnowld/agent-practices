#!/usr/bin/env python3
"""Stop hook: a turn that ends waiting on me must signal it (P6b).

The desktop app marks a session as needing input only while a structured
prompt is open, and prose alone sends no notification. When the final
message carries an acceptance card, a question, a decision or a closeout and
neither AskUserQuestion nor PushNotification was called since I last spoke,
block the stop once and say which to call. My last words are my last typed
message or my last answer to AskUserQuestion, so an early clarifying
question does not cover a card or closeout written an hour later.

It also holds the closeout to its template (P15): a closeout missing a field
of templates/closeout.md is blocked, and so is a turn that merged a PR
without rewriting the PR description afterwards or without any closeout in
chat this session. A PR this session created with `gh pr create` and has not
merged, set to auto-merge or closed since is not a stopping point (P5): the
turn is blocked unless a closeout was sent this session or this turn asked me
with AskUserQuestion. Any error
lets the turn end with a note on stderr; a broken check must not trap a
session.
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
    (r"^\s*\*\*Decision needed:\*\* \S", "a decision"),
    (r"^\s*\*\*Waiting on me:\*\* (?![\"'`*_]*(?i:nothing|none|n/a)(?![a-z]))\S", "a 'Waiting on me' line"),
]
NOTIFY = [(r"^\s*# Closeout: \S", "a closeout")]
FENCE = re.compile(r"^\s*(```|~~~).*?^\s*\1", re.M | re.S)
# Shell commands split into simple commands; a merge or body edit must be one.
SPLIT = re.compile(r"&&|\|\||[;|\n]")
MERGE = re.compile(r"gh pr merge\b")
NOT_MERGE = re.compile(r"\s(--auto|--disable-auto|--help|-h)\b")
# Heredoc bodies and quoted strings are text, not commands (a PR body, a commit message).
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1.*?^\s*\2\s*$", re.M | re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
# A create or settle may follow `$(`, a backtick, `do` or `VAR=`.
CREATE = re.compile(r"(^|[\s(`=])gh pr create\b")
SETTLE = re.compile(r"(^|[\s(`=])gh pr (merge|close)\b")
NOT_ACTION = re.compile(r"\s(--help|-h|--dry-run)\b")
EDIT = re.compile(r"gh pr edit\b.*\s(--body|--body-file|-b|-F)\b|gh api\b.*\sbody=")
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
    """Tool calls since I last spoke (typed, or answered AskUserQuestion), in
    order as (name, input), whether any earlier message held a closeout, and
    the session's Bash commands in order."""
    names, asks, failed, closeout, session = [], set(), set(), False, []
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
                failed |= {c.get("tool_use_id") for c in parts
                           if c.get("type") == "tool_result" and c.get("is_error")}
                if typed(entry, content) or any(
                        c.get("type") == "tool_result" and c.get("tool_use_id") in asks for c in parts):
                    names = []
            elif entry.get("type") == "assistant":
                for c in parts:
                    if c.get("type") == "text" and re.search(
                            NOTIFY[0][0], FENCE.sub("", c.get("text") or ""), re.M):
                        closeout = True
                    if c.get("type") == "tool_use":
                        names.append((c.get("name"), c.get("input") or {}, c.get("id")))
                        if c.get("name") == "Bash":
                            session.append(((c.get("input") or {}).get("command"), c.get("id")))
                        if c.get("name") == "AskUserQuestion":
                            asks.add(c.get("id"))
    return ([(n, i) for n, i, k in names if k not in failed], closeout,
            [str(c) for c, k in session if k not in failed])


def steps_of(commands):
    """Simple commands, in order, of a list of shell commands, with heredoc
    bodies and quoted strings emptied."""
    bare = (QUOTED.sub('""', HEREDOC.sub("", c.replace("\\\n", " "))) for c in commands)
    return [seg.strip() for c in bare for seg in SPLIT.split(c)]


def pr_left_open(commands):
    """Whether the last successful `gh pr create` has no later merge, auto-merge
    enable or close (P5); disabling auto-merge opens it again. Not per PR
    number: any later settle counts."""
    created = open_ = False
    for c in steps_of(commands):
        if NOT_ACTION.search(c):
            continue
        if CREATE.search(c):
            created = open_ = True
        elif SETTLE.search(c):
            open_ = created and "--disable-auto" in c
    return open_


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
                    "(Outcome, Proof with the post-merge run, Blocked on, Cleanup); a comment "
                    "does not replace it")
    if not closeout:
        gaps.append("send the full closeout in chat if the session's work ends here; none "
                    "was sent this session")
    return ["if this turn merged a PR of this session's: " + "; ".join(gaps)] if gaps else []


def main():
    data = json.load(sys.stdin)
    if data.get("stop_hook_active") or data.get("background_tasks"):
        return
    text = FENCE.sub("", data.get("last_assistant_message") or "")
    found = lambda rules: [what for pattern, what in rules if re.search(pattern, text, re.M)]
    ask, notify = found(ASK), found(NOTIFY)
    calls, earlier, commands = turn_tools(data["transcript_path"])
    gaps = merge_gaps(calls, earlier or bool(notify))
    missing = missing_fields(text) if notify else []
    if missing:
        gaps.append("add the closeout fields it lacks, with their labels (\"none\" where "
                    "nothing applies): " + ", ".join(missing))
    reasons = ["Closeout incomplete (closeout skill): " + "; ".join(gaps) + "."] if gaps else []
    if (pr_left_open(commands) and not (earlier or notify)
            and "AskUserQuestion" not in {n for n, _ in calls}):
        reasons.append(
            "A PR this session created is still open and no closeout was sent; an open PR "
            "is not a stopping point (P5). Finish it: independent review (P4), then merge "
            "with the `merge` skill or hand the merge to me, then write the closeout with "
            "the `closeout` skill and its PushNotification. If I already merged it or "
            "said I will, the closeout records that hand-off. If you are waiting on me, "
            "ask with AskUserQuestion" + LOAD.format("AskUserQuestion") + ".")
    if (ask or notify) and not {n for n, _ in calls} & SIGNALS:
        reasons.append(signal_reason(ask))
    if reasons:
        json.dump({"decision": "block", "reason": " ".join(reasons)}, sys.stdout)


def signal_reason(ask):
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
            "session. Then ask any closeout questions (acceptance, merge, "
            "follow-ups) with AskUserQuestion. Do not repeat the message."
        )
    return reason


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
