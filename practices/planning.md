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

## Two files per phase

A product's phase plan (P19) is two files with one owner each:

- `docs/plan.md` (`templates/docs/plan.md`) owns status: one screen, one
  status per row, updated by every session that changes one.
- `docs/plans/phase-N.md` (`templates/docs/phase-plan.md`) owns scope: the
  open packages' criteria, the rules for running them, pending inputs and the
  estimate. It carries no status, and a package leaves it when it merges.

Package IDs are the only IDs; `plan.md` rows name outcomes and map to them in
a Packages column. Why: acceptance criteria must exist before a package is
briefed, and briefs do not stay in the repo, so they need a file; but when
both files carried status, sessions updated one and not the other, and two
numbering schemes made the files hard to read side by side. Product repo,
2026-09.

Cross-project lesson, 2026-09; moved out of policy P6 on 2026-09-28.
