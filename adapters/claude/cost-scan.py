#!/usr/bin/env python3
"""Scan Claude Code transcripts for spend over a date range (cost-review skill).

Usage: cost-scan.py --since YYYY-MM-DD --until YYYY-MM-DD [--tz ZONE]
                    [--projects-root DIR] [--out PATH]

Reads main transcripts (ROOT/PROJECT/SESSION.jsonl) and their subagent
transcripts (ROOT/PROJECT/SESSION/subagents/**/agent-*.jsonl, workflow agents
included). A session belongs to the window by its first timestamp; days are
days in --tz (default: this machine's zone), both ends inclusive. Writes one
JSON document (schema 1) that scripts/cost-report.py reads. The transcript
facts this relies on are listed in README.md ("Transcript facts the cost
scanner relies on").

Counting rules:
- An API call is the last transcript line per message.id; model <synthetic>
  is not a call. A compaction is a system line with subtype compact_boundary.
- A session's cost comes from the last cost-state line of its main
  transcript (it covers the session's subagents), priced with PRICES below;
  Claude Code's own costUSD is kept for comparison. Calls after that line
  (the session resumed) add their transcript cost (basis "cost-state+tail");
  a subagent call counts there only when later than the first main line
  after the cost-state line. Without a cost-state line the transcript sum is
  used (basis "transcript").
- cost-state has one cache-write count per model; it is split into 5m and 1h
  writes by the ratio in the session's own transcripts for that model (5m
  when the transcripts have none), and fast mode and US inference apply at
  the transcripts' cost-weighted rate for that model.
- Subagent transcripts record output_tokens at stream start only, so a
  subagent's output is the model's cost-state output less the main
  transcript's, shared among that model's subagents by calls. Other token
  counts go to the main session and each subagent in proportion to their
  transcripts; a model with no transcript calls goes to role "untracked".

Privacy: the output holds numbers, model and tool names, agent types that
Claude Code recorded for a subagent it ran, project folder names, the
working directory, file paths of Read/Edit/MultiEdit/Write/NotebookEdit,
the program name of Bash commands when it is on PROGRAMS, session ids and
timestamps. Never message text, tool input or output, agent descriptions,
titles or prompts.
"""
import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

PRICES_URL = "https://platform.claude.com/docs/en/about-claude/pricing"
PRICES_DATE = "2026-10-07"
PRICES_SOURCE = f"{PRICES_URL}, checked {PRICES_DATE}"
# USD per million tokens: input, output, cache read, 5m write, 1h write.
# Exact model ids only. Every row, the fast-mode and US multipliers and the
# web-search price were confirmed on PRICES_URL on PRICES_DATE.
PRICES = {
    "claude-fable-5-1": (10, 50, 0.25, 12.5, 20),
    "claude-opus-5-5": (4, 20, 0.20, 5, 8),
    "claude-opus-5": (5, 25, 0.50, 6.25, 10),
    "claude-opus-4-8": (5, 25, 0.50, 6.25, 10),
    "claude-sonnet-5-5": (2, 10, 0.20, 2.5, 4),
    "claude-sonnet-5": (2, 10, 0.20, 2.5, 4),
    "claude-haiku-4-5-20251001": (1, 5, 0.10, 1.25, 2),
}
# speed "fast": the page lists fast input and output at twice the base price,
# with cache multipliers on top. A fast call on another model is not priced.
FAST = {"claude-opus-5-5": 2, "claude-opus-5": 2, "claude-opus-4-8": 2}
# inference_geo "us": 1.1x on 4.6 and later models; earlier ones reject it.
GEO_US = 1.1
NO_GEO = {"claude-haiku-4-5-20251001"}
GEO_NONE = ("", "not_available", "global", None)
WEB_SEARCH_USD = 0.01  # $10 per 1,000 searches
# cost-state may key a model as "MODEL[1m]"; the page prices the 1M context
# window at standard rates on these models, so the tag is dropped.
CONTEXT_TAG = re.compile(r"\[1m\]$")

