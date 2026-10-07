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
- Identify a session by project, start time and short id.
- No secret can reach the report (P10): if a path or name in the output
  looks like one, leave it out and say so.

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
the window's last day (`YYYY-MM-DD.md`). Files are kept; each run reads the
latest one.

## 1. Window

The window is the days I name. Otherwise it starts the day after the latest
record's window and ends yesterday (local days). With no record, use the
last 7 days. Say the window in the first line of the report.

## 2. Scan and measure

The scanner reads the running agent's local transcripts and prices them
with its dated price table. It lives in that agent's adapter
(`SKILL_DIR/../../adapters/AGENT/cost-scan.py`, where `SKILL_DIR` is the
folder holding this file); list `adapters/*/cost-scan.py` to find it. An
agent with no scanner is out of scope: say so in the report.

Write intermediate files to the session's scratch folder, never into a
repository:

```
python3 SKILL_DIR/../../adapters/AGENT/cost-scan.py --since YYYY-MM-DD --until YYYY-MM-DD --out SCRATCH/scan.json
python3 SKILL_DIR/../../scripts/cost-report.py SCRATCH/scan.json --out SCRATCH/measures.json --text
```

Use the scripts as they are. If a number you need is not in their output,
say so in the report's method section and propose it as a script change; do
not write an ad-hoc script. If the scanner stops on an unknown transcript
format, stop and report it.

The measures, every run:

1. Spend by day, model, project and role (main session, and each subagent
   type).
2. The 15 costliest sessions, with compactions, peak context and their
   cause facts.
3. Fixed context at session start: the first call's context, median and
   spread.
4. Cache-write cost by cause: growth, after compaction, idle past the cache
   lifetime, session start.
5. Compactions per 100 main-session responses.
6. Coordinator reads (file reads and read-style shell commands) and the most
   re-read files.
7. Review runs by role and model, with their cost.
8. Delegated, self-implemented and reading-only sessions (P2b): count, cost,
   compactions and coordinator reads.

Totals use the agent's own session counter where the transcript has one,
and the transcript sum where it does not; the report says how many sessions
used each basis. The price table's date goes in the report.

## 3. Decision check

Read the latest record in `PATH/cost-review/`. For each prediction in it,
compare the measure it names with this window's figure and mark it:

- **met**, with the figure;
- **not met**, with the figure and the likeliest reason from the measures;
- **too early**, when fewer than 7 days of the window fall after the date it
  took effect.

A prediction that needs a figure from outside the scripts (an external
dashboard the record names) uses a figure I give, or a read-only look at
that page if the record says how; never write to it. Without either, mark it
"not checked" and ask for the figure in the questions.

## 4. Levers

From the measures, find what would save the most for a week like this one.
For each lever:

- the evidence: the measure, the figure, the costliest examples;
- an estimate of the weekly saving, rough and labelled as such;
- options A, B, C by effect, one marked proposed, including "leave it";
- whether it needs a session: propose one (`brief` skill) when the change is
  in a repository (a rule, a role, a hook, a project's docs or config). A
  change to my settings or anything outside a repository is mine to make:
  give the exact change.

Rank levers by weekly saving. Patterns you checked that are small or not
worth changing go in one table with their weekly cost and a one-line
verdict, so the next run does not chase them again.

## 5. Report

One HTML page, published as a private page on the agent host (not
publishing under P9). Plain words (P21). Sections, in order:

1. Header: window, total spend, change from the previous run, one-paragraph
   lede on what drove it.
2. Tiles: total (with basis), sessions, fixed starting context,
   compactions, review cost.
3. Spend per day: main sessions and subagents, stacked.
4. Where it goes: by project, by session cost band, by context size, by
   role.
5. Last review's decisions: one row per prediction, met / not met / too
   early, with the figure.
6. What to change, ranked: one block per lever (step 4).
7. Looked at, small or not worth changing.
8. Most expensive sessions: the top 15 with cost, compactions, subagents and
   a one-line cause written from the facts.
9. For discussion: the questions (step 6), Q-numbered.
10. Method and caveats: sources, price table date, totals basis, what the
    scripts could not measure, agents out of scope.

## 6. Questions

Ask in chat, one batch, `templates/question.md` format: Q1, Q2 with
options by effect, a proposed default, and the closing Reply line (P6b).
One question per lever worth deciding, plus any "not checked" figure. Do
not re-ask a question an earlier record answered unless its figures moved.

## 7. Record

After I answer, write `PATH/cost-review/YYYY-MM-DD.md` (the window's last
day), following the folder's own rules if it is in a repository:

- Summary: window, totals with basis, the price table's date, the report
  link.
- Measures: the eight measures' headline figures, so the next run compares.
- Decisions: what I decided, each with where and when it takes effect.
- Predictions: for each decision, the measure, its figure this window, and
  what counts as met.

A decision that changes a rule, role, skill or hook in agent-practices goes
there as a brief with a general reason and no figures: results, counts,
costs and session tables stay in the results folder.

## 8. Report back

Chat gets the report link, the decision check in one line per prediction,
the questions, and once answered, the record's path and any briefs
proposed.
