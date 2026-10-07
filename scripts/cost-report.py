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
Spend uses each session's basis cost (scan field "usd"); by day, the main
session's share and each subagent's are spread over days by their
transcript cost per day.
"""
import argparse
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
    return "\n".join(lines) + "\n"


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
