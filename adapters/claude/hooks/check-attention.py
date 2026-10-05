#!/usr/bin/env python3
"""Stop hook: a turn that ends waiting on me must signal it (P6b).

The desktop app marks a session as needing input only while a structured
prompt is open, and prose alone sends no notification. When the final
message carries an acceptance card, a question, a decision or a closeout and
neither AskUserQuestion nor PushNotification was called since I last spoke,
block the stop once and say which to call. My last words are my last typed
message or my last answer to AskUserQuestion, so an early clarifying
question does not cover a card or closeout written an hour later.

It also holds the closeout to its template (P15): a chat closeout missing a
required summary field of templates/closeout.md (TL;DR, Status) is blocked,
and so is a turn that merged a PR without rewriting the PR description afterwards or without any closeout in
chat this session. A PR this session or its subagents created with
`gh pr create` and has not merged, set to auto-merge or closed since is not a
stopping point (P5): the turn is blocked unless a closeout was sent this
session or this turn asked me with AskUserQuestion. When the turn began with
my dismissing a question, it is waiting on me: neither the open-PR rule nor
the ask-signal rule fires, so a dismissal does not push the session into a
closeout or a repeat question. Any error
lets the turn end with a note on stderr; a broken check must not trap a
session.
"""
import glob
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
# Heredoc bodies, quoted strings, comments (a `#` starting a word) and echo or
# printf arguments are text, not commands (a PR body, a commit message, a note).
HEREDOC = re.compile(r"<<-?\s*(['\"]?)(\w+)\1([^\n]*)\n.*?^\s*\2\s*$", re.M | re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"|(?<![^\s;&|()])#[^\n]*")
QUOTED_VAR = re.compile(r'"\$(?:\w+|\{\w+\})"')
ECHO = re.compile(r"(^|[\s(`=])(echo|printf)\s(?:[^)`$]|\$(?!\())*")
# A create or settle may follow `$(`, a backtick, `do` or `VAR=`.
CREATE = re.compile(r"(^|[\s(`=])gh pr create\b")
SETTLE = re.compile(r"(^|[\s(`=])gh pr (merge|close)\b")
# A settle names its PR by number or URL as its first argument that is not a
# flag or a flag's value; gh pr create prints the new PR's URL.
NUMBER = re.compile(r"(?:\S*/pull/)?(\d+)(?:/\S*)?")
VALUED = {"-t", "--subject", "-b", "--body", "-F", "--body-file", "--match-head-commit",
          "-A", "--author-email", "-R", "--repo", "-c", "--comment"}
FOR = re.compile(r"(?:(?:then|do|else)\s+|\()*for (\w+) in (.*)")
ASSIGN = re.compile(r"(?:(?:then|do|else)\s+|\()*(?:export\s+)?(\w+)=")
PULL = re.compile(r"/pull/(\d+)\b")
NOT_ACTION = re.compile(r"\s(--help|-h|--dry-run)\b")
EDIT = re.compile(r"gh pr edit\b.*\s(--body|--body-file|-b|-F)\b|gh api\b.*\sbody=")
# The tool result of a question I dismissed (observed 2026-10-05, not documented).
DISMISSED = "User dismissed"
# A question a hook denied was never shown to me (observed tool result prefix).
DENIED = "PreToolUse:AskUserQuestion hook error"
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


def session_bash(path):
    """The successful Bash calls of the session and its subagents as
    (command, output), in time order. Subagent transcripts sit in a nested
    subagents/ folder (hooks.md, "SubagentStop"); SESSION/subagents/ beside
    SESSION.jsonl, workflow agents one level deeper (observed)."""
    calls, out, failed = [], {}, set()
    subagents = glob.glob(os.path.join(os.path.splitext(path)[0], "subagents", "**", "agent-*.jsonl"),
                          recursive=True)
    for p in [path] + sorted(subagents):
        for entry, _, parts in entries(p):
            for c in parts:
                key = (p, c.get("id") or c.get("tool_use_id"))
                if c.get("type") == "tool_use" and c.get("name") == "Bash":
                    calls.append((str(entry.get("timestamp") or ""), key,
                                  str((c.get("input") or {}).get("command"))))
                elif c.get("type") == "tool_result":
                    body = c.get("content")
                    out[key] = body if isinstance(body, str) else " ".join(
                        str(b.get("text", "")) for b in body or [] if isinstance(b, dict))
                    if c.get("is_error"):
                        failed.add(key)
    calls.sort(key=lambda call: call[0])  # stable: each transcript keeps its order
    return [(cmd, out.get(key, "")) for _, key, cmd in calls if key not in failed]


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


