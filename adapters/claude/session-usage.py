#!/usr/bin/env python3
"""Measure one Claude Code session from its local transcript.

Usage: session-usage.py SESSION [--row]

SESSION is a session id, a unique id prefix, or the path of the transcript
(`<config dir>/projects/<project>/<id>.jsonl`; the config dir is
$CLAUDE_CONFIG_DIR or ~/.claude). Subagent transcripts are read from
`<project>/<id>/subagents/agent-*.jsonl` with their `.meta.json` beside them.

Prints, for the parent and each subagent: responses (one per assistant
message id), model, tokens (input, cache read, cache write, output), the
context each response carried (input + cache read + cache write; mean by
quarter of the session, and the largest), compactions with the context they
started from, elapsed time, and what the tool calls were spent on: images
returned, tool results over 5,000 characters, read-style shell calls
(`sed -n`, `grep`, `cat`, `head`, `tail`, `rg`, `find`, `ls`; `sed -i` and
`find -delete` are not reads), waits (any `sleep`), and files opened more than
twice through `Read` or `sed -n` (paths made absolute against the record's
working directory, so both count for the same file).

`--row` prints instead one Markdown row for the trial log described in
practices/context-efficiency.md (columns: date, agent, slice, model,
responses, input / cache read / cache write / output, compactions including
subagents, elapsed, proof, rework); slice, proof and rework are left as
placeholders to fill in.

Exits 2 when the session cannot be found or the prefix is ambiguous.
Usage figures come from the API usage block on each assistant message; a
message streamed in several chunks takes the last chunk's block, and a
response with no usage block counts as a response with zero tokens and is
left out of the context figures.
"""
import collections
import datetime
import glob
import json
import os
import pathlib
import re
import shlex
import sys

READ_CMDS = {"sed", "grep", "cat", "head", "tail", "rg", "find", "ls"}
LARGE_RESULT = 5000
SED_PATH_RE = re.compile(r"sed\s+(?:-[a-zA-Z]+\s+)*(?:'[^']*'|\"[^\"]*\"|[^\s'\"-]\S*)((?:\s+(?:'[^']*'|\"[^\"]*\"|[^\s;&|)]+))+)")
SLEEP_RE = re.compile(r"(?:^|[\s;&|(])sleep\s+\d")


def config_dir():
    return pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR") or pathlib.Path.home() / ".claude")


def find_transcript(arg):
    p = pathlib.Path(arg)
    if p.suffix == ".jsonl" and p.is_file():
        return p
    hits = sorted(set(glob.glob(str(config_dir() / "projects" / "*" / f"{arg}*.jsonl"))))
    if len(hits) != 1:
        what = "no session matches" if not hits else f"{len(hits)} sessions match"
        print(f"error: {what} {arg!r}", file=sys.stderr)
        sys.exit(2)
    return pathlib.Path(hits[0])


def records(path):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def first_words(command):
    """The command word and its arguments, after a leading `cd X &&`/`;`,
    an opening subshell bracket and shell variable assignments."""
    try:
        words = shlex.split(command, posix=True)
    except ValueError:
        words = command.split()
    words = [w.lstrip("(") for w in words]
    words = [w for w in words if w]
    if words and words[0] == "cd":
        for i, w in enumerate(words[1:], 1):
            if w in ("&&", ";", "||"):
                words = words[i + 1:]
                break
    while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
        words = words[1:]
    return [os.path.basename(words[0])] + words[1:] if words else []


def is_read(words):
    if not words or words[0] not in READ_CMDS:
        return False
    if words[0] == "sed" and any(w.startswith("-i") for w in words[1:]):
        return False
    if words[0] == "find" and "-delete" in words:
        return False
    return True


