# Record keeping

Detail for P17: size budgets and what triggers `docs-gardening`. Budgets are
starting points; adjust them from evidence.

## Budgets

| Record | Budget |
|---|---|
| ADR summary (above the divider) | ~15 lines |
| ADR total | ~10 KB; longer evidence goes in the PR |
| ADR index (`docs/adr/README.md`, template `templates/docs/adr-index.md`, checked by baseline C5) | One line per ADR in force or proposed |
| ADRs in force | Review when over 25; many may be superseded |
| Question register (`docs/questions.md`, template `templates/docs/questions.md`) | 30 open items or 20 KB |
| Current-state doc | 40 KB per file; split by topic beyond that |
| Living plan | 20 KB; one per initiative |
| Phase status (`docs/plan.md`) | 20 KB |
| Phase work packages (`docs/plans/phase-N.md`, the phase's living plan) | 30 KB, in place of the living-plan budget |
| Binaries in `docs/` | None, except diagrams a doc embeds (< 200 KB each) |
| Session, closeout, brief, verification logs | None in the repo |

## Triggers

- A closeout finds a record over budget: run `docs-gardening` in a separate
  PR, or note it as deferred if the session is nearly done.
- A new ADR supersedes one: in the same PR, set the old one's status to
  superseded, move it to the archive and remove its index row. The ADR check
  (baseline C5) catches a superseded status left in place or an archived ADR
  still listed, not an old ADR whose status was never changed. The index
  scheme and check came from a product repo, in use since 2026-09.
- A question is answered: resolve it in the same PR.

## Visual evidence

Screenshots, recordings and other visual acceptance evidence go on a private
published page (the agent host's own page feature, or any private host that
opens on my phone, P18), linked from the PR. The host is agreed once per
project; publishing a private evidence page there is not publishing under P9.
Agents' command-line tools cannot upload images as PR attachments (observed;
unverified against a primary source), and P17 keeps verification evidence out
of the repository (the "verification logs" row above). Learnt in a product
repo, 2026-09-27.

## Why

Agents read docs on start. Oversized records cost tokens every session, bury
current truth under history, and contradict each other. Git already keeps
history, so deleting is safe.