MAIN_TTL = 3600  # main sessions write 1h cache (observed)
SUB_TTL = 300  # subagents write 5m cache (observed)
MISS_TOKENS = 20000  # a write this big that reads under half the last context is a miss
READ_TOOLS = ("Read",)
READ_PROGRAMS = ("cat", "sed", "head", "tail", "grep", "rg", "find")
EDIT_TOOLS = {"Edit": "file_path", "MultiEdit": "file_path", "Write": "file_path",
              "NotebookEdit": "notebook_path"}
SPAWN_TOOLS = ("Agent", "Task")
SPAWN_MODELS = ("inherit", "opus", "sonnet", "haiku", "fable")
# Bash program names that may appear in the output; anything else is "other".
PROGRAMS = frozenset("""
cd echo printf export source test true false set unset exit read eval exec wait
sleep time type command which env timeout nohup sudo
ls cat head tail wc sort uniq cut tr tee cp mv rm mkdir rmdir touch chmod ln pwd
date basename dirname realpath readlink stat du df diff cmp comm paste xargs
file mktemp shasum sha256sum md5 tar zip unzip gzip ps kill pkill lsof
grep rg find fd sed awk jq yq
git gh python python3 pip pip3 uv pytest ruff mypy node npm npx pnpm yarn bun
deno tsc eslint prettier make cargo go swift xcodebuild xcrun gradle gradlew
docker kubectl helm terraform curl wget ssh scp rsync open osascript brew
sqlite3 psql ruby bundle java sh bash zsh launchctl defaults plutil
""".split())

NAME = re.compile(r"^[A-Za-z0-9_.:@+\[\]-]{1,100}$")
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
WORKTREE = re.compile(r"/\.claude/worktrees/[^/]+.*$")


def name(s):
    """A model or tool name, or "?" when it does not look like one."""
    return s if isinstance(s, str) and NAME.match(s) else "?"


def program(cmd):
    """The program a Bash command runs, if on PROGRAMS: first word after env
    assignments and a leading "cd DIR &&"; else "other"."""
    words = cmd.split() if isinstance(cmd, str) else []
    i = 0
    while i < len(words):
        if ENV_ASSIGN.match(words[i]):
            i += 1
        elif words[i] == "cd" and i + 2 < len(words) and words[i + 2] in ("&&", ";"):
            i += 3
        else:
            break
    if i >= len(words):
        return "other"
    p = words[i].rsplit("/", 1)[-1]
    return p if p in PROGRAMS else "other"


def path_of(v):
    ok = isinstance(v, str) and v[:1] in ("/", "~") and "\n" not in v and len(v) <= 400
    return v if ok else "?"


def parse_ts(s):
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        return None


def iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def local_zone():
    """This machine's IANA zone: $TZ, else /etc/localtime's target, else UTC."""
    candidates = [os.environ.get("TZ", "").lstrip(":")]
    try:
        target = os.path.realpath("/etc/localtime")
        if "zoneinfo/" in target:
            candidates.append(target.split("zoneinfo/", 1)[1])
    except OSError:
        pass
    for c in candidates:
        if c:
            try:
                return c, ZoneInfo(c)
            except (ZoneInfoNotFoundError, ValueError):
                continue
    return "UTC", ZoneInfo("UTC")


def multiplier(model, usage):
    """Price multiplier for fast mode and US inference, or None when not priced."""
    m = 1.0
    if usage.get("speed") == "fast":
        if model not in FAST:
            return None
        m *= FAST[model]
    geo = usage.get("inference_geo")
    if geo not in GEO_NONE:
        if geo != "us" or model in NO_GEO:
            return None
        m *= GEO_US
    return m


def token_cost(model, inp, out, cr, w5, w1, mult=1.0):
    p = PRICES.get(model)
    if p is None or mult is None:
        return 0.0
    return (inp * p[0] + out * p[1] + cr * p[2] + w5 * p[3] + w1 * p[4]) / 1e6 * mult


