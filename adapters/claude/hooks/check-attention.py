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
and so is one written without the closeout skill loaded this session. A turn
that merged a PR is blocked without the PR description rewritten afterwards,
a closeout in chat this session and the closeout skill. A merge is a direct
`gh pr merge`, or, once this session turned auto-merge on, its landing: a
background `wait-for pr-ci|pr-merged` that exits 0, a tool result holding
wait-for's final line for a merge or a pass, or `"state":"MERGED"` from a
`gh pr view`, each for the PR auto-merge was turned on for.

A turn that says it waits on CI, a run or a merge while no background task is
running is blocked: nothing will wake the session, since the app's monitor
wakes it only on failures, conflicts and review comments. A sentence whose
wait is on me ("once you accept") is left alone. Any running background task lets
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
AUTO = re.compile(r"\s--auto\b")
DISABLE = re.compile(r"\s--disable-auto\b")
# The PR a gh pr command names, by number or URL; none means the branch's own.
PR_ARG = re.compile(r"\s(?:\S*/pull/)?(\d+)\b")
# A background wait whose exit 0 means the PR merged or its auto-merge can land
# (bin/wait-for); a wrapper after it (`; echo $?`) hides the exit code.
WAIT_FOR = re.compile(r"(?:\S*/)?wait-for\b.*\s(?:pr-ci|pr-merged)\s+(\d+)(?:\s+\d?>&?\s*\S+)*\s*$")
EXITED_0 = re.compile(r"<status>completed</status>.*\(exit code 0\)", re.S)
NOTICE_ID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
# wait-for's final line for a merged PR or passed CI; gh's JSON for a merged PR
# counts only as the result of a `gh pr view` of that PR.
LANDED = re.compile(r"^(?:merged: PR|passed: CI on PR) (\d+) at \S", re.M)
VIEW = re.compile(r"gh pr view\b")
MERGED_STATE = re.compile(r'"state":\s*"MERGED"')
CLOSEOUT_SKILL = re.compile(r"^(?:[\w-]+:)?closeout$")
CLOSEOUT_COMMAND = re.compile(r"<command-name>/(?:[\w-]+:)?closeout</command-name>")
EDIT = re.compile(r"gh pr edit\b.*\s(--body|--body-file|-b|-F)\b|gh api\b.*\sbody=")
# The tool result of a question I dismissed (observed 2026-10-05, not documented).
DISMISSED = "User dismissed"
# A question a hook denied was never shown to me (observed tool result prefix).
DENIED = "PreToolUse:AskUserQuestion hook error"
# Waiting on CI with nothing running: a waiting phrase and a CI noun in one sentence.
SENTENCE = re.compile(r"[.!?]+(?=\s|$)|\n")
# A wait that is on me ("once you accept", "waiting for your answer") is not on CI.
ON_ME = re.compile(r"\b(?:waiting (?:for|on)|wait for|once|when|after|until) (?:you|your)\b", re.I)
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
    "say so and send PushNotification. If you are not waiting on anything, end the turn "
    "again as is.")
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


def result_text(content):
    """A tool result's or notice's text, however its content is shaped."""
    if isinstance(content, str):
        return content
    return "\n".join(c.get("text") or "" for c in content or [] if isinstance(c, dict))