def pr_left_open(commands):
    """Whether a PR created with `gh pr create` has no later merge, auto-merge
    enable or close (P5); commands are (command, output). A PR is known by the
    one URL its create printed, else by the first number a settle names for
    it. A lone create that printed output but no PR URL failed (an error piped
    through `tail` is not a failed call). Disabling auto-merge reopens only a
    PR not merged or closed."""
    prs = []  # [number or None, "open" | "auto" | "done"]
    for command, output in commands:
        steps = [c for c in steps_of([command]) if not NOT_ACTION.search(c)]
        lone = sum(bool(CREATE.search(c)) for c in steps) == 1
        printed = PULL.findall(output) if lone else []
        loops = {}  # loop variable -> PR numbers of a literal `for` list
        for c in steps:
            bound, assigned = FOR.match(c), ASSIGN.match(c)
            if assigned:
                loops.pop(assigned.group(1), None)  # rebound: no longer the loop's list
            if bound:
                words = bound.group(2).split()
                loops[bound.group(1)] = (
                    [int(NUMBER.fullmatch(w).group(1)) for w in words]
                    if words and all(NUMBER.fullmatch(w) for w in words) else None)
            if CREATE.search(c):
                if lone and not printed and output.strip():
                    continue
                n = int(printed[0]) if len(set(printed)) == 1 else None
                if n is None or all(pr[0] != n for pr in prs):
                    prs.append([n, "open"])
            elif SETTLE.search(c):
                for pr in settled(prs, c, loops):
                    if pr[1] == "done":
                        continue
                    if "--disable-auto" in c:
                        pr[1] = "open"
                    else:
                        pr[1] = "auto" if "--auto" in c else "done"
    return any(state == "open" for _, state in prs)


def settled(prs, step, loops=None):
    """The PRs a settle step acts on; none for a PR not created here. One
    naming no PR takes the latest it would change, open before auto-merge;
    one naming it by variable takes each number a literal `for` list in loops
    bound to it, else all it would change."""
    rest = re.sub(r"\$\([^()]*\)|`[^`]*`", "$_", SETTLE.split(step, 1)[-1])  # one word
    words, arg = iter(rest.split()), ""
    for word in words:
        if word in VALUED:
            next(words, None)
        elif not word.startswith("-"):
            arg = word
            break
    arg = arg.strip('"') if QUOTED_VAR.fullmatch(arg) else arg
    named, var = NUMBER.fullmatch(arg), re.fullmatch(r"\$(?:(\w+)|\{(\w+)\})", arg)
    numbers = (loops or {}).get(var and (var.group(1) or var.group(2))) or (
        [int(named.group(1))] if named else [])
    if not numbers:
        wanted = ["auto"] if "--disable-auto" in step else ["open", "auto"]
        if arg.startswith("$"):
            return [pr for pr in prs if pr[1] in wanted]
        for state in wanted:
            match = [pr for pr in prs if pr[1] == state]
            if match:
                return match[-1:]
        return []
    acted = []
    for n in numbers:
        live = [pr for pr in prs if pr[1] != "done"]
        known = [pr for pr in prs if pr[0] == n] or [pr for pr in live if pr[0] is None][-1:]
        if known:
            known[0][0] = n
            acted.append(known[0])
    return acted


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
                    "Continuation); a comment "
                    "does not replace it")
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
        gaps.append("start the closeout with the summary fields it lacks, in plain words "
                    "(the full record goes in the PR): " + ", ".join(missing))
    reasons = ["Closeout incomplete (closeout skill): " + "; ".join(gaps) + "."] if gaps else []
    if (not (earlier or notify or dismissed) and "AskUserQuestion" not in {n for n, _ in calls}
            and pr_left_open(session_bash(data["transcript_path"]))):
        reasons.append(
            "A PR this session created is still open and no closeout was sent; an open PR "
            "is not a stopping point (P5). Finish it: independent review (P4), then merge "
            "with the `merge` skill or hand the merge to me, then write the closeout with "
            "the `closeout` skill and its PushNotification. If I already merged it or "
            "said I will, the closeout records that hand-off. If you are waiting on me, "
            "ask with AskUserQuestion" + LOAD.format("AskUserQuestion") + ".")
    if ((ask and not dismissed) or notify) and not {n for n, _ in calls} & SIGNALS:
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
            + LOAD.format("PushNotification") + " with the status and what, if anything, "
            "waits on me, in one line under 200 characters; it is skipped if I am at the "
            "session. Then ask any closeout questions (acceptance, merge, "
            "follow-ups) with AskUserQuestion. Do not repeat the message."
        )
    return reason


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
