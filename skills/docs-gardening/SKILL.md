---
name: docs-gardening
description: Consolidate a project's records to current truth (P17) when a record exceeds its size budget in practices/record-keeping.md, or at closeout when records drifted. Moves, merges and deletes docs; git history is the archive.
---

# Docs gardening

Goal: the repo holds current truth and lasting decisions only, within the
budgets in `practices/record-keeping.md`. Nothing is lost: git keeps history.

## 1. Measure

List records with sizes and counts: `docs/` tree, ADRs (in force vs archive),
question register open items, plans, session or verification logs, binaries.
Compare with the budgets; list what is over.

## 2. Classify each over-budget or suspect record

| It is… | Do |
|---|---|
| Session log, closeout, brief, verification log | Delete; move any lasting fact into the current-state doc or an ADR first |
| Current-state doc with history in it | Rewrite to "how it is now"; drop narrative |
| Quotes from me, my name, or a date that only records when something was said | Reword (`practices/record-keeping.md#outcomes-not-conversations`) |
| ADR missing the summary layer | Add Decision/Consequences above a divider (`templates/adr.md`) |
| ADR superseded or rejected | Move to `docs/adr/archive/`; update the index |
| Answered question | Answer into an ADR or doc; remove from the register |
| Finished plan | Move outcomes; delete |
| Screenshot or binary in docs | Delete unless a test compares against it (then move to the test baseline folder) |

Never delete a record that a live doc, test or script references without
fixing the reference. Never change what a decision says; only its form.

## 3. Check implications

Search for references to every moved or deleted path and ADR number; fix them.
Look for contradictions between docs you touched.

## 4. Deliver

One PR, grouped commits (delete / archive / rewrite). The description gives
before/after sizes, what was deleted and where each lasting fact went. Review
as docs (P4): references, contradictions, stale mentions. Decisions whose
meaning I might dispute go to me, not the reviewer.
