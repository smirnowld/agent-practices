#!/usr/bin/env python3
"""Per day: merged pull requests, active main sessions and idle-rebuild cost.

Usage: cost-throughput.py SCAN.json --repo OWNER/NAME [--repo ...] [--out PATH] [--text]

Reads a cost-scan JSON document (schema 1; for Claude Code,
adapters/claude/cost-scan.py) and, for each day of its window in the scan's
zone, counts the pull requests merged that day in each repository (one
`gh pr list --state merged --search "merged:DAY..DAY"` call per repository and
day; GitHub reads the search dates as UTC days), the distinct main sessions
with an API call that day, and the cache-write cost of the calls with cause
"idle" (main sessions and subagents) that day. Writes JSON (stdout, or --out);
with --text also prints a table (stdout, or stderr when the JSON goes to
stdout). The gh command is $COST_THROUGHPUT_GH (default: gh), which the
self-test replaces with a stub. A repository whose query fails counts as
unknown for the day (null), not zero.

Only sessions that started inside the scan's window are in the scan, so a day
can show merged PRs and no sessions when the work ran in older sessions.

No repositories are built in: pass each as OWNER/NAME. Output has counts and
dollar amounts only, never titles or branch names.
"""
import argparse
import datetime as dt
import json
import os
import shlex
import subprocess
import sys
from zoneinfo import ZoneInfo

LIMIT = 200


def merged_on(gh, repo, day):
    """Number of PRs merged on DAY (UTC) in REPO, or None when gh fails."""
    cmd = gh + ["pr", "list", "--repo", repo, "--state", "merged", "--search", f"merged:{day}..{day}",
                "--json", "number,mergedAt", "--limit", str(LIMIT)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if out.returncode:
            return None
        rows = json.loads(out.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    return len(rows) if isinstance(rows, list) else None


def local_day(t, tz):
    return dt.datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone(tz).date().isoformat()


def throughput(doc, repos, gh):
    w = doc["window"]
    tz = ZoneInfo(w["tz"])
    since, until = dt.date.fromisoformat(w["since"]), dt.date.fromisoformat(w["until"])
    days = {}
    d = since
    while d <= until:
        days[d.isoformat()] = {"merged": {}, "active_main_sessions": set(),
                               "idle_rebuild_usd": 0.0, "idle_rebuild_usd_main": 0.0}
        d += dt.timedelta(days=1)
    for s in doc["sessions"]:
        for who, calls in [("main", s["calls"])] + [("subagent", a["calls"]) for a in s["subagents"]]:
            for c in calls:
                if not c.get("t"):
                    continue
                row = days.get(local_day(c["t"], tz))
                if row is None:
                    continue
                if who == "main":
                    row["active_main_sessions"].add(s["session_id"])
                if c.get("cause") == "idle":
                    row["idle_rebuild_usd"] += c["wusd"]
                    if who == "main":
                        row["idle_rebuild_usd_main"] += c["wusd"]
    for day, row in days.items():
        for repo in repos:
            row["merged"][repo] = merged_on(gh, repo, day)
    out = {"schema": 1, "window": w, "repos": repos,
           "note": "merged PRs by UTC day (GitHub search); sessions and cost by day in the scan's zone",
           "days": {}}
    for day, row in days.items():
        known = [v for v in row["merged"].values() if v is not None]
        out["days"][day] = {
            "merged_prs": sum(known) if known else None, "merged_by_repo": row["merged"],
            "active_main_sessions": len(row["active_main_sessions"]),
            "idle_rebuild_usd": round(row["idle_rebuild_usd"], 2),
            "idle_rebuild_usd_main": round(row["idle_rebuild_usd_main"], 2)}
    return out


def text(r):
    L = [f"{'day':<11}{'merged PRs':>11}{'main sessions':>15}{'idle rebuild':>14}"]
    for day, v in r["days"].items():
        m = "?" if v["merged_prs"] is None else str(v["merged_prs"])
        if any(x is None for x in v["merged_by_repo"].values()):
            m += "*"
        L.append(f"{day:<11}{m:>11}{v['active_main_sessions']:>15}{'$' + format(v['idle_rebuild_usd'], ',.2f'):>14}")
    L.append("* a repository's query failed; the count leaves it out. " + r["note"])
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("scan")
    ap.add_argument("--repo", action="append", required=True, metavar="OWNER/NAME")
    ap.add_argument("--out")
    ap.add_argument("--text", action="store_true")
    a = ap.parse_args()
    with open(a.scan, encoding="utf-8") as fh:
        doc = json.load(fh)
    if doc.get("schema") != 1:
        sys.exit(f"error: unsupported scan schema {doc.get('schema')!r}")
    r = throughput(doc, a.repo, shlex.split(os.environ.get("COST_THROUGHPUT_GH", "gh")))
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
