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
# never reaches either output; the added measures (effort, idle rebuilds,
# compaction cost, start-context sources, Haiku 5.5 long-prompt pricing) and
# scripts/cost-throughput.py with a stubbed gh. HOME is set so project names do not depend on
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

python3 - "$tmp/scan.json" "$tmp/report.json" "$dir/cost-report.py" "$dir/../adapters/claude/cost-scan.py" <<'EOF'
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
# Effort, idle gaps, compaction cost, start-context sources (scanner).
eq("a effort per call", [x["e"] for x in a["calls"]], ["medium"] * 3 + ["high"] * 2)
eq("a effort most common", (a["effort"], a["subagents"][0]["effort"]), ("medium", "high"))
eq("c efforts", (c["effort"], {x["id"]: x["effort"] for x in c["subagents"]}),
   ("xhigh", {"agent-b1": "unknown", "agent-i1": "low"}))
eq("f effort (one max call of seven, others unrecorded)", ([x["e"] for x in f["calls"]][:2], f["effort"]),
   (["max", "unknown"], "unknown"))
eq("idle gaps (seconds)", [x.get("gap") for x in a["calls"]], [None] * 4 + [6540])
eq("c main idle gap", c["calls"][1]["gap"], 34170)
eq("subagent idle gaps", (a["subagents"][0]["calls"][1]["gap"], fsub["agent-g1"]["calls"][1]["gap"]), (600, 900))
eq("a compaction keeps the next call's cost", a["compactions"],
   [{"t": "2026-09-29T08:10:00Z", "trigger": "auto", "pre": 170000, "post": 18000,
     "next_usd": a["calls"][3]["usd"], "next_wusd": a["calls"][3]["wusd"]}])
# Sizes only: characters / 4, lines before the first call, a later listing not counted.
eq("a start sources", a["start_sources"], {
    "deferred_tool_names": 40, "first_user_prompt": 8, "hook:SessionStart": 10,
    "instructions_file:Project": 100, "instructions_file:User": 50, "session_context": 20,
    "skill_listing": 200, "system_prompt": 500})
eq("start sources without attachments", b["start_sources"], {"first_user_prompt": 5})

# Report: role x model x effort, idle rebuilds, compaction log, start split.
rme = {(x["role"], x["model"], x["effort"]): x for x in rep["role_model_effort"]["by_run"]}
eq("main role is coordinator", rme[("coordinator", "claude-opus-5-5", "medium")]["runs"], 1)
eq("subagent role by agent type", rme[("critical-reviewer", "claude-sonnet-5-5", "high")]["usd"], 0.19)
eq("implementer", rme[("implementer", "claude-opus-5-5", "low")]["runs"], 1)
byc = {(x["role"], x["model"], x["effort"]): x for x in rep["role_model_effort"]["by_call"]}
eq("by call", byc[("coordinator", "claude-opus-5-5", "high")]["calls"], 2)
ir = rep["idle_rebuilds"]
eq("idle events and tokens", (ir["events"], ir["tokens"]), (5, 52500))
eq("idle by gap", {k: v["events"] for k, v in ir["by_gap"].items()},
   {"5min-1h": 3, "1-2h": 1, "2-8h": 0, "8h+": 1})
eq("idle by role", {k: v["events"] for k, v in ir["by_role"].items()},
   {"main:coordinator": 2, "subagent:critical-reviewer": 1, "subagent:explorer": 1, "subagent:?": 1})
eq("idle share of spend", ir["share_of_spend"], round(ir["usd"] / t["usd"], 4), 1e-3)
eq("idle per 7 days", ir["per_7_days_usd"], round(ir["usd"] * 7 / 3, 2), 0.011)
eq("idle fixture sessions are alone", {k: v["events"] for k, v in ir["by_other_main_sessions_active"].items()},
   {"0": 5, "1": 0, "2": 0, "3+": 0})
eq("subagent resumed after 5 min", ir["subagent_resumed_after_5min"]["events"], 3)
eq("long main session", [(x["session"][:1], x["rebuilds"], x["span_hours"]) for x in ir["long_main_sessions"]],
   [("c", 1, 9.5)])
eq("event rows are per event, costliest first", [(e["session"][:1], e["who"], e["gap_s"]) for e in ir["event_rows"]][:2],
   [("a", "main", 6540), ("a", "subagent", 600)])
cl = rep["compaction_log"]["rows"]
eq("compaction log", [(x["session"][:1], x["pre"], x["post"], x["trigger"]) for x in cl], [("a", 170000, 18000, "auto")])
eq("compaction next call cost", cl[0]["next_call_usd"], a["calls"][3]["usd"])
ss = rep["start_split"]
eq("start split sources", ss["by_source"]["system_prompt"]["tokens"], 500)
eq("start split not split",
   ss["not_split"]["tokens"], ss["first_call_context_tokens"] - sum(v["tokens"] for v in ss["by_source"].values()))
eq("start split sessions", ss["sessions"], 4)

# Report logic on a built scan: other main sessions active in the previous hour.
import importlib.machinery, importlib.util
def load(path, name):
    spec = importlib.util.spec_from_loader(name, importlib.machinery.SourceFileLoader(name, path))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
