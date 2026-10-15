# UI design rules and design review

Cross-project rules for screens people use, and how a change to them is
reviewed. Each rule is written so a reviewer can say pass or fail from a
screenshot, a string or a measurement; project rules (brand, tokens, component names) live
in the project's `docs/design.md` and add to these.

## Rules

Numbered so findings can cite them (`UI3`). A project's `docs/design.md`
overrides one by number and says why.

### Layout and information

- **UI1. Visual first, detail below.** A screen or card whose job is an
  overview shows the state as a visual (chart, bar, status mark, grid) above
  any explanatory text. Fails when the first thing in reading order is a
  paragraph that a visual could replace.
- **UI2. One message per card.** A card or row carries one headline and at
  most two supporting lines, counted as rendered lines at default text size
  in the longest locale. Fails at three or more supporting lines, or when
  the headline joins two facts (a count and a sentence, two numbers).
- **UI3. Density matches the task.** No region of the first screen is empty
  for more than a third of the viewport height unless it is a deliberate
  empty state; a list or table fits the narrowest supported width without
  horizontal scroll, by hiding, merging or stacking columns.
- **UI4. Exact values visible.** A number the user acts on is shown as text,
  not only on hover, tap-and-hold or in a tooltip.
- **UI5. Numbers say what they are.** Every number shows its unit and the
  period it covers where it has them and, where the change says it can be
  stale, when it was measured. A value that is
  estimated or unavailable is labelled as such, never shown as a plain
  number, zero or blank.

### Consistency

- **UI6. Same element, same size.** One component (button, toggle, badge,
  dot, chip) has the same height, corner radius and padding everywhere it
  appears, in every locale and theme, unless the project's `docs/design.md`
  names it as a separate size variant. Width may grow with the label; height
  may not. Measured, not eyeballed: height differences above 2 pt (iOS),
  2 dp (Android) or 2 CSS px fail.
- **UI7. Same meaning, same look across platforms.** The same concept is the
  same relative size and weight on each platform, adapted to that platform's
  native control. A status mark more than 1.5 times larger, relative to its
  neighbouring text, on one platform than another fails.
- **UI8. Locales fit.** The longest supported locale shows every label in
  full: no truncation, clipping, overlap or unplanned wrap. Truncation with an
  ellipsis is allowed only where the full text is one tap away.
- **UI9. Both themes are designed.** Every screen is checked in light and
  dark: no element disappears, no hard-coded colour that only works in one.

### Readability and access

- **UI10. Contrast.** Text meets WCAG 2.2 AA (4.5:1, or 3:1 for large text:
  at least 24 CSS px regular or 18.66 CSS px bold, which WCAG writes as 18 pt
  and 14 pt); icons and control borders that carry
  meaning meet 3:1.
- **UI11. No colour-only status.** Every status shown by colour also has a
  shape, icon or word.
- **UI12. Touch targets.** Every tappable element is at least 44×44 pt on iOS
  and 48×48 dp on Android, and at least 24×24 CSS px on the web (WCAG 2.5.8),
  including its padding.
- **UI13. Large text works.** At the largest accessibility text size the
  platform offers that the project supports, nothing clips or overlaps and
  every action stays reachable.
- **UI14. Errors are prominent.** An error or blocking state uses the
  project's error style at body size or larger, next to the thing it is
  about, and is visible without scrolling from that thing. Small grey text
  fails.

### Copy

- **UI15. Copy says what to do next.** An error, empty, offline or
  unavailable state says what happened and what the user can do now. A bare
  label ("Unavailable: X", "Error") fails.
- **UI16. Copy is true.** The text matches what the app actually does in that
  state (offline still shows cached data, a retry happens automatically, an
  item can still be ordered later). A statement the reviewer can show is
  false from the screen or the change fails.
- **UI17. One term per concept.** The same thing has the same name across
  screens and, within a locale, the same register (formal or informal
  address) throughout.
- **UI18. Every locale is written, not just translated.** Each locale reads
  naturally to a native speaker: no word-for-word calques, no untranslated
  strings, no mixed scripts except names and terms kept in the original.

### Platform conventions

Load only the section for each platform the change touches. A finding
against one cites it as `iOS`, `Android` or `Web`.

- **iOS** (Human Interface Guidelines): system controls for system jobs
  (toggles, segmented controls, sheets, navigation bar); large titles only on
  top-level screens; no Android-style floating action button; SF Symbols
  weight matches neighbouring text; buttons in a row share one style
  (a filled, prominent button for the one primary action, not every action).
- **Android** (Material 3): top app bar, navigation bar and dialogs from the
  Material components; one filled button per screen for the primary action;
  ripple on tappable surfaces; system back always works.
- **Web**: works from 320 CSS px to wide desktop; semantic headings in order;
  focus visible on every control; no text in images.

## Review layers

A change to user-visible UI is reviewed in layers, split by input rather
than by topic, cheapest first. Each layer reports only what it can see.

| Layer | Input | Who | Finds |
|---|---|---|---|
| 0. Measurements | The running screens | Scripts | UI6 to UI8, UI10, UI12, UI13 by number: sizes across locale and theme, truncation, contrast, target sizes; side-by-side grids for the next layers |
| 1. Copy | Changed strings, every locale, with key and screen | [Copy reviewer](../roles/copy-reviewer.md) | UI15 to UI18 |
| 2. Visual | The grids and a few full-size screens, the change's description, the project's `docs/design.md` | [Design reviewer](../roles/design-reviewer.md) | Guide compliance, consistency the scripts could not measure (UI6 to UI9), usability (UI11, UI14), brand, UI1 to UI5 |
| 3. Critique | A new screen's plan or sketch | Design reviewer in critique mode, at planning time | Whether the screen's structure suits its job; advisory |

Rules for every layer:

- **Platform sections load only for touched platforms**; no reviewer per
  platform or per concern.
- **Grids beat single screens.** Consistency defects (UI6 to UI9) are seen
  only when the variants sit side by side at the same scale: one grid per
  screen with locale × theme × platform cells.
- **Full-size, not downscaled.** Size and spacing findings need images at
  device resolution or a stated scale; a downscaled screenshot hides 2-point
  differences.
- **These layers add to the change's review (policy P4), never replace
  it.** Their findings map onto it: *defect* (broken, false, unreadable,
  unreachable) and *guide* (violates a numbered rule, cited) are blocking;
  *advisory* (a better design is possible) is non-blocking, tracked as P4
  says and shown on the acceptance card for the owner's call.
- **Do no harm.** A reviewer never proposes restyling something that passes
  the rules; an advisory finding names the problem a user would have, not a
  taste.

## Origin

Defects caught only by the owner at acceptance in a native mobile ordering
app and a web operations dashboard: control sizes that varied by locale and
theme, a status mark several times larger on one platform, an unavailable
state shown in small grey text with a bare label, offline copy that did not
match behaviour, summary cards carrying paragraphs, and a table wider than a
phone.