def sed_paths(command, cwd):
    if "sed" not in command or " -n" not in command:
        return []
    lead = re.match(r"\s*\(?cd\s+(/\S+)\s*(?:&&|;)", command)
    if lead:
        cwd = lead.group(1)
    out = []
    for group in SED_PATH_RE.findall(command):
        try:
            names = shlex.split(group)
        except ValueError:
            names = group.split()
        for n in names:
            if not n.startswith("-"):
                out.append(n if os.path.isabs(n) or not cwd else os.path.join(cwd, n))
    return out


def timestamp(rec):
    ts = rec.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def measure(path):
    m = {
        "responses": 0, "models": collections.Counter(),
        "input": 0, "cache_read": 0, "cache_write": 0, "output": 0,
        "contexts": [], "compactions": [], "tools": collections.Counter(),
        "images": 0, "large_results": 0, "large_chars": 0,
        "read_calls": 0, "waits": 0, "file_reads": collections.Counter(),
        "first": None, "last": None,
    }
    usage_by_id = {}
    order = []
    for rec in records(path):
        ts = timestamp(rec)
        if ts:
            m["first"] = m["first"] or ts
            m["last"] = ts
        if rec.get("type") == "system" and rec.get("subtype") == "compact_boundary":
            m["compactions"].append((rec.get("compactMetadata") or {}).get("preTokens", 0))
            continue
        msg = rec.get("message") or {}
        content = msg.get("content") if isinstance(msg.get("content"), list) else []
        if rec.get("type") == "assistant":
            mid = msg.get("id")
            if mid not in usage_by_id:
                order.append(mid)
                m["responses"] += 1
                m["models"][msg.get("model") or "?"] += 1
            # A streamed message repeats its id; the last chunk carries the
            # final output count.
            if msg.get("usage") is not None or mid not in usage_by_id:
                usage_by_id[mid] = msg.get("usage")
            cwd = rec.get("cwd") or ""
            for c in content:
                if c.get("type") != "tool_use":
                    continue
                name, inp = c.get("name", "?"), c.get("input") or {}
                if name == "Agent":
                    name += ":" + str(inp.get("subagent_type") or "general")
                elif name == "Bash":
                    cmd = inp.get("command") or ""
                    if is_read(first_words(cmd)):
                        m["read_calls"] += 1
                    if SLEEP_RE.search(cmd):
                        m["waits"] += 1
                    for p in sed_paths(cmd, cwd):
                        m["file_reads"][os.path.normpath(p)] += 1
                elif name == "Read" and inp.get("file_path"):
                    p = inp["file_path"]
                    m["file_reads"][os.path.normpath(p if os.path.isabs(p) or not cwd else os.path.join(cwd, p))] += 1
                m["tools"][name] += 1
        elif rec.get("type") == "user":
            for c in content:
                if c.get("type") != "tool_result":
                    continue
                body = c.get("content")
                if isinstance(body, list):
                    m["images"] += sum(1 for b in body if isinstance(b, dict) and b.get("type") == "image")
                    # Text size only: image data is counted under images.
                    n = sum(len(b.get("text") or "") for b in body if isinstance(b, dict) and b.get("type") == "text")
                else:
                    n = len(body) if isinstance(body, str) else len(json.dumps(body))
                if n > LARGE_RESULT:
                    m["large_results"] += 1
                    m["large_chars"] += n
    for mid in order:
        u = usage_by_id.get(mid)
        if not u:
            continue
        inp = u.get("input_tokens") or 0
        cr = u.get("cache_read_input_tokens") or 0
        cw = u.get("cache_creation_input_tokens") or 0
        m["input"] += inp
        m["cache_read"] += cr
        m["cache_write"] += cw
        m["output"] += u.get("output_tokens") or 0
        m["contexts"].append(inp + cr + cw)
    return m