def read_lines(path):
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if isinstance(d, dict):
                yield d


def parse_transcript(path, main):
    """Calls, compactions and tool facts of one transcript."""
    calls, order = {}, []
    compactions, tools, spawns = [], {}, []
    reads, shell, edits = [], {}, []
    seen_tools = set()
    cost_state = cs_time = resume_time = None
    cs_line = -1
    first = last = cwd = None
    pending_compact = False
    usage_lines = 0
    for n, d in enumerate(read_lines(path)):
        t = parse_ts(d.get("timestamp")) if d.get("timestamp") else None
        if t:
            first = first or t
            last = t
        if cwd is None and isinstance(d.get("cwd"), str):
            cwd = d["cwd"]
        kind = d.get("type")
        if t and cost_state is not None and resume_time is None:
            resume_time = t  # first main line after the last cost-state line
        if kind == "cost-state":
            cost_state, cs_time, cs_line = d, last, n
            resume_time = None
        elif kind == "system" and d.get("subtype") == "compact_boundary":
            cm = d.get("compactMetadata") or {}
            trig = cm.get("trigger")
            compactions.append({"t": iso(t) if t else None,
                                "trigger": trig if trig in ("auto", "manual") else "?",
                                "pre": cm.get("preTokens") if isinstance(cm.get("preTokens"), int) else None,
                                "post": cm.get("postTokens") if isinstance(cm.get("postTokens"), int) else None})
            pending_compact = True
        elif kind == "assistant":
            m = d.get("message") or {}
            mid = m.get("id")
            if not mid or m.get("model") == "<synthetic>":
                continue
            if isinstance(m.get("usage"), dict):
                usage_lines += 1
            if mid not in calls:
                order.append(mid)
                calls[mid] = {"t0": t, "pc": pending_compact, "line": n}
                pending_compact = False
            calls[mid].update(model=name(m.get("model")), usage=m.get("usage") or {}, t1=t)
            for c in m.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use" or c.get("id") in seen_tools:
                    continue
                seen_tools.add(c.get("id"))
                tool = name(c.get("name"))
                tools[tool] = tools.get(tool, 0) + 1
                inp = c.get("input") if isinstance(c.get("input"), dict) else {}
                if tool in READ_TOOLS:
                    reads.append(path_of(inp.get("file_path")))
                elif tool == "Bash":
                    p = program(inp.get("command"))
                    shell[p] = shell.get(p, 0) + 1
                elif tool in EDIT_TOOLS:
                    edits.append({"tool": tool, "path": path_of(inp.get(EDIT_TOOLS[tool]))})
                elif tool in SPAWN_TOOLS:
                    mdl = inp.get("model")
                    spawns.append({"requested": inp.get("subagent_type") or "general-purpose",
                                   "model": mdl if mdl in SPAWN_MODELS else ("other" if mdl else None)})
    out = []
    prev_t = prev_ctx = None
    ttl = MAIN_TTL if main else SUB_TTL
    for i, mid in enumerate(order):
        r = calls[mid]
        u = r["usage"]
        model = r["model"]
        cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else None
        if cc:
            w5 = cc.get("ephemeral_5m_input_tokens") or 0
            w1 = cc.get("ephemeral_1h_input_tokens") or 0
        else:
            w5, w1 = u.get("cache_creation_input_tokens") or 0, 0
        inp = u.get("input_tokens") or 0
        outp = u.get("output_tokens") or 0
        cr = u.get("cache_read_input_tokens") or 0
        stu = u.get("server_tool_use") if isinstance(u.get("server_tool_use"), dict) else {}
        ws = stu.get("web_search_requests") or 0
        mult = multiplier(model, u)
        priced = model in PRICES and mult is not None
        usd = token_cost(model, inp, outp, cr, w5, w1, mult) + (ws * WEB_SEARCH_USD if priced else 0)
        wusd = token_cost(model, 0, 0, 0, w5, w1, mult)
        ctx = inp + cr + w5 + w1
        cause = None
        if w5 + w1:
            if i == 0:
                cause = "start"
            elif r["pc"]:
                cause = "compaction"
            elif prev_t and r["t0"] and (r["t0"] - prev_t).total_seconds() > ttl:
                cause = "idle"
            elif w5 + w1 > MISS_TOKENS and prev_ctx and cr < 0.5 * prev_ctx:
                cause = "miss"
            else:
                cause = "growth"
            # The next call's cache lifetime follows this call's write type.
            ttl = MAIN_TTL if w1 >= w5 else SUB_TTL
        rec = {"t": iso(r["t0"]) if r["t0"] else None, "m": model, "in": inp, "out": outp, "cr": cr,
               "w5": w5, "w1": w1, "usd": round(usd, 6), "wusd": round(wusd, 6)}
        if ws:
            rec["ws"] = ws
        if cause:
            rec["cause"] = cause
        if not priced:
            rec["np"] = 1
        if mult not in (None, 1.0):
            rec["x"] = mult
        if cost_state is not None and r["line"] > cs_line:
            rec["tail"] = 1
        # Base-price cost, for the cost-state rate of fast mode and US inference.
        rec["_base"] = token_cost(model, inp, outp, cr, w5, w1) if model in PRICES else 0.0
        out.append(rec)
        prev_t = r["t1"] or r["t0"]
        prev_ctx = ctx
    return {"calls": out, "compactions": compactions, "tools": tools, "spawns": spawns,
            "reads": reads, "shell": shell, "edits": edits, "cost_state": cost_state,
            "cs_time": cs_time, "resume_time": resume_time, "first": first, "last": last, "cwd": cwd, "usage_lines": usage_lines}


