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
  scheme and check came from a product repo.
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

On that page, each image opens in an in-page viewer with a visible way back,
never as a link to the image file: the host's page viewer opens a linked
image with no back control, which strands me in picture view on a phone
(observed; unverified against a primary source). Start from
[templates/evidence-page.html](../templates/evidence-page.html): a button per
image opens a full-screen dialog with "Back to overview" and an actual-size
toggle, and its Back button, Escape and the back gesture close it. Learnt in
a product repo, 2026-10-02.

## Outcomes, not conversations

Detail for P17. Future sessions read checked-in files, docs and code comments
alike, for the result, not for the conversation that produced it. The PR that
made a decision keeps that history: my words quoted (P11), who decided, when.

- **No quotes from me.** State the decision or fact in plain words:
  "Promotions come after phase 2a", not my sentence in quotation marks.
- **No names.** Leave the person out when the sentence works without one:
  "Secrets are created by hand in the dashboard; agents never see them." When
  a person is needed, write "me" in an `AGENTS.md`, which speaks in my voice
  like the policy, and "the maintainer" elsewhere. Not "the owner" or "the
  operator": products use those words for their own roles. An accepted ADR
  needs no "decided by"; only I accept decisions (P11). Anyone else is named
  by role.
- **A date only where it helps the reader** judge how fresh a fact is: when an
  outside fact was checked, when a measurement or observation was made where
  tool or model behaviour may since have changed, a deadline, how long live
  state has been in place, an ADR's date. Drop a date that only records when
  something was said, decided or moved; git has it.
- **Lessons say where they came from by kind of project** ("a product repo"),
  so a reader can judge whether they apply, with a date only under the rule
  above.
- **Text found breaking this** is reworded when found, as a fix on the go
  (P6): keep the fact, drop the attribution.

Learnt across all projects: agents copied my words, my name and the date of
each conversation into docs and code comments, where no later reader needed
them.

## Why

Agents read docs on start. Oversized records cost tokens every session, bury
current truth under history, and contradict each other. Git already keeps
history, so deleting is safe.
