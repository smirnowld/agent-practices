# Planning

Detail for P6 "Plan in increments": how to shape a plan. P6 keeps only how to
ask me about it.

- **Short, demoable increments.** Each increment ends in something I can see
  working, so a wrong direction shows early and costs one increment.
- **Honest ranges.** Estimate as a range that reflects the real uncertainty,
  not a single number that looks precise.
- **Size relatively.** Compare work with work already done ("about twice the
  last slice") rather than computing absolute hours.
- **Size in responses.** An increment is at most an M slice
  (`practices/model-sizing.md`, "Size in responses"); anything larger is
  planned as steps before a session starts, not split by the session once it
  is over budget.

Cross-project lesson, 2026-09; moved out of policy P6 on 2026-09-28.

## Two files per phase

A product's current phase plan (P19) is two files, each owning one thing:

- **`docs/plan.md`** (`templates/docs/plan.md`) owns status. It is a
  current-state doc: every change of a package's status is made here and
  nowhere else.
- **`docs/plans/phase-N.md`** (`templates/docs/phase-plan.md`) owns scope:
  the open packages' criteria, the rules for running them, pending inputs,
  parked packages and the estimate. It is the phase's living plan (P17) and
  carries no status. Parking is a scope decision, recorded only here.

Package IDs are the only IDs; `plan.md` rows name outcomes and map to them in
a Packages column.

**When a package leaves.** The pull request that finishes a package sets its
`plan.md` row and removes its section from the phase plan. If the project
keeps docs out of that pull request (a separate docs lane), its `AGENTS.md`
names who does it; the closeout checks it happened. A package merged as
engineering complete but externally blocked (P5) stays, reduced to its
blocked criteria, until it is finished.

**At the end of the phase:** compare the result with the estimate (kept as
accepted), move lasting outcomes into the roadmap and current-state docs,
delete the phase plan and write the next one in the same shape.

Why: acceptance criteria must exist before a package is briefed, and briefs
do not stay in the repository, so criteria need a file; but when both files
carried status, sessions updated one and not the other, and two numbering
schemes made them hard to read side by side. Product repo, 2026-09.