CS_FIELDS = (("in", "inputTokens"), ("out", "outputTokens"), ("cr", "cacheReadInputTokens"),
             ("cw", "cacheCreationInputTokens"), ("ws", "webSearchRequests"))


def cost_state_tokens(cost_state):
    """Token counts per model from a cost-state line, context tag dropped."""
    out = {}
    for model, mu in (cost_state.get("modelUsage") or {}).items():
        if not isinstance(mu, dict):
            continue
        model = name(CONTEXT_TAG.sub("", model) if isinstance(model, str) else model)
        tok = out.setdefault(model, {k: 0 for k, _ in CS_FIELDS})
        for k, f in CS_FIELDS:
            v = mu.get(f)
            tok[k] += v if isinstance(v, (int, float)) else 0
    return out


def allocate(units, cost_state):
    """Share a cost-state's priced cost among the session's units, then add
    each unit's calls after the cost-state line; per unit, per model USD."""
    alloc = {u: {} for u in units}
    alloc["untracked"] = {}
    for model, tok in cost_state_tokens(cost_state).items():
        priced = model in PRICES
        ws_usd = tok["ws"] * WEB_SEARCH_USD if priced else 0.0
        per = {}
        for u, data in units.items():
            cs = [c for c in data["calls"] if c["m"] == model and not c.get("tail")]
            if cs:
                s = {k: sum(c.get(k, 0) for c in cs) for k in ("in", "out", "cr", "w5", "w1", "usd", "_base", "ws")}
                s["n"] = len(cs)
                per[u] = s
        if not per:
            alloc["untracked"][model] = alloc["untracked"].get(model, 0.0) + ws_usd + token_cost(
                model, tok["in"], tok["out"], tok["cr"], tok["cw"], 0)
            continue
        share = {u: {"in": 0.0, "out": 0.0, "cr": 0.0, "w5": 0.0, "w1": 0.0, "ws": 0.0} for u in per}
        ncalls = sum(v["n"] for v in per.values())
        for k, keys in (("in", ("in",)), ("cr", ("cr",)), ("cw", ("w5", "w1")), ("ws", ("ws",))):
            total = sum(sum(s[x] for x in keys) for s in per.values())
            for u, s in per.items():
                part = sum(s[x] for x in keys)
                frac = part / total if total else s["n"] / ncalls
                amount = tok[k] * frac
                if k == "cw":
                    both = s["w5"] + s["w1"]
                    share[u]["w1"] += amount * (s["w1"] / both if both else 0)
                    share[u]["w5"] += amount * (s["w5"] / both if both else 1)
                else:
                    share[u][k] += amount
        main_out = min(per["main"]["out"], tok["out"]) if "main" in per else 0
        if "main" in per:
            share["main"]["out"] = main_out
        rest = tok["out"] - main_out
        subs = {u: s for u, s in per.items() if u != "main"}
        if subs:
            n = sum(s["n"] for s in subs.values())
            for u, s in subs.items():
                share[u]["out"] += rest * s["n"] / n
        else:
            share["main"]["out"] += rest
        for u, sh in share.items():
            s = per[u]
            mult = s["usd"] / s["_base"] if s["_base"] else 1.0
            c = token_cost(model, sh["in"], sh["out"], sh["cr"], sh["w5"], sh["w1"], mult)
            if priced:
                c += sh["ws"] * WEB_SEARCH_USD
            alloc[u][model] = alloc[u].get(model, 0.0) + c
    for u, data in units.items():
        for c in data["calls"]:
            if c.get("tail"):
                alloc[u][c["m"]] = alloc[u].get(c["m"], 0.0) + c["usd"]
    return alloc


