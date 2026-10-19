# Accessibility

Detail for P22. How much accessibility work a project does is a choice made per project
(P22), not a default every change carries. The reason: checking and fixing
every screen at large text and with a screen reader, on every change, costs
a lot while screens are still being redesigned, and a tool only its author
uses gets nothing from it. What is cheap to build in from the start is
expensive to retrofit, and what is expensive to check is cheap to check
once, before people depend on it.

## Levels

| Level | Fits | What sessions do |
|---|---|---|
| `none` | A tool only I or my team use | Nothing beyond the project's own readability rules. Reviews raise no accessibility findings. |
| `built-in` | An internal tool with a few users; an early product with no outside users yet | The habits below on every change. No per-change testing, fixing or acceptance evidence at large text or with a screen reader. Reviews raise only a broken habit. |
| `reviewed` | A product with customers, the public, or a legal duty | `built-in`, plus a focused review before each milestone the project names. |

No declaration means `none`; the baseline audit (R8 in
[project-baseline.md](project-baseline.md)) reports it so the choice is
made, not forgotten.

## Built-in habits

Each costs close to nothing when written first, and each is a rewrite when
added later because it spreads through every screen:

- Platform text styles (Dynamic Type, scalable `sp`, `rem`), never fixed
  font sizes.
- No fixed heights on anything holding text; let rows and buttons grow.
- A label on every icon-only control and on values a screen reader would
  otherwise read badly (prices, times).
- System or design-system components over hand-built ones, so their
  accessibility comes along.
- Contrast settled in the colour tokens, checked where the tokens are
  generated, not screen by screen.

Existing automated large-text or screen-reader tests stay: they are already
paid for and catch regressions. New work does not add more of them.

## The milestone review

For a `reviewed` project, `AGENTS.md` names the milestones, for example: a
new customer or tenant going live, a first public release, a new customer
flow shipping, the end of a phase. Before each, the phase plan carries one
work package that:

- walks the main flows at the largest text sizes, with the platform's
  screen reader, and checks contrast and touch targets;
- covers the screens the milestone puts in front of users, not the whole
  product each time;
- fixes what it finds in the same package, and takes in the open issues
  marked for it.

Accessibility findings that turn up between reviews are filed for the next
one, not fixed on the go, unless they break a built-in habit.

## When the level should rise

Raise the question with me when planned work would:

- give the project users outside my team;
- give it paying customers or put it in front of the public;
- bring a legal duty, such as an accessibility law covering the service
  (check the law's own text and its exemptions; P12).

The level is mine to set; a session proposes it with the reason.
