# Visuals

<!-- Spec for docs/visuals/<doc>.html: one-page visual views of roadmap.md,
plan.md, architecture.md and tech-stack.md, for people. The Markdown doc is
the source of truth; a visual never says anything its source does not. For
a project on a board, the plan visual's status comes from the board
(practices/tracking.md), never from merged PRs or the Markdown docs. -->

## Files

- `docs/visuals/<doc>.html`, one per source doc, plus `docs/visuals/README.md`
  listing each visual, what it shows, and its GitHub link (P18).
- Self-contained HTML: inline CSS and SVG; web fonts from Google Fonts at most;
  no scripts required to read it. Opened from GitHub or downloaded.
- Light and dark: colour tokens on `:root`, redefined for
  `prefers-color-scheme: dark` and for `[data-theme]`.
- Laid out for a desktop or tablet screen. Do not squeeze the picture to fit a
  phone; let it scroll if needed.

## Shared encoding

The same meaning has the same look in every visual of a project.

| Encoding | Means |
|---|---|
| Blue | Code we write |
| Green | Apps and surfaces people touch |
| Violet | A service we rent |
| Neutral | Open source we build on |
| Amber | A milestone or something waiting on the maintainer |
| Dashed outline | A boundary, or something not yet built or confirmed |

Every visual carries a legend for the encodings it uses.

## Every page

- Eyebrow: project · doc · month and year.
- A headline claim (the one from the source doc) and a two-to-three sentence
  intro.
- No internal IDs or jargon; the reader may be outside the project.

## Per doc

| Visual | Shape |
|---|---|
| Roadmap | Phases in order as cards: name, size, deliverables in user terms, "Done when". Milestone flags. A parallel track for work outside engineering. No dates unless the source commits to them. |
| Plan | The current phase: goal up top, with health from the board's status update when it has one; the order of outcomes from plan.md as a diagram with nodes coloured by their packages' status on the board (done; waiting, with engineering complete marked; active; planned or ready; parked, dashed); a progress count from the board; amber for what waits on the maintainer, taken from items assigned to the maintainer. |
| Architecture | Boxes grouped by boundary (clients, our system, rented services), arrows for who calls whom, a caption saying so; principles below as short cards. |
| Tech stack | One band per layer with its one-line intent; each choice tagged by kind (write, build on, rent, unconfirmed). |
