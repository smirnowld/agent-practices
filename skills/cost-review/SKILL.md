---
name: cost-review
description: On-demand review of agent spend across all projects on this machine, suggested monthly and after a policy change. Scripts count spend by day, model, project and role, the costliest sessions and the patterns behind them; the session checks whether last review's decisions delivered, ranks levers and asks numbered questions. Proposes changes, never makes them. Use when I ask for /cost-review or where spend went.
---

# Cost review

Goal: know where agent spend went over a window, whether the last review's
decisions delivered what they predicted, and which changes would save the
most, without hand-written scripts. The scripts count; this session judges.
Same measures every run, so runs compare.

Run it on demand: monthly is the suggested cadence, and after a policy or
tooling change once a week of data exists. Scheduling it is my choice. The
whole account's sessions on this machine are in scope, not one project.
Standard tier at medium is enough.

It proposes and never changes: no settings, rules, roles or project files
are edited by this skill. A decision I take becomes a decision record and,
where it changes a rule, a brief.

## Privacy

The scripts print numbers, model names, tool names, agent types, project
names, file paths, session ids and times. They never print message text,
tool input beyond a shell command's program name and a file tool's path, or
tool output. Keep it that way in everything you write:

- Do not open transcripts to read what was said. Causes come from the
  scripts' structured facts (compactions, peak context, subagents by type,
  coordinator reads, self-edits), not from prompts or titles.
- Identify a session by project, local start time and short id.
- File paths and project names from the scripts may be shown, worktree and
  scratch paths included. No secret can reach the report (P10): if a path or
  name looks like one, leave it out and say so.

## 0. Results folder

Results go only to the folder my global agent instructions name, on a line
of this form:

```
Results folder for agent-practices skills: PATH
```

Read that line. If it is missing, ask me once for the folder, propose the
line, and stop: editing my global instructions is outside the repository
(P9), so I add it. Never write results into agent-practices or a project
repository, and never fall back to a default folder.

This skill's results live in `PATH/cost-review/`: one file per run, named by
the window's last day (`YYYY-MM-DD.md`). Files are kept. The previous record
is the latest one whose window ends before this window starts; if none does
but a record covers some of the same days, this run is a re-run: use that
record and say so in the header.

## 1. Window

The window is the days I name. Otherwise it starts the day after the
previous record's window and ends yesterday (local days). With no record,
use the last 7 days. Say the window in the first line of the report.

The session set is the sessions that started in the window; a session's
whole cost counts, including spend after the window's last day (the scripts
report that part as after the window). A record built on another set or
method says so, and figures compared with it say the basis differs.

Windows vary in length, so every weekly figure (spend, savings, a
prediction "per week") is per 7 days: the scripts give both the window's
figure and its 7-day rate.

## 2. Scan and measure

The scanner reads the local transcripts of the agent running this session
and prices them with its dated price table. It lives in that agent's
adapter (`SKILL_DIR/../../adapters/AGENT/cost-scan.py`, where `SKILL_DIR` is
the folder holding this file); list `adapters/*/cost-scan.py` to find it,
and pick the running agent's. An agent with no scanner is out of scope: say
so in the report.

`SCRATCH` is the session's scratch or temporary folder, never a repository
or the results folder:

```
python3 SKILL_DIR/../../adapters/AGENT/cost-scan.py --since YYYY-MM-DD --until YYYY-MM-DD --out SCRATCH/scan.json
python3 SKILL_DIR/../../scripts/cost-report.py SCRATCH/scan.json --out SCRATCH/measures.json --text
```

Use the scripts as they are. Build the report from `measures.json`: reading
its fields (with `jq` or a one-line JSON read) is expected. Computing new
figures from the scan or the transcripts is not. Arithmetic on its fields
(a ratio, a share, scaling a window figure to 7 days) is fine, shown in one
line. If a number you need is not
in `measures.json`, say so in the report's method section and propose it as
a script change. The scanner exits with an error when the transcripts no
longer match the format it knows; then stop and report that, with its
message, instead of building a report.

The measures, every run:

1. Spend by day (main sessions and subagents, days after the window
   marked), model, project, session cost band, context size and role (main
   session, and each subagent type).
2. The 15 costliest sessions, with compactions, peak context and their
   cause facts.
3. Fixed context at session start: the first call's context, median and
   spread.
4. Cache-write cost by cause: growth, after compaction, idle past the cache
   lifetime, session start, and miss (a rewrite with none of those causes);
   `measures.json` defines each.
5. Compactions per 100 main-session responses.
6. Coordinator reads (file reads and read-style shell commands) and the most
   re-read files.
