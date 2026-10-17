#!/usr/bin/env python3
"""Compute the cost-review measures from a cost-scan JSON document.

Usage: cost-report.py SCAN.json [--out PATH] [--text]

Reads the scan an agent adapter wrote (schema 1; for Claude Code,
adapters/claude/cost-scan.py) and writes the measures as JSON (stdout, or
--out). With --text, also prints a short plain-text summary (to stdout, or
to stderr when the JSON goes to stdout). Model names are opaque strings from
the scan; anything per model is decided there.

Measures, the same every run so runs compare:
 1. spend by day (main sessions and subagents), model, project and role,
    session cost bands, and 7-day rates;
 2. the top 15 sessions by cost, with facts for a one-line cause;
 3. context at session start (first call's input + cache read + cache
    write), overall and by project; main-session call spend by context size;
 4. cache-write cost by cause, with the scan's definitions;
 5. compactions per 100 responses (main-session API calls);
 6. coordinator reads (main-session file reads and read-only shell programs)
    and the most re-read files;
 7. review runs by role and model, with cost per run;
 8. self-implemented, delegated and other (`neither`) sessions (P2b): a
    session is self-implemented when its main session edited a file that is
    not a doc, delegated when it ran an implementer subagent and edited none,
    and "neither" otherwise: reading only, or edits only by a subagent that
    is not an implementer.
Added sections (absent from older scans they need: effort "e", idle "gap",
compaction "next_usd", session "start_sources"):
 9. cost and runs by role x model x effort (main sessions are role
    "coordinator");
10. idle cache rebuilds (calls with cause "idle"): per-event rows, by gap
    bucket, by role, share of spend, by number of other main sessions active
    in the previous hour, long-running main sessions, and subagent rebuilds
    resumed after the 5-minute cache lifetime;
11. the compaction log, with the cost of the call after each compaction;
12. the first call's context split by source, estimated from sizes
    (characters / 4) of the lines recorded before it, with the unsplit rest.
Spend uses each session's basis cost (scan field "usd"); by day, the main
session's share and each subagent's are spread over days by their
transcript cost per day.
"""
import argparse
import bisect
import datetime as dt
import json
import os
import statistics
import sys

TOP = 15
TOP_FILES = 20
REVIEW_ROLES = ("light-reviewer", "reviewer", "critical-reviewer", "critical-reviewer-strongest")
# The coordinator-edit hook's doc rule (adapters/claude/hooks/check-coordinator-edit.py).
DOCS = {".md", ".markdown", ".rst", ".txt", ".adoc"}
SOURCE_NAMES = ("cmakelists.txt", "requirements", "constraints")
GAP_BUCKETS = ((3600, "5min-1h"), (7200, "1-2h"), (28800, "2-8h"), (None, "8h+"))
ACTIVE_BUCKETS = ("0", "1", "2", "3+")
ACTIVE_WINDOW = 3600  # a main-session call this many seconds back counts as active
LONG_SESSION = 28800  # wall span of a long-running main session
RESUME_TTL = 300  # subagent cache lifetime
TOP_EVENTS = 15
COST_BANDS = ((1, "under $1"), (5, "$1-5"), (15, "$5-15"), (30, "$15-30"), (None, "$30+"))
CONTEXT_BANDS = ((50, "under 50k"), (75, "50-75k"), (100, "75-100k"), (125, "100-125k"),
                 (150, "125-150k"), (175, "150-175k"), (None, "175k+"))


def role_of(agent_type):
    """Role name without a plugin prefix ("plugin:reviewer" -> "reviewer")."""
    return (agent_type or "?").rsplit(":", 1)[-1]


def ctx(call):
    return call["in"] + call["cr"] + call["w5"] + call["w1"]


def r2(x):
    return round(x, 2)


def add(d, k, v):
    d[k] = d.get(k, 0) + v


def band(value, bands):
    for limit, label in bands:
        if limit is None or value < limit:
            return label
    return bands[-1][1]


def percentiles(xs):
    if not xs:
        return {"n": 0}
    xs = sorted(xs)
    q = lambda p: xs[min(len(xs) - 1, int(p * len(xs)))]
    return {"n": len(xs), "median": statistics.median(xs), "p10": q(0.10), "p25": q(0.25),
            "p75": q(0.75), "p90": q(0.90), "min": xs[0], "max": xs[-1]}