cr_mod = load(sys.argv[3], "cost_report")
def call(t, cause=None, gap=None, w=1000, usd=1.0):
    x = {"t": t, "m": "m", "in": 0, "out": 0, "cr": 0, "w5": 0, "w1": w, "usd": usd, "wusd": usd, "e": "high"}
    if cause: x["cause"] = cause
    if gap: x["gap"] = gap
    return x
sess = lambda sid, calls, subs=(): {"session_id": sid, "project_name": "p", "usd": 10.0, "calls": calls, "subagents": list(subs)}
built = [
    sess("x", [call("2026-01-01T09:00:00Z", "start"), call("2026-01-01T12:00:00Z", "idle", 10800, usd=1.0),
               call("2026-01-01T15:00:00Z", "idle", 10800, usd=2.0), call("2026-01-02T00:30:00Z", "idle", 34200, usd=4.0)]),
    sess("o1", [call("2026-01-01T11:30:00Z"), call("2026-01-01T14:30:00Z")]),
    sess("o2", [call("2026-01-01T11:40:00Z")]), sess("o3", [call("2026-01-01T11:50:00Z")]),
]
b_ir = cr_mod.idle_rebuilds(built, 1.0)
eq("active buckets events", {k: v["events"] for k, v in b_ir["by_other_main_sessions_active"].items()},
   {"0": 1, "1": 1, "2": 0, "3+": 1})
eq("active buckets cost and average", b_ir["by_other_main_sessions_active"]["3+"], {"events": 1, "usd": 1.0, "avg_usd": 1.0})
eq("gap buckets", {k: v["events"] for k, v in b_ir["by_gap"].items()}, {"5min-1h": 0, "1-2h": 0, "2-8h": 2, "8h+": 1})
eq("long session share", b_ir["long_main_sessions"], [{
    "session": "x", "project": "p", "span_hours": 15.5, "session_usd": 10.0, "rebuilds": 3, "main_rebuilds": 3,
    "rebuild_usd": 7.0, "share_of_session": 0.7}])
eq("event rows hold every event", len(b_ir["event_rows"]), 3)

# Prices: Haiku 5.5 is priced by prompt length, per call.
sc = load(sys.argv[4], "cost_scan")
eq("haiku 5.5 short prompt", sc.token_cost("claude-haiku-5-5", 80000, 0, 0, 0, 10000, 1.0, 90000), 0.01, 1e-9)
eq("haiku 5.5 long prompt", sc.token_cost("claude-haiku-5-5", 80000, 0, 0, 0, 30000, 1.0, 110000), 0.07, 1e-9)
eq("haiku 5.5 takes the US multiplier", sc.multiplier("claude-haiku-5-5", {"inference_geo": "us"}), 1.1)
eq("haiku 5.5 has no fast mode", sc.multiplier("claude-haiku-5-5", {"speed": "fast"}), None)
if fails:
    sys.exit("error: " + "\n  ".join(fails))
EOF

# Throughput: merged PRs (stubbed gh), active main sessions and idle-rebuild cost per day.
cat > "$tmp/gh" <<'STUBEOF'
#!/bin/sh
# Stub for gh: acme/one merged 2 PRs on 2026-09-29 and 1 on 2026-09-30, acme/two 1 on
# 2026-09-30; acme/bad fails.
repo=; search=
while [ $# -gt 0 ]; do
  case "$1" in --repo) repo=$2; shift;; --search) search=$2; shift;; esac
  shift
done
case "$repo:$search" in
  acme/bad:*) echo "boom" >&2; exit 1;;
  acme/one:merged:2026-09-29..2026-09-29) echo '[{"number":1,"mergedAt":"x"},{"number":2,"mergedAt":"x"}]';;
  acme/one:merged:2026-09-30..2026-09-30|acme/two:merged:2026-09-30..2026-09-30) echo '[{"number":3,"mergedAt":"x"}]';;
  *) echo '[]';;
esac
STUBEOF
chmod +x "$tmp/gh"
COST_THROUGHPUT_GH="$tmp/gh" python3 "$dir/cost-throughput.py" "$tmp/scan.json" --repo acme/one --repo acme/two \
  --repo acme/bad --out "$tmp/tp.json" --text > "$tmp/tp.txt"
python3 - "$tmp/tp.json" "$tmp/tp.txt" <<'TPEOF'
import json, sys
tp = json.load(open(sys.argv[1]))
d = tp["days"]
fails = []
def eq(what, got, want):
    if got != want:
        fails.append(f"{what}: got {got!r}, want {want!r}")
eq("days", list(d), ["2026-09-29", "2026-09-30", "2026-10-01"])
eq("merged by repo (a failing repo is null)", d["2026-09-29"]["merged_by_repo"],
   {"acme/one": 2, "acme/two": 0, "acme/bad": None})
eq("merged sums the known repos", [d[k]["merged_prs"] for k in d], [2, 2, 0])
eq("active main sessions per local day", [d[k]["active_main_sessions"] for k in d], [1, 2, 1])
eq("idle rebuild cost per local day", [d[k]["idle_rebuild_usd"] for k in d], [0.24, 0.0, 0.0])
eq("idle rebuild main part", [d[k]["idle_rebuild_usd_main"] for k in d], [0.17, 0.0, 0.0])
txt = open(sys.argv[2]).read()
if "2026-09-29" not in txt or "*" not in txt:
    fails.append("text table lacks the day or the failed-query mark")
if fails:
    sys.exit("error: " + "\n  ".join(fails))
TPEOF
echo "cost-review self-test passed"