7. Review runs by role and model, with their cost.
8. Delegated, self-implemented and other sessions (P2b): count, cost,
   compactions and coordinator reads. Self-implemented: the main session
   edited source (any file the coordinator hook would deny). Delegated: it
   did not, and an implementer subagent ran. Other (the scripts' `neither`):
   the rest, such as reading, coordinating, docs only, or edits by a
   subagent that is not an implementer.

Totals use the agent's own session counter where the transcript has one,
and the transcript sum where it does not; a session with calls after its
last counter line adds those calls from the transcript. The report says how
many sessions used each basis. The price table's date goes in the report.

## 3. Decision check

Read the previous record (step 0). For each prediction in it, compare the
measure it names with this window's figure, always showing the figure, and
mark it:

- **met**, with the figure;
- **not met**, with the figure and the likeliest reason from the measures;
- **too early**, when fewer than 7 days of the window fall after the time it
  took effect (the record's own date when it gives none).

A prediction that needs a figure from outside the scripts (an external
dashboard the record names) uses a figure I give, or a read-only look at
that page if the record says how; never write to it. Without either, or
when the record's own baseline or threshold is missing, mark it "not
checked" and ask for what is missing in the questions. When the figure it
needs is not in `measures.json` (a combined median, a sum the scripts do
not give), show the nearest figures, mark it "not checked", and propose the
script change in the method section.

The header's change from the previous run uses the previous record's
Measures section; a record without one gives its Summary totals, with the
basis said.

## 4. Levers

From the measures, find what would save the most for a week like this one.
For each lever:

- the evidence: the measure, the figure, the costliest examples;
- an estimate of the weekly saving, rough and labelled as such;
- options A, B, C by effect, one marked proposed, including "leave it";
- whether it needs a session: propose one (`brief` skill) when the change is
  in a repository (a rule, a role, a hook, a project's docs or config), and
  name it in the lever in one line. A role's model or effort default, a
  rule or a hook is a repository change. A change to my settings or
  anything outside a repository is mine to make: give the exact change.

Estimate savings from the scripts' per-role, per-model and per-run figures,
with the arithmetic in one line. A lever an earlier decision already covers
is not ranked again: it shows in the decision check, and returns as a lever
only once that decision is checked and not met. Rank the rest by weekly
saving. When decisions already cover the large levers, say so in the lede
and list only what is left; do not pad the ranking. Patterns you checked that are small or not
worth changing go in one table with their weekly cost and a one-line
verdict, so the next run does not chase them again.

## 5. Report

One HTML page, published as a private page on the agent host; a private
page is not publishing under P9. Follow the host's page guidance for
layout, light and dark colours and phone width. Plain words (P21).
Sections, in order:

1. Header: window, total spend, change from the previous run, one-paragraph
   lede on what drove it.
2. Tiles: total (with basis), sessions, fixed starting context,
   compactions, review cost.
3. Spend per day: main sessions and subagents, stacked.
4. Where it goes: by project, by session cost band, by context size (main
   session calls), by role.
5. Last review's decisions: one row per prediction, met / not met / too
   early, with the figure.
6. What to change, ranked: one block per lever (step 4).
7. Looked at, small or not worth changing.
8. Most expensive sessions: the top 15 with cost, compactions, subagents and
   a one-line cause written from the facts.
9. For discussion: each question's number, title and proposed answer; the
   full question goes in chat (step 6).
10. Method and caveats: sources, price table date, totals basis, what the
    scripts could not measure, agents out of scope (named, with no figures
    unless I give them).

## 6. Questions

Ask in chat, one batch, `templates/question.md` format: each question
headed by its number and title ("Q1. …"), options by effect, a proposed
default, and one Reply line for the batch at the end (P6b).
One question per lever whose proposed option changes something, plus any
"not checked" figure; a lever proposed as "leave it" gets none. Do
not re-ask a question an earlier record answered unless its figures moved.

## 7. Record

After I answer, write `PATH/cost-review/YYYY-MM-DD.md` (the window's last
day), following the folder's own rules if it is in a repository:

- Summary: window, totals with basis, the price table's date, the report
  link.
- Measures: the eight measures' headline figures, so the next run compares.
- Decisions: what I decided, each with where and when it takes effect.
- Predictions: for each decision, the measure, its figure this window, and
  a number that counts as met (per 7 days where weekly), so the next run
  does not have to interpret it.

A decision that changes a rule, role, skill or hook in agent-practices goes
there as a brief with a general reason and no figures: results, counts,
costs and session tables stay in the results folder.

## 8. Report back

Chat gets the report link, the decision check in one line per prediction,
the questions, and once answered, the record's path and any briefs
proposed.