def agent_meta(path):
    try:
        with open(path[:-len(".jsonl")] + ".meta.json", encoding="utf-8") as fh:
            meta = json.load(fh)
    except (OSError, ValueError):
        return {}
    return meta if isinstance(meta, dict) else {}


def project_name(cwd, project):
    """Display name: the repository folder of the session's working directory
    (a worktree counts as its repository), "~" for the home directory."""
    home = os.path.expanduser("~")
    if not isinstance(cwd, str) or not cwd.startswith("/"):
        enc = re.sub(r"[^A-Za-z0-9]", "-", home)
        group = re.sub(r"--claude-worktrees-.*$", "", project)
        return group[len(enc):].lstrip("-") or "~" if group.startswith(enc) else group
    root = WORKTREE.sub("", cwd.rstrip("/"))
    if root == home:
        return "~"
    parts = root.split("/")
    for i, p in enumerate(parts):
        if p.endswith("-worktrees") and i > 0:
            return p[:-len("-worktrees")]
    return parts[-1] or "/"


def scan_session(root, project, path, tz):
    sid = os.path.basename(path)[:-len(".jsonl")]
    main = parse_transcript(path, True)
    units = {"main": main}
    subs = []
    sub_glob = os.path.join(root, project, sid, "subagents", "**", "agent-*.jsonl")
    for sp in sorted(glob.glob(sub_glob, recursive=True)):
        aid = os.path.basename(sp)[:-len(".jsonl")]
        data = parse_transcript(sp, False)
        units[aid] = data
        meta = agent_meta(sp)
        atype = meta.get("agentType")
        subs.append((aid, data, atype if isinstance(atype, str) and NAME.match(atype) else "?",
                     "workflow" if "/workflows/" in sp.replace(os.sep, "/") else None))
    cs = main["cost_state"]
    # A subagent call is outside the cost-state line only when the main
    # session resumed after that line and the call is later than the resume;
    # a background subagent that ended before the session exited is counted.
    if cs and main["resume_time"]:
        for aid, data, _, _ in subs:
            for c in data["calls"]:
                if c["t"] and parse_ts(c["t"]) > main["resume_time"]:
                    c["tail"] = 1
    transcript_usd = sum(c["usd"] for u in units.values() for c in u["calls"])
    tail_usd = sum(c["usd"] for u in units.values() for c in u["calls"] if c.get("tail"))
    if cs:
        alloc = allocate(units, cs)
        tail = any(c.get("tail") for u in units.values() for c in u["calls"])
        basis = "cost-state+tail" if tail else "cost-state"
    else:
        alloc = {u: {} for u in units}
        alloc["untracked"] = {}
        for u, data in units.items():
            for c in data["calls"]:
                alloc[u][c["m"]] = alloc[u].get(c["m"], 0.0) + c["usd"]
        basis = "transcript"
    models = {}
    for per in alloc.values():
        for m, v in per.items():
            models[m] = models.get(m, 0.0) + v
    days_main, days_sub = {}, {}
    for u, data in units.items():
        days = days_main if u == "main" else days_sub
        for c in data["calls"]:
            t = parse_ts(c["t"]) if c["t"] else None
            if t:
                d = t.astimezone(tz).date().isoformat()
                days[d] = days.get(d, 0.0) + c["usd"]
    unpriced = {c["m"] for u in units.values() for c in u["calls"] if c.get("np")}
    if cs:
        unpriced |= {m for m in cost_state_tokens(cs) if m not in PRICES}
    known_types = {t for _, _, t, _ in subs if t != "?"}
    session = {
        "session_id": sid, "project": project,
        "project_group": re.sub(r"--claude-worktrees-.*$", "", project),
        "project_name": project_name(main["cwd"], project),
        "cwd": path_of(main["cwd"]),
        "start": iso(main["first"]), "start_local": main["first"].astimezone(tz).isoformat(timespec="minutes"),
        "end": iso(main["last"]) if main["last"] else None,
        "basis": basis, "usd": round(sum(models.values()), 6),
        "transcript_usd": round(transcript_usd, 6), "tail_usd": round(tail_usd, 6),
        "models": {m: round(v, 6) for m, v in models.items()},
        "untracked_usd": round(sum(alloc["untracked"].values()), 6),
        "days_main": {d: round(v, 6) for d, v in sorted(days_main.items())},
        "days_subagents": {d: round(v, 6) for d, v in sorted(days_sub.items())},
        "unpriced_models": sorted(unpriced),
        "compactions": main["compactions"], "tools": main["tools"],
        # A requested type is printed only when it names a subagent that ran.
        "spawns": [{"type": s["requested"] if s["requested"] in known_types else "other", "model": s["model"]}
                   for s in main["spawns"]],
        "reads": main["reads"], "shell": main["shell"], "edits": main["edits"],
        "coordinator_reads": len(main["reads"]) + sum(n for p, n in main["shell"].items() if p in READ_PROGRAMS),
        "main_usd": round(sum(alloc["main"].values()), 6),
        "calls": main["calls"],
        "subagents": [],
    }
    if cs:
        cs_models = {}
        for m, mu in (cs.get("modelUsage") or {}).items():
            if isinstance(mu, dict):
                cs_models[name(m)] = {k: mu.get(k) for k in (
                    "inputTokens", "outputTokens", "thinkingTokens", "cacheReadInputTokens",
                    "cacheCreationInputTokens", "webSearchRequests", "costUSD")
                    if isinstance(mu.get(k), (int, float))}
        total = cs.get("totalCostUSD")
        session["cost_state"] = {
            "total_cost_usd": total if isinstance(total, (int, float)) else None,
            "sum_cost_usd": round(sum(v.get("costUSD", 0) for v in cs_models.values()), 6),
            "models": cs_models,
        }
    for aid, data, atype, kind in subs:
        counts = {}
        for c in data["calls"]:
            counts[c["m"]] = counts.get(c["m"], 0) + 1
        sub = {"id": aid, "type": atype, "model": max(counts, key=counts.get) if counts else None,
               "usd": round(sum(alloc[aid].values()), 6),
               "transcript_usd": round(sum(c["usd"] for c in data["calls"]), 6),
               "compactions": len(data["compactions"]), "calls": data["calls"]}
        if kind:
            sub["kind"] = kind
        session["subagents"].append(sub)
    for u in units.values():
        for c in u["calls"]:
            c.pop("_base", None)
    return session, sum(u["usage_lines"] for u in units.values())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--since", required=True, type=dt.date.fromisoformat)
    ap.add_argument("--until", required=True, type=dt.date.fromisoformat)
    ap.add_argument("--tz", help="IANA zone for day boundaries (default: this machine's)")
    ap.add_argument("--projects-root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--out")
    a = ap.parse_args()
    if a.tz:
        try:
            tz_name, tz = a.tz, ZoneInfo(a.tz)
        except (ZoneInfoNotFoundError, ValueError):
            sys.exit(f"error: unknown time zone {a.tz!r}")
    else:
        tz_name, tz = local_zone()
    start = dt.datetime.combine(a.since, dt.time(), tz)
    end = dt.datetime.combine(a.until + dt.timedelta(days=1), dt.time(), tz)
    root = a.projects_root
    sessions = []
    usage_lines = 0
    for path in sorted(glob.glob(os.path.join(root, "*", "*.jsonl"))):
        first = None
        for d in read_lines(path):
            first = parse_ts(d.get("timestamp")) if d.get("timestamp") else None
            if first:
                break
        if not first or not start <= first < end:
            continue
        project = os.path.basename(os.path.dirname(path))
        s, n = scan_session(root, project, path, tz)
        sessions.append(s)
        usage_lines += n
    # The transcript format is the vendor's and may change; stop rather than
    # report numbers built on lines this scanner no longer recognises.
    if sessions and not usage_lines:
        sys.exit(f"error: {len(sessions)} sessions in the window but no assistant line with usage; "
                 "the transcript format may have changed (see adapters/claude/README.md, section on transcript facts)")
    # Open sessions have no cost-state line yet, so a window reaching today
    # can legitimately have none.
    today = dt.datetime.now(tz).date()
    if sessions and a.until < today and not any(s["basis"] != "transcript" for s in sessions):
        sys.exit(f"error: {len(sessions)} sessions in the window but none has a cost-state line; "
                 "the transcript format changed, or every session in the window is still running "
                 "(see adapters/claude/README.md, section on transcript facts)")
    doc = {
        "schema": 1,
        "source": "claude-code",
        "prices": {"date": PRICES_DATE, "source": PRICES_SOURCE, "unit": "USD per million tokens",
                   "columns": ["input", "output", "cache_read", "cache_write_5m", "cache_write_1h"],
                   "models": {m: list(p) for m, p in PRICES.items()},
                   "fast": FAST, "geo_us": GEO_US, "web_search_usd": WEB_SEARCH_USD,
                   "not_priced": "unknown models; fast mode or an inference geo the source does not list"},
        "window": {"since": a.since.isoformat(), "until": a.until.isoformat(), "tz": tz_name,
                   "start": iso(start), "end": iso(end), "session_by": "first timestamp of the main transcript"},
        "rules": {"responses": "API calls of main sessions (last line per message id, <synthetic> excluded)",
                  "coordinator_read_programs": list(READ_PROGRAMS),
                  "cache_write_causes": {
                      "start": "first call of a main session or subagent",
                      "compaction": "first call after a compaction",
                      "idle": "gap since the last call over the cache lifetime of the last write "
                              f"(1h write: {MAIN_TTL}s, 5m write: {SUB_TTL}s; before any write, "
                              "main sessions 1h and subagents 5m)",
                      "miss": f"not idle, but a write over {MISS_TOKENS} tokens whose cache read is "
                              "under half the previous call's context (the cached prefix changed)",
                      "growth": "any other write: new turns appended to a cached prefix"}},
        "sessions": sessions,
    }
    text = json.dumps(doc, separators=(",", ":"))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    else:
        sys.stdout.write(text + "\n")


if __name__ == "__main__":
    main()
