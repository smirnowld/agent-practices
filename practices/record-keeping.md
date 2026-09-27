# Record keeping

Detail for P17: size budgets and what triggers `docs-gardening`. Budgets are
starting points; adjust them from evidence.

## Budgets

| Record | Budget |
|---|---|
| ADR summary (above the divider) | ~15 lines |
| ADR total | ~10 KB; longer evidence goes in the PR |
| ADR index (`docs/adr/README.md`) | One line per ADR in force |
| ADRs in force | Review when over 25; many may be superseded |
| Question register (`docs/questions.md`, template `templates/docs/questions.md`) | 30 open items or 20 KB |
| Current-state doc | 40 KB per file; split by topic beyond that |
| Living plan | 20 KB; one per initiative |
| Binaries in `docs/` | None, except diagrams a doc embeds (< 200 KB each) |
| Session, closeout, brief, verification logs | None in the repo |

## Triggers

- A closeout finds a record over budget: run `docs-gardening` in a separate
  PR, or note it as deferred if the session is nearly done.
- A new ADR supersedes one: archive the old one in the same PR.
- A question is answered: resolve it in the same PR.

## Visual evidence

Screenshots and other visual acceptance evidence go on a private published
page (the agent host's own page feature, or any private host that opens on my
phone, P18), linked from the PR. Agents' command-line tools cannot upload
images as PR attachments, and committing them to the repo breaks the binaries
budget above. Learnt in a product repo, 2026-09-27.

## Why

Agents read docs on start. Oversized records cost tokens every session, bury
current truth under history, and contradict each other. Git already keeps
history, so deleting is safe.
