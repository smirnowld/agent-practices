#!/bin/sh
# Offline self-test for the cost-review scripts: the Claude Code scanner
# (adapters/claude/cost-scan.py) and the report (scripts/cost-report.py) on a
# synthetic projects root. Checks the counting rules (window by Tallinn day,
# last line per message id, <synthetic> excluded, cost-state basis with
# subagent output from it, transcript basis without it, cache-write causes,
# compactions, coordinator reads, reviews, P2b kinds, fast mode, US
# inference, a [1m] cost-state key, a workflow subagent, calls after the
# cost-state line, an unpriced model, days after the window), that the scanner
# stops on a format it does not know, and that a phrase planted in message
# text, tool input and output, agent descriptions, agent types and a title
# never reaches either output. HOME is set so project names do not depend on
# the machine.
set -eu
dir=$(dirname "$0")
fixture="$dir/../adapters/claude/fixtures/cost-review/projects"
phrase="PLANTED ZEBRA PHRASE"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

grep -rqF "$phrase" "$fixture" || { echo "error: fixture lacks the planted phrase" >&2; exit 1; }
scan() {
  HOME=/Users/test python3 "$dir/../adapters/claude/cost-scan.py" --since 2026-09-29 --until 2026-10-01 \
    --tz Europe/Tallinn --projects-root "$@"
}
scan "$fixture" --out "$tmp/scan.json"
python3 "$dir/cost-report.py" "$tmp/scan.json" --out "$tmp/report.json" --text > "$tmp/report.txt"

for f in scan.json report.json report.txt; do
  if grep -qiF "zebra" "$tmp/$f"; then
    echo "error: planted phrase in $f" >&2; exit 1
  fi
done

# A format the scanner does not know must stop it: no cost-state line in any
# session, or no assistant line with usage.
for case in no-cost-state no-usage; do
  cp -R "$fixture" "$tmp/$case"
  find "$tmp/$case" -name '*.jsonl' | while read -r f; do
    if [ "$case" = no-cost-state ]; then
      grep -v '"cost-state"' "$f" > "$f.new" || true
    else
      sed 's/"usage"/"usage_renamed"/g' "$f" > "$f.new"
    fi
    mv "$f.new" "$f"
  done
  if scan "$tmp/$case" --out "$tmp/$case.json" 2> "$tmp/$case.err"; then
    echo "error: scanner accepted the $case fixture" >&2; exit 1
  fi
done
# Open sessions have no cost-state line yet: a window reaching today must not stop.
HOME=/Users/test python3 "$dir/../adapters/claude/cost-scan.py" --since 2026-09-29 --until 2099-12-31 \
  --tz Europe/Tallinn --projects-root "$tmp/no-cost-state" --out "$tmp/open.json" || {
  echo "error: scanner stopped on a window that reaches today" >&2; exit 1; }

python3 - "$tmp/scan.json" "$tmp/report.json" <<'EOF'
import json, sys
scan = json.load(open(sys.argv[1]))
rep = json.load(open(sys.argv[2]))
fails = []
def eq(what, got, want, tol=1e-6):
    ok = abs(got - want) <= tol if isinstance(want, float) else got == want
    if not ok:
        fails.append(f"{what}: got {got!r}, want {want!r}")

ss = {s["session_id"][:1]: s for s in scan["sessions"]}
eq("sessions in window (d, e outside)", sorted(ss), ["a", "b", "c", "f"])
eq("price source", scan["prices"]["source"],
   "https://platform.claude.com/docs/en/about-claude/pricing, checked 2026-10-07")
eq("time zone", scan["window"]["tz"], "Europe/Tallinn")
eq("cache-write causes defined", sorted(scan["rules"]["cache_write_causes"]),
   ["compaction", "growth", "idle", "miss", "start"])
a, b, c, f = ss["a"], ss["b"], ss["c"], ss["f"]
eq("a calls (repeat id once, synthetic out)", len(a["calls"]), 5)
eq("a first call keeps last line", a["calls"][0]["out"], 100)
eq("a causes", [x.get("cause") for x in a["calls"]], ["start", "growth", "growth", "compaction", "idle"])
eq("a subagent causes", [x.get("cause") for x in a["subagents"][0]["calls"]], ["start", "idle"])
eq("a basis", a["basis"], "cost-state")
eq("a transcript usd", a["transcript_usd"], 0.918552)
eq("a usd from last cost-state", a["usd"], 0.964052)
eq("a untracked (model without transcript calls)", a["untracked_usd"], 0.0015)
eq("reviewer usd (output from cost-state)", a["subagents"][0]["usd"], 0.190032)
eq("reviewer transcript usd", a["subagents"][0]["transcript_usd"], 0.150032)
eq("b basis", b["basis"], "transcript")
eq("b usd", b["usd"], 0.251)
csub = {x["id"]: x for x in c["subagents"]}
eq("c implementer usd", csub["agent-i1"]["usd"], 0.105018)
eq("c background subagent before the cost-state line is not tail",
   (c["basis"], [x.get("tail") for x in csub["agent-b1"]["calls"]]), ("cost-state", [None]))
eq("c main usd", c["main_usd"], 0.49906)
eq("c main by day (call after the window)", c["days_main"], {"2026-10-01": 0.48204, "2026-10-02": 0.01702})
eq("project names (cwd, worktree, folder fallback)",
   [s["project_name"] for s in (a, b, f)], ["code-alpha", "code-beta", "gamma"])
