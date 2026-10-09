---
name: docs-drift-check
description: Weekly routine (baseline T1). Cheaply checks whether a project's docs still match its code and recent merges, and proposes a session only when the drift warrants one. Read-only.
---

# Docs drift check

Goal: find docs that no longer describe the code, at the lowest cost that can
tell. Most weeks the answer is "no drift" and the run ends there. Read-only:
it never edits the repo.

Runs from a local scheduled routine over the private project list, one run per
project. The routine proposes a follow-up session only for projects this skill flags.

## 1. Cheap pass (fast tier)

Since the last run (or 7 days):

1. List merged PRs and commits to the default branch. None: report
   "no changes" and stop.
2. List changed paths. Map them to the docs that describe them: the doc set
   for the repo type (P19), `README.md`, `AGENTS.md`, `docs/operations.md`,
   runbooks, ADRs whose subject the paths touch.
3. For each changed area, check whether the matching doc changed in the same
   PR or after. Unchanged doc with changed subject is a candidate.
4. Mechanical checks, no judgement needed: links and paths in docs that no
   longer resolve; commands in docs whose scripts or targets were renamed;
   the observability manifest naming endpoints or files that are gone;
   docs over the budgets in `practices/record-keeping.md`; visuals in
   `docs/visuals/` older than the doc they draw (`project-visuals`).
   For a product (`practices/planning.md`, "Two files per phase"): a
   finished package still in `docs/plans/phase-N.md`; a `docs/plan.md` row
   whose status disagrees with its PR (merged but not Done or Engineering
   complete, open but not In review or In progress).
5. ADRs still Proposed in `docs/adr/README.md` that a PR in the range built
   (the PR names the ADR and changed code), with no ruling of mine and no
   exploratory reason in that PR: candidates for an acceptance ask (P11).

No candidates and no mechanical failures: report "no drift" and stop.

## 2. Confirm (standard tier, only for candidates)

Read each candidate doc section against the diff that touched its subject.
Classify:

- **Drift:** the doc states something now false, or omits something a reader
  needs (a new env var, step, service, decision).
- **Fine:** the change does not affect what the doc says.

Do not report style or wording.

## 3. Decide

| Result | Output |
|---|---|
| Nothing confirmed | One line: "no drift", with the range checked |
| Only mechanical fixes (links, paths, renamed commands) | Proposed session: small fix session, standard tier |
| Confirmed drift in docs | Proposed session: docs update session; over-budget records go to `docs-gardening` |
| A built ADR still Proposed with no ruling (step 1, item 5) | Proposed session that asks me to rule on it and records the answer |
| A doc contradicts a decision or code in a way I must settle | Proposed session that asks me first; do not propose a fix |

## 4. Session brief

Write it with the `brief` skill: the repo, the commit range, each finding as
`doc:section — claim — evidence (file:line or PR URL, P18)`, the proposed
change, and proof = docs review (P4). Keep it to findings; no transcript.

Report the run's token use in the routine's log so the cost of the routine
stays visible.