def is_doc(path):
    base = os.path.basename(path).lower()
    if os.path.splitext(base)[1] not in DOCS:
        return False
    return not (base == SOURCE_NAMES[0] or (base.endswith(".txt") and base.startswith(SOURCE_NAMES[1:])))


def self_edits(s):
    return [e["path"] for e in s["edits"] if e["path"] != "?" and not is_doc(e["path"])]


def kind_of(s):
    if self_edits(s):
        return "self-implemented"
    if any(role_of(a["type"]) == "implementer" for a in s["subagents"]):
        return "delegated"
    return "neither"


def by_value(d, digits=2):
    return {k: round(v, digits) for k, v in sorted(d.items(), key=lambda kv: -kv[1])}


def spread(total, days, into):
    tdays = sum(days.values())
    for d, v in days.items():
        if tdays:
            add(into, d, total * v / tdays)


def spend(sessions, window):
    main_day, sub_day, model, project, role = {}, {}, {}, {}, {}
    bands = {label: {"sessions": 0, "usd": 0.0} for _, label in COST_BANDS}
    for s in sessions:
        main_total = s["main_usd"] + s["untracked_usd"]
        sub_total = sum(a["usd"] for a in s["subagents"])
        if sum(s["days_main"].values()) or not sum(s["days_subagents"].values()):
            spread(main_total, s["days_main"] or {s["start_local"][:10]: 1}, main_day)
        else:
            sub_total += main_total
        if sum(s["days_subagents"].values()):
            spread(sub_total, s["days_subagents"], sub_day)
        elif sub_total:
            spread(sub_total, s["days_main"] or {s["start_local"][:10]: 1}, main_day)
        for m, v in s["models"].items():
            add(model, m, v)
        add(project, s["project_name"], s["usd"])
        add(role, "main", s["main_usd"])
        for a in s["subagents"]:
            add(role, a["type"], a["usd"])
        if s["untracked_usd"]:
            add(role, "untracked", s["untracked_usd"])
        b = bands[band(s["usd"], COST_BANDS)]
        b["sessions"] += 1
        b["usd"] += s["usd"]
    by_day = {}
    for d in sorted(set(main_day) | set(sub_day)):
        m, sb = main_day.get(d, 0.0), sub_day.get(d, 0.0)
        by_day[d] = {"usd": r2(m + sb), "main": r2(m), "subagents": r2(sb)}
        if d > window["until"]:
            by_day[d]["after_window"] = True
    after = sum(v["usd"] for d, v in by_day.items() if v.get("after_window"))
    return {"by_day": by_day, "after_window_usd": r2(after), "by_model": by_value(model),
            "by_project": by_value(project), "by_role": by_value(role),
            "cost_bands": {k: {"sessions": v["sessions"], "usd": r2(v["usd"])} for k, v in bands.items()}}


def facts(s):
    calls = s["calls"]
    subs = {}
    for a in s["subagents"]:
        t = subs.setdefault(a["type"], {"runs": 0, "usd": 0.0})
        t["runs"] += 1
        t["usd"] += a["usd"]
    causes = {}
    for c in calls:
        if c.get("cause"):
            add(causes, c["cause"], c["wusd"])
    return {
        "session_id": s["session_id"], "project": s["project_name"], "start_local": s["start_local"],
        "start": s["start"], "end": s["end"],
        "usd": r2(s["usd"]), "basis": s["basis"], "transcript_usd": r2(s["transcript_usd"]),
        "main_usd": r2(s["main_usd"]), "subagent_usd": r2(sum(a["usd"] for a in s["subagents"])),
        "models": by_value(s["models"]),
        "kind": kind_of(s),
        "responses": len(calls),
        "compactions": len(s["compactions"]),
        "compaction_triggers": sorted({c["trigger"] for c in s["compactions"]}),
        "start_context": ctx(calls[0]) if calls else None,
        "peak_context": max((ctx(c) for c in calls), default=0),
        "subagents": {k: {"runs": v["runs"], "usd": r2(v["usd"])} for k, v in sorted(subs.items())},
        "subagent_compactions": sum(a["compactions"] for a in s["subagents"]),
        "coordinator_reads": s["coordinator_reads"],
        "self_edits": len(self_edits(s)),
        "doc_edits": sum(1 for e in s["edits"] if e["path"] != "?" and is_doc(e["path"])),
        "main_cache_write_usd_by_cause": by_value(causes),
    }