def turn_tools(path):
    """Tool calls since I last spoke (typed, or answered AskUserQuestion), in
    order as (name, input); whether any earlier message held a closeout;
    whether the closeout skill was loaded this session; the index into those
    calls at which an auto-merge this session turned on landed this turn
    (None if none did); and whether I dismissed the question that started
    the turn."""
    names, asks, failed, closeout, dismissed = [], set(), set(), False, False
    skills, auto_ids, disable_ids, waits, views = set(), {}, {}, {}, {}
    auto, landed, command = set(), None, False

    def lands(pr):
        """Whether PR is one this session's auto-merge is on for; it lands once."""
        nonlocal auto, landed
        hit = auto if pr is None else auto & {pr, None}
        if hit:
            auto, landed = auto - hit, len(names) if landed is None else landed
    for entry, content, parts in entries(path):
        if entry.get("type") == "user":
            results = [c for c in parts if c.get("type") == "tool_result"]
            failed |= {c.get("tool_use_id") for c in results
                       if c.get("is_error") or (c.get("tool_use_id") in asks
                                                and DENIED in json.dumps(c.get("content")))}
            answers = [c for c in results if c.get("tool_use_id") in asks
                       and DENIED not in json.dumps(c.get("content"))]
            if typed(entry, content) or answers:
                names, landed = [], None
                dismissed = any(DISMISSED in json.dumps(c.get("content")) for c in answers)
            text = result_text(content)
            command |= bool(CLOSEOUT_COMMAND.search(text))
            for c in results:
                k = c.get("tool_use_id")
                if k in failed:
                    continue
                if k in auto_ids:
                    auto.add(auto_ids[k])
                if k in disable_ids:
                    auto -= {disable_ids[k]} if disable_ids[k] else set(auto)
                out = result_text(c.get("content"))
                for m in LANDED.finditer(out):
                    lands(m.group(1))
                if k in views and MERGED_STATE.search(out):
                    lands(views[k])
            notice = NOTICE_ID.search(text)
            if notice and notice.group(1) in waits and EXITED_0.search(text):
                lands(waits[notice.group(1)])
        elif entry.get("type") == "assistant":
            for c in parts:
                if c.get("type") == "text" and re.search(
                        NOTIFY[0][0], FENCE.sub("", c.get("text") or ""), re.M):
                    closeout = True
                if c.get("type") != "tool_use":
                    continue
                name, args, k = c.get("name"), c.get("input") or {}, c.get("id")
                names.append((name, args, k))
                if name == "AskUserQuestion":
                    asks.add(k)
                elif name == "Skill" and CLOSEOUT_SKILL.match(str(args.get("skill", ""))):
                    skills.add(k)
                elif name == "Bash":
                    for step in steps_of([str(args.get("command", ""))]):
                        pr = PR_ARG.search(step)
                        pr = pr and pr.group(1)
                        if MERGE.match(step) and AUTO.search(step):
                            auto_ids[k] = pr
                        elif MERGE.match(step) and DISABLE.search(step):
                            disable_ids[k] = pr
                        elif VIEW.match(step):
                            views[k] = pr
                        waits.pop(k, None)
                        wait = WAIT_FOR.match(step)
                        if wait and args.get("run_in_background"):
                            waits[k] = wait.group(1)
    kept = [(n, i, k) for n, i, k in names if k not in failed]
    if landed is not None:
        landed = sum(1 for _, _, k in names[:landed] if k not in failed)
    skill = command or bool(skills - failed)
    return [(n, i) for n, i, _ in kept], closeout, skill, landed, dismissed


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


def merge_gaps(calls, closeout, skill, landed=None):
    """What a turn that merged a PR still owes: the PR description rewritten
    after the merge, a closeout in chat and the closeout skill (P15, closeout
    skill step 5). A merge is a direct `gh pr merge`, or an auto-merge that
    landed before call LANDED."""
    steps, first = [], {}
    for k, (n, i) in enumerate(calls):
        first[k] = len(steps)
        if n == "Bash":
            steps += steps_of([str(i.get("command", ""))])
    merged = [k for k, c in enumerate(steps) if MERGE.match(c) and not NOT_MERGE.search(c)]
    if landed is not None:
        merged.append(first.get(landed, len(steps)) - 1)
    if not merged:
        return []
    gaps = []
    if not skill:
        gaps.append("load the closeout skill (Skill `agent-practices:closeout`) and write the "
                    "PR description and the chat summary with it")
    if not any(EDIT.match(c) for c in steps[max(merged) + 1:]):
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
    calls, earlier, skill, landed, dismissed = turn_tools(data["transcript_path"])
    gaps = merge_gaps(calls, earlier or bool(notify), skill, landed)
    if notify and not skill and not gaps:
        gaps.append("load the closeout skill (Skill `agent-practices:closeout`) and write the "
                    "closeout with it; a closeout written without it misses its template")
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
    """Whether a sentence says it waits on CI, a run or a merge, and not on me."""
    for sentence in SENTENCE.split(text):
        if ON_ME.search(sentence):
            continue
        if WAITING.search(sentence) and CI_NOUN.search(sentence):
            return True
    return False


try:
    main()
except Exception as e:
    print(f"check-attention: skipped, {type(e).__name__}: {e}", file=sys.stderr)