def subagents(path):
    out = []
    for sp in sorted(glob.glob(str(path.with_suffix("") / "subagents" / "agent-*.jsonl"))):
        meta = {}
        mp = pathlib.Path(sp).with_suffix(".meta.json")
        if mp.is_file():
            try:
                meta = json.loads(mp.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                meta = {}
        out.append((meta.get("agentType") or "?", meta.get("description") or "", measure(pathlib.Path(sp))))
    return out


def k(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    return f"{n / 1000:.0f}k" if n >= 1000 else str(n)


def models(m):
    return ", ".join(f"{name} ({n})" if len(m["models"]) > 1 else name for name, n in m["models"].most_common())


def elapsed(m):
    if not (m["first"] and m["last"]):
        return "?"
    s = int((m["last"] - m["first"]).total_seconds())
    return f"{s // 3600}h{(s % 3600) // 60:02d}m" if s >= 3600 else f"{s // 60}m"


def quarters(contexts):
    n = len(contexts)
    if n < 4:
        return [sum(contexts) // n] if n else []
    out = []
    for i in range(4):
        part = contexts[i * n // 4:(i + 1) * n // 4]
        out.append(sum(part) // len(part))
    return out


def report(path, m, subs):
    print(f"session {path.stem}  ({path.parent.name})")
    print(f"  responses {m['responses']}  model {models(m)}  elapsed {elapsed(m)}")
    print(f"  tokens: input {k(m['input'])}  cache read {k(m['cache_read'])}  "
          f"cache write {k(m['cache_write'])}  output {k(m['output'])}")
    if m["contexts"]:
        print(f"  context per response: first {k(m['contexts'][0])}  mean by quarter "
              f"{' / '.join(k(c) for c in quarters(m['contexts']))}  max {k(max(m['contexts']))}")
    comp = m["compactions"]
    print(f"  compactions {len(comp)}" + (f"  from {', '.join(k(c) for c in comp)}" if comp else ""))
    print(f"  tool calls {sum(m['tools'].values())}: "
          + ", ".join(f"{n} {name}" for name, n in m["tools"].most_common(8)))
    print(f"  read-style shell calls {m['read_calls']}  waits {m['waits']}  images {m['images']}  "
          f"results over {k(LARGE_RESULT)} chars {m['large_results']} ({k(m['large_chars'])} chars)")
    rereads = [(p, n) for p, n in m["file_reads"].most_common() if n > 2]
    if rereads:
        print(f"  files opened more than twice ({len(rereads)}): "
              + ", ".join(f"{os.path.basename(p)} x{n}" for p, n in rereads[:8]))
    if subs:
        print("  subagents:")
        for role, desc, s in subs:
            print(f"    {role}  {models(s)}  responses {s['responses']}  cache read {k(s['cache_read'])}  "
                  f"cache write {k(s['cache_write'])}  output {k(s['output'])}  {desc}")
        print(f"  total cache read including subagents: "
              f"{k(m['cache_read'] + sum(s['cache_read'] for _, _, s in subs))}")


def row(m, subs):
    date = m["first"].date().isoformat() if m["first"] else "<date>"
    model = "parent " + models(m)
    by_role = collections.Counter((role.split(":")[-1], models(s)) for role, _, s in subs)
    for (role, name), n in by_role.items():
        model += f"; {role} {name}" + (f" x{n}" if n > 1 else "")
    def total(key):
        return m[key] + sum(s[key] for _, _, s in subs)
    resp = str(m["responses"]) + (f" (+{sum(s['responses'] for _, _, s in subs)} in subagents)" if subs else "")
    comp = len(m["compactions"]) + sum(len(s["compactions"]) for _, _, s in subs)
    print(f"| {date} | Claude Code | <project and slice> | {model} | {resp} | "
          f"{k(total('input'))} / {k(total('cache_read'))} / {k(total('cache_write'))} / {k(total('output'))} | "
          f"{comp} | {elapsed(m)} | <proof done> | <rework> |")


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    flags = {a for a in argv if a.startswith("--")}
    if len(args) != 1 or flags - {"--row"}:
        sys.exit(__doc__.strip().splitlines()[2])
    path = find_transcript(args[0])
    m = measure(path)
    subs = subagents(path)
    if "--row" in flags:
        row(m, subs)
    else:
        report(path, m, subs)


if __name__ == "__main__":
    main(sys.argv[1:])