def start_context(sessions):
    starts = [ctx(s["calls"][0]) for s in sessions if s["calls"]]
    hist = {}
    for x in starts:
        b = min(x // 10000 * 10, 200)
        add(hist, f"{b}k+" if b == 200 else f"{b}-{b + 10}k", 1)
    per_project = {}
    for s in sessions:
        if s["calls"]:
            per_project.setdefault(s["project_name"], []).append(ctx(s["calls"][0]))
    out = percentiles(starts)
    out["histogram"] = dict(sorted(hist.items(), key=lambda kv: int(kv[0].split("-")[0].rstrip("k+"))))
    out["by_project"] = {p: {"sessions": len(v), "median": statistics.median(v)}
                         for p, v in sorted(per_project.items(), key=lambda kv: -len(kv[1]))}
    return out


def context_spend(sessions):
    rows = {label: {"calls": 0, "usd": 0.0} for _, label in CONTEXT_BANDS}
    for s in sessions:
        for c in s["calls"]:
            r = rows[band(ctx(c) / 1000, CONTEXT_BANDS)]
            r["calls"] += 1
            r["usd"] += c["usd"]
    return {"basis": "transcripts, main-session calls",
            "by_context": {k: {"calls": v["calls"], "usd": r2(v["usd"])} for k, v in rows.items()}}


def cache_writes(sessions, definitions):
    out = {}
    for s in sessions:
        for who, calls in [("main", s["calls"])] + [("subagent", a["calls"]) for a in s["subagents"]]:
            for c in calls:
                if not c.get("cause"):
                    continue
                e = out.setdefault(f"{who}:{c['cause']}", {"usd": 0.0, "tokens": 0, "calls": 0})
                e["usd"] += c["wusd"]
                e["tokens"] += c["w5"] + c["w1"]
                e["calls"] += 1
    total = sum(e["usd"] for e in out.values())
    rows = {k: {"usd": r2(e["usd"]), "share": round(e["usd"] / total, 3) if total else 0,
                "tokens": e["tokens"], "calls": e["calls"]}
            for k, e in sorted(out.items(), key=lambda kv: -kv[1]["usd"])}
    return {"basis": "transcripts", "definitions": definitions, "total_usd": r2(total), "by_cause": rows}


def compactions(sessions, responses_rule):
    n = sum(len(s["compactions"]) for s in sessions)
    resp = sum(len(s["calls"]) for s in sessions)
    return {"responses": responses_rule, "main_compactions": n, "main_responses": resp,
            "per_100_responses": round(100 * n / resp, 3) if resp else None,
            "sessions_with_compaction": sum(1 for s in sessions if s["compactions"]),
            "subagent_compactions": sum(a["compactions"] for s in sessions for a in s["subagents"]),
            "subagent_responses": sum(len(a["calls"]) for s in sessions for a in s["subagents"])}


def coordinator_reads(sessions, programs):
    files, shell = {}, {}
    for s in sessions:
        for p in s["reads"]:
            if p == "?":
                continue
            f = files.setdefault(p, {"reads": 0, "sessions": set()})
            f["reads"] += 1
            f["sessions"].add(s["session_id"])
        for p, n in s["shell"].items():
            if p in programs:
                add(shell, p, n)
    top = sorted(files.items(), key=lambda kv: (-kv[1]["reads"], kv[0]))[:TOP_FILES]
    per = [s["coordinator_reads"] for s in sessions]
    return {"programs": sorted(programs), "total": sum(per), "file_reads": sum(len(s["reads"]) for s in sessions),
            "shell_reads": by_value(shell, 0), "per_session": percentiles(per),
            "top_files": [{"path": p, "reads": f["reads"], "sessions": len(f["sessions"])} for p, f in top]}


def per_run(e):
    return round(e["usd"] / e["runs"], 3) if e["runs"] else None


def reviews(sessions):
    rows = {}
    for s in sessions:
        for a in s["subagents"]:
            role = role_of(a["type"])
            if role not in REVIEW_ROLES and "review" not in role:
                continue
            e = rows.setdefault((role, a["model"] or "?"), {"runs": 0, "usd": 0.0, "transcript_usd": 0.0})
            e["runs"] += 1
            e["usd"] += a["usd"]
            e["transcript_usd"] += a["transcript_usd"]
    by_role = {}
    for (role, _), e in rows.items():
        t = by_role.setdefault(role, {"runs": 0, "usd": 0.0})
        t["runs"] += e["runs"]
        t["usd"] += e["usd"]
    return {"by_role": {k: {"runs": v["runs"], "usd": r2(v["usd"]), "usd_per_run": per_run(v)}
                        for k, v in sorted(by_role.items())},
            "by_role_model": [{"role": r, "model": m, "runs": e["runs"], "usd": r2(e["usd"]),
                               "usd_per_run": per_run(e), "transcript_usd": r2(e["transcript_usd"])}
                              for (r, m), e in sorted(rows.items())],
            "usd": r2(sum(e["usd"] for e in rows.values())),
            "runs": sum(e["runs"] for e in rows.values())}


def delegation(sessions):
    out = {}
    for k in ("self-implemented", "delegated", "neither"):
        ss = [s for s in sessions if kind_of(s) == k]
        out[k] = {"sessions": len(ss), "usd": r2(sum(s["usd"] for s in ss)),
                  "median_usd": r2(statistics.median([s["usd"] for s in ss])) if ss else None,
                  "compactions_per_session": round(sum(len(s["compactions"]) for s in ss) / len(ss), 2) if ss else None,
                  "median_coordinator_reads": statistics.median([s["coordinator_reads"] for s in ss]) if ss else None}
    out["self-implemented"]["also_delegated"] = sum(
        1 for s in sessions if kind_of(s) == "self-implemented"
        and any(role_of(a["type"]) == "implementer" for a in s["subagents"]))
    return out


def rates(window, total, by_role, review_usd):
    days = (dt.date.fromisoformat(window["until"]) - dt.date.fromisoformat(window["since"])).days + 1
    f = 7 / days if days > 0 else 0
    return {"window_days": days,
            "per_7_days": {"usd": r2(total * f), "review_usd": r2(review_usd * f),
                           "by_role": {k: r2(v * f) for k, v in by_role.items()}}}


def epoch(t):
    return dt.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()


def common(items):
    counts = {}
    for x in items:
        counts[x] = counts.get(x, 0) + 1
    return max(sorted(counts), key=counts.get) if counts else "?"


def units_of(s):
    """(who, role, unit id, unit dict) for the main session and each subagent."""
    yield "main", "coordinator", s["session_id"], s
    for a in s["subagents"]:
        yield "subagent", role_of(a["type"]), a["id"], a


def effort_of(u):
    return u.get("effort") or common([c.get("e", "unknown") for c in u["calls"]]) if u["calls"] else "unknown"


def role_model_effort(sessions):
    runs, calls = {}, {}
    for s in sessions:
        for who, role, _, u in units_of(s):
            if not u["calls"]:
                continue
            model = common([c["m"] for c in u["calls"]])
            e = runs.setdefault((role, model, effort_of(u)), {"runs": 0, "usd": 0.0})
            e["runs"] += 1
            e["usd"] += u["main_usd"] if who == "main" else u["usd"]
            for c in u["calls"]:
                k = calls.setdefault((role, c["m"], c.get("e", "unknown")), {"calls": 0, "usd": 0.0})
                k["calls"] += 1
                k["usd"] += c["usd"]
    row = lambda k, e, n: {"role": k[0], "model": k[1], "effort": k[2], n: e[n], "usd": r2(e["usd"])}
    return {"basis": "by_run: runs by the model and effort most of their calls used, cost as the basis "
                     "cost of the main session (its own share) or subagent; by_call: every call at its own "
                     "model and effort, transcript cost",
            "by_run": [row(k, e, "runs") for k, e in sorted(runs.items(), key=lambda kv: -kv[1]["usd"])],
            "by_call": [row(k, e, "calls") for k, e in sorted(calls.items(), key=lambda kv: -kv[1]["usd"])]}


def idle_rebuilds(sessions, rate_window):
    main_calls = sorted((epoch(c["t"]), s["session_id"]) for s in sessions for c in s["calls"] if c["t"])
    times = [t for t, _ in main_calls]
    events = []
    for s in sessions:
        for who, role, uid, u in units_of(s):
            for c in u["calls"]:
                if c.get("cause") != "idle" or not c["t"]:
                    continue
                t = epoch(c["t"])
                lo = bisect.bisect_left(times, t - ACTIVE_WINDOW)
                hi = bisect.bisect_right(times, t)
                others = {sid for _, sid in main_calls[lo:hi] if sid != s["session_id"]}
                events.append({"session": s["session_id"], "project": s["project_name"], "unit": uid,
                               "who": who, "role": role, "t": c["t"], "gap_s": c.get("gap"),
                               "tokens": c["w5"] + c["w1"], "usd": c["wusd"], "model": c["m"],
                               "effort": c.get("e", "unknown"), "other_main_sessions_active": len(others)})
    total_spend = sum(s["usd"] for s in sessions)
    usd = sum(e["usd"] for e in events)
    f = rate_window
    by_gap = {label: {"events": 0, "usd": 0.0, "tokens": 0} for _, label in GAP_BUCKETS}
    by_role, by_active = {}, {k: {"events": 0, "usd": 0.0} for k in ACTIVE_BUCKETS}
    for e in events:
        g = by_gap[band(e["gap_s"] or 0, GAP_BUCKETS)]
        g["events"] += 1
        g["usd"] += e["usd"]
        g["tokens"] += e["tokens"]
        k = by_role.setdefault(f"{e['who']}:{e['role']}", {"events": 0, "usd": 0.0, "tokens": 0})
        k["events"] += 1
        k["usd"] += e["usd"]
        k["tokens"] += e["tokens"]
        a = by_active["3+" if e["other_main_sessions_active"] >= 3 else str(e["other_main_sessions_active"])]
        a["events"] += 1
        a["usd"] += e["usd"]
    long_sessions = []
    for s in sessions:
        ts = [epoch(c["t"]) for c in s["calls"] if c["t"]]
        if not ts or max(ts) - min(ts) <= LONG_SESSION:
            continue
        ev = [e for e in events if e["session"] == s["session_id"]]
        long_sessions.append({
            "session": s["session_id"], "project": s["project_name"],
            "span_hours": round((max(ts) - min(ts)) / 3600, 1), "session_usd": r2(s["usd"]),
            "rebuilds": len(ev), "main_rebuilds": sum(1 for e in ev if e["who"] == "main"),
            "rebuild_usd": r2(sum(e["usd"] for e in ev)),
            "share_of_session": round(sum(e["usd"] for e in ev) / s["usd"], 3) if s["usd"] else None})
    long_sessions.sort(key=lambda x: -x["rebuild_usd"])
    resumed = [e for e in events if e["who"] == "subagent" and (e["gap_s"] or 0) > RESUME_TTL]
    return {
        "basis": "calls with cause idle; cost is the cache-write cost of the call (wusd); main sessions "
                 "1h cache lifetime, subagents 5 min",
        "events": len(events), "tokens": sum(e["tokens"] for e in events), "usd": r2(usd),
        "share_of_spend": round(usd / total_spend, 4) if total_spend else None,
        "per_7_days_usd": r2(usd * f), "spend_per_7_days_usd": r2(total_spend * f),
        "by_gap": {k: {"events": v["events"], "usd": r2(v["usd"]), "tokens": v["tokens"]} for k, v in by_gap.items()},
        "by_role": {k: {"events": v["events"], "usd": r2(v["usd"]), "tokens": v["tokens"]}
                    for k, v in sorted(by_role.items(), key=lambda kv: -kv[1]["usd"])},
        "by_other_main_sessions_active": {
            k: {"events": v["events"], "usd": r2(v["usd"]),
                "avg_usd": round(v["usd"] / v["events"], 4) if v["events"] else None}
            for k, v in by_active.items()},
        "active_rule": f"distinct other main sessions with a call in the {ACTIVE_WINDOW}s before the event, "
                       "across every session in the scan",
        "long_main_sessions": long_sessions,
        "long_session_rule": f"main-session wall span first to last call over {LONG_SESSION // 3600}h; "
                             "rebuilds count the session's main and subagent events",
        "subagent_resumed_after_5min": {
            "events": len(resumed), "usd": r2(sum(e["usd"] for e in resumed)),
            "rule": f"subagent idle events with a gap over {RESUME_TTL}s; the subagent cache lifetime is "
                    f"{RESUME_TTL}s, so every subagent idle event qualifies"},
        "event_rows": sorted(events, key=lambda e: -e["usd"])}


def compaction_log(sessions):
    rows = []
    for s in sessions:
        for c in s["compactions"]:
            rows.append({"session": s["session_id"], "project": s["project_name"], "t": c["t"],
                         "trigger": c["trigger"], "pre": c["pre"], "post": c["post"],
                         "next_call_usd": c.get("next_usd"), "next_call_cache_write_usd": c.get("next_wusd")})
    rows.sort(key=lambda x: x["t"] or "")
    known = [x["next_call_usd"] for x in rows if x["next_call_usd"] is not None]
    return {"count": len(rows), "next_call_usd": r2(sum(known)), "rows": rows}


def start_split(sessions):
    have = [s for s in sessions if s["calls"] and "start_sources" in s]
    if not have:
        return {"sessions": 0, "note": "the scan has no start_sources (older scan or no main session)"}
    tot, sources = 0, {}
    for s in have:
        tot += ctx(s["calls"][0])
        for k, v in s["start_sources"].items():
            sources[k] = sources.get(k, 0) + v
    known = sum(sources.values())
    n = len(have)
    rows = {k: {"tokens": v, "per_session": v // n, "share": round(v / tot, 3) if tot else None}
            for k, v in sorted(sources.items(), key=lambda kv: -kv[1])}
    return {
        "sessions": n, "estimate": "characters / 4 of the lines recorded before the first call; sizes only",
        "first_call_context_tokens": tot, "first_call_context_per_session": tot // n,
        "by_source": rows,
        "not_split": {"tokens": tot - known, "per_session": (tot - known) // n,
                      "share": round((tot - known) / tot, 3) if tot else None,
                      "note": "remainder of the first call's context: tool definitions are not in the "
                              "transcript, the system prompt only as recorded, estimate error, and for a "
                              "resumed session the earlier conversation; these cannot be separated"}}


def report(doc):
    sessions = doc["sessions"]
    rules = doc.get("rules", {})
    reported = [s["cost_state"]["total_cost_usd"] for s in sessions
                if s.get("cost_state") and s["cost_state"].get("total_cost_usd") is not None]
    sp = spend(sessions, doc["window"])
    rv = reviews(sessions)
    total = sum(s["usd"] for s in sessions)
    return {
        "schema": 1, "source": doc.get("source"),
        "prices": {k: doc["prices"].get(k) for k in ("date", "source")},
        "window": doc["window"],
        "totals": {
            "sessions": len(sessions),
            "usd": r2(total),
            "transcript_usd": r2(sum(s["transcript_usd"] for s in sessions)),
            "reported_usd": r2(sum(reported)), "reported_sessions": len(reported),
            "basis": {b: sum(1 for s in sessions if s["basis"] == b) for b in sorted({s["basis"] for s in sessions})},
            "tail_usd": r2(sum(s.get("tail_usd", 0) for s in sessions)),
            "untracked_usd": r2(sum(s["untracked_usd"] for s in sessions)),
            "unpriced_models": sorted({m for s in sessions for m in s["unpriced_models"]}),
            "subagent_runs": sum(len(s["subagents"]) for s in sessions),
        },
        "rates": rates(doc["window"], total, sp["by_role"], rv["usd"]),
        "spend": sp,
        "top_sessions": [facts(s) for s in sorted(sessions, key=lambda s: -s["usd"])[:TOP]],
        "start_context": start_context(sessions),
        "context_spend": context_spend(sessions),
        "cache_writes": cache_writes(sessions, rules.get("cache_write_causes", {})),
        "compactions": compactions(sessions, rules.get("responses", "API calls of main sessions")),
        "coordinator_reads": coordinator_reads(sessions, set(rules.get("coordinator_read_programs", []))),
        "reviews": rv,
        "delegation": delegation(sessions),
        "role_model_effort": role_model_effort(sessions),
        "idle_rebuilds": idle_rebuilds(sessions, 7 / rates(doc["window"], 0, {}, 0)["window_days"]),
        "compaction_log": compaction_log(sessions),
        "start_split": start_split(sessions),
    }


def money(v):
    return f"${v:,.2f}"


def text(r):
    t, w, sp = r["totals"], r["window"], r["spend"]
    rt = r["rates"]
    lines = [
        f"Window {w['since']}..{w['until']} ({w['tz']}, {rt['window_days']} days); prices {r['prices']['source']}",
        f"Sessions {t['sessions']} ({', '.join(f'{k} {v}' for k, v in t['basis'].items())}); "
        f"cost {money(t['usd'])}, reported {money(t['reported_usd'])}, transcripts {money(t['transcript_usd'])}; "
        f"per 7 days {money(rt['per_7_days']['usd'])}",
    ]
    if t["unpriced_models"]:
        lines.append("Not priced: " + ", ".join(t["unpriced_models"]))
    lines.append("By day (main + subagents): " + "; ".join(
        f"{d} {money(v['usd'])} ({money(v['main'])} + {money(v['subagents'])}){' after window' if v.get('after_window') else ''}"
        for d, v in sp["by_day"].items()))
    for k in ("by_model", "by_project", "by_role"):
        lines.append(f"{k.replace('_', ' ').capitalize()}: " + "; ".join(
            f"{n} {money(v)}" for n, v in list(sp[k].items())[:10]))
    lines.append("Session cost bands: " + "; ".join(f"{k} {v['sessions']} ({money(v['usd'])})"
                                                    for k, v in sp["cost_bands"].items()))
    lines.append("Top sessions:")
    for s in r["top_sessions"]:
        subs = ", ".join(f"{role_of(k)} {v['runs']} {money(v['usd'])}" for k, v in s["subagents"].items())
        lines.append(f"  {s['session_id'][:8]} {s['project']} {s['start_local']} {money(s['usd'])} "
                     f"(main {money(s['main_usd'])}, subagents {money(s['subagent_usd'])}), {s['kind']}: "
                     f"{s['responses']} responses, {s['compactions']} compactions, peak {s['peak_context'] // 1000}k, "
                     f"{s['coordinator_reads']} reads, {s['self_edits']} self-edits; {subs or 'no subagents'}")
    sc = r["start_context"]
    if sc["n"]:
        lines.append(f"Start context: median {sc['median'] / 1000:.0f}k (p10 {sc['p10'] / 1000:.0f}k, "
                     f"p90 {sc['p90'] / 1000:.0f}k), n {sc['n']}; by project: " + "; ".join(
                         f"{p} {v['median'] / 1000:.0f}k ({v['sessions']})" for p, v in list(sc["by_project"].items())[:8]))
    lines.append("Main-call spend by context: " + "; ".join(
        f"{k} {money(v['usd'])}" for k, v in r["context_spend"]["by_context"].items()))
    cw = r["cache_writes"]
    lines.append(f"Cache writes {money(cw['total_usd'])}: " + "; ".join(
        f"{k} {money(v['usd'])}" for k, v in cw["by_cause"].items()))
    c = r["compactions"]
    lines.append(f"Compactions {c['main_compactions']} per {c['main_responses']} main responses "
                 f"({c['per_100_responses']} per 100)")
    cr = r["coordinator_reads"]
    lines.append(f"Coordinator reads {cr['total']} (median {cr['per_session'].get('median')} per session); top: "
                 + "; ".join(f"{f['path']} {f['reads']}x/{f['sessions']}s" for f in cr["top_files"][:5]))
    lines.append(f"Reviews {money(r['reviews']['usd'])} (per 7 days {money(rt['per_7_days']['review_usd'])}): "
                 + "; ".join(f"{k} {v['runs']} runs {money(v['usd'])} ({money(v['usd_per_run'] or 0)}/run)"
                             for k, v in r["reviews"]["by_role"].items()))
    lines.append("P2b: " + "; ".join(f"{k} {v['sessions']} ({money(v['usd'])}, median {money(v['median_usd'] or 0)})"
                                      for k, v in r["delegation"].items()))
    lines += text_added(r)
    return "\n".join(lines) + "\n"


def text_added(r):
    L = []
    L.append("Cost by role x model x effort (by run: runs, cost; top 12):")
    for x in r["role_model_effort"]["by_run"][:12]:
        L.append(f"  {x['role']} / {x['model']} / {x['effort']}: {x['runs']} runs, {money(x['usd'])}")
    L.append("  by call (top 8): " + "; ".join(
        f"{x['role']}/{x['model']}/{x['effort']} {x['calls']} calls {money(x['usd'])}"
        for x in r["role_model_effort"]["by_call"][:8]))
    ir = r["idle_rebuilds"]
    L.append(f"Idle cache rebuilds: {ir['events']} events, {ir['tokens']:,} tokens, {money(ir['usd'])} = "
             f"{100 * (ir['share_of_spend'] or 0):.1f}% of spend (per 7 days {money(ir['per_7_days_usd'])} of "
             f"{money(ir['spend_per_7_days_usd'])})")
    L.append("  by gap: " + "; ".join(f"{k} {v['events']} ({money(v['usd'])})" for k, v in ir["by_gap"].items()))
    L.append("  by role: " + "; ".join(f"{k} {v['events']} ({money(v['usd'])})" for k, v in ir["by_role"].items()))
    L.append("  by other main sessions active in the previous hour: " + "; ".join(
        f"{k}: {v['events']} events, {money(v['usd'])}, avg {money(v['avg_usd'] or 0)}"
        for k, v in ir["by_other_main_sessions_active"].items()))
    sr = ir["subagent_resumed_after_5min"]
    L.append(f"  subagents resumed after 5 min (gap over {RESUME_TTL}s): {sr['events']} events, {money(sr['usd'])}")
    L.append(f"  long-running main sessions (span over {LONG_SESSION // 3600}h): {len(ir['long_main_sessions'])}")
    for x in ir["long_main_sessions"][:10]:
        L.append(f"    {x['session'][:8]} {x['project']} {x['span_hours']}h: {x['rebuilds']} rebuilds "
                 f"({x['main_rebuilds']} main), {money(x['rebuild_usd'])} = "
                 f"{100 * (x['share_of_session'] or 0):.0f}% of its {money(x['session_usd'])}")
    L.append(f"  top {TOP_EVENTS} events by cost:")
    for e in ir["event_rows"][:TOP_EVENTS]:
        L.append(f"    {e['session'][:8]} {e['who']} {e['role']} {e['t']} gap {(e['gap_s'] or 0) / 3600:.1f}h "
                 f"{e['tokens']:,} tokens {money(e['usd'])}, {e['other_main_sessions_active']} other main active")
    cl = r["compaction_log"]
    L.append(f"Compaction log: {cl['count']} compactions, next-call cost {money(cl['next_call_usd'])}")
    for x in cl["rows"][:15]:
        nxt = money(x["next_call_usd"]) if x["next_call_usd"] is not None else "no call after"
        L.append(f"    {x['session'][:8]} {x['t']} {x['trigger']} pre {x['pre']} post {x['post']} next call {nxt}")
    sp = r["start_split"]
    if not sp["sessions"]:
        L.append("Starting context split: " + sp["note"])
    else:
        L.append(f"Starting context split ({sp['sessions']} main sessions, first call mean "
                 f"{sp['first_call_context_per_session']:,} tokens; sources are {sp['estimate']}):")
        for k, v in sp["by_source"].items():
            L.append(f"    {k}: ~{v['per_session']:,} tokens/session ({100 * (v['share'] or 0):.1f}%)")
        ns = sp["not_split"]
        L.append(f"    not split: remainder ~{ns['per_session']:,} tokens/session ({100 * (ns['share'] or 0):.1f}%); "
                 + ns["note"])
    return L


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("scan")
    ap.add_argument("--out")
    ap.add_argument("--text", action="store_true")
    a = ap.parse_args()
    with open(a.scan, encoding="utf-8") as fh:
        doc = json.load(fh)
    if doc.get("schema") != 1:
        sys.exit(f"error: unsupported scan schema {doc.get('schema')!r}")
    r = report(doc)
    js = json.dumps(r, indent=1) + "\n"
    if a.out:
        with open(a.out, "w", encoding="utf-8") as fh:
            fh.write(js)
    else:
        sys.stdout.write(js)
    if a.text:
        (sys.stdout if a.out else sys.stderr).write(text(r))


if __name__ == "__main__":
    main()