# f: fast mode, US inference, mixed writes, a miss, an unpriced model, a
# [1m] cost-state key, a workflow subagent, a call after the cost-state line.
eq("f multipliers", [x.get("x") for x in f["calls"]], [2.0, 1.1, None, None, None, None, None])
eq("f fast call usd", f["calls"][0]["usd"], 0.64408)
eq("f US call usd", f["calls"][1]["usd"], 0.018722)
eq("f mixed 5m/1h call", (f["calls"][2]["w5"], f["calls"][2]["w1"], f["calls"][2]["wusd"]), (2000, 3000, 0.034))
eq("f causes", [x.get("cause") for x in f["calls"]],
   ["start", "growth", "growth", "miss", "growth", "growth", "growth"])
eq("f unpriced", (f["calls"][4].get("np"), f["unpriced_models"]), (1, ["claude-mystery-9"]))
eq("f [1m] key folded into the model", sorted(f["models"]),
   ["claude-mystery-9", "claude-opus-5-5", "claude-sonnet-5-5"])
eq("f tail call", [x.get("tail") for x in f["calls"]], [None] * 6 + [1])
eq("f basis", f["basis"], "cost-state+tail")
fsub = {x["id"]: x for x in f["subagents"]}
eq("f subagent tail only after the resume", [x.get("tail") for x in fsub["agent-g1"]["calls"]], [None, 1])
eq("f tail usd", f["tail_usd"], 0.027986)
eq("f usd", f["usd"], 1.261038)
w = fsub["agent-w1"]
eq("workflow subagent", (w["id"], w.get("kind"), w["type"]), ("agent-w1", "workflow", "?"))
eq("workflow causes (TTL from the last write type)", [x.get("cause") for x in w["calls"]],
   ["start", "growth", "growth", "idle"])
eq("f edits (MultiEdit; a path with a newline hidden)", f["edits"],
   [{"tool": "MultiEdit", "path": "/repo/y.py"}, {"tool": "Edit", "path": "?"}])
eq("f reads (not a path)", f["reads"], ["?"])
eq("f shell (programs off the allowlist)", f["shell"], {"other": 2})
eq("f spawn type without a run", f["spawns"], [{"type": "other", "model": None}])

t = rep["totals"]
eq("report sessions", t["sessions"], 4)
eq("report usd", t["usd"], 3.11)
eq("report transcript usd", t["transcript_usd"], 3.05)
eq("basis counts", t["basis"], {"cost-state": 2, "cost-state+tail": 1, "transcript": 1})
eq("unpriced models", t["unpriced_models"], ["claude-mystery-9"])
sp = rep["spend"]
eq("by day", sp["by_day"], {
    "2026-09-29": {"usd": 0.96, "main": 0.77, "subagents": 0.19},
    "2026-09-30": {"usd": 1.51, "main": 1.36, "subagents": 0.15},
    "2026-10-01": {"usd": 0.59, "main": 0.48, "subagents": 0.11},
    "2026-10-02": {"usd": 0.04, "main": 0.02, "subagents": 0.03, "after_window": True}})
eq("after window", sp["after_window_usd"], 0.04)
eq("by role", sp["by_role"], {"main": 2.63, "agent-practices:critical-reviewer": 0.19, "?": 0.15,
                              "agent-practices:implementer": 0.11, "agent-practices:explorer": 0.04,
                              "untracked": 0.0})
eq("by project", sp["by_project"], {"code-alpha": 1.6, "gamma": 1.26, "code-beta": 0.25})
eq("cost bands", [sp["cost_bands"][k]["sessions"] for k in sp["cost_bands"]], [3, 1, 0, 0, 0])
eq("rates", (rep["rates"]["window_days"], rep["rates"]["per_7_days"]["usd"]), (3, 7.26))
eq("start context median", rep["start_context"]["median"], 45010.0)
eq("start context by project", rep["start_context"]["by_project"]["code-alpha"], {"sessions": 2, "median": 55010.0})
eq("context spend 50-75k", rep["context_spend"]["by_context"]["50-75k"], {"calls": 5, "usd": 0.94})
top = rep["top_sessions"][0]
eq("top session", (top["session_id"][:1], top["kind"], top["start_local"], top["subagents"]),
   ("f", "self-implemented", "2026-09-30T11:00+03:00", {"?": {"runs": 1, "usd": 0.15}, "agent-practices:explorer": {"runs": 1, "usd": 0.01}}))
eq("a peak context", [x for x in rep["top_sessions"] if x["session_id"][:1] == "a"][0]["peak_context"], 51505)
cw = rep["cache_writes"]["by_cause"]
eq("cache write main start", cw["main:start"]["usd"], 1.72)
eq("cache write causes", sorted(cw), ["main:compaction", "main:growth", "main:idle", "main:miss", "main:start",
                                      "subagent:growth", "subagent:idle", "subagent:start"])
eq("cache write definitions", sorted(rep["cache_writes"]["definitions"]),
   ["compaction", "growth", "idle", "miss", "start"])
eq("compactions per 100", rep["compactions"]["per_100_responses"], 6.667)
cr = rep["coordinator_reads"]
eq("coordinator reads", cr["total"], 4)
eq("shell reads", cr["shell_reads"], {"cat": 1, "grep": 1})
eq("reviews", rep["reviews"]["by_role"], {"critical-reviewer": {"runs": 1, "usd": 0.19, "usd_per_run": 0.19}})
d = rep["delegation"]
eq("p2b", [d[k]["sessions"] for k in ("self-implemented", "delegated", "neither")], [2, 1, 1])
if fails:
    sys.exit("error: " + "\n  ".join(fails))
EOF
echo "cost-review self-test passed"
