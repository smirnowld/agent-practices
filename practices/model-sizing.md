# Model sizing

Starting points for P2a. Tiers are vendor-neutral; adapters map them to
models. Adjust from evidence.

## Tiers

| Tier | For |
|---|---|
| fast | Search, lookups, summarising evidence, mechanical edits, scoped slices from a complete brief |
| standard | Implementation that needs exploration or judgement, routine review |
| strong | Hard design, debugging, reviewing standard-tier work that is non-trivial |
| strongest | Critical review of security, auth, payments and data loss, deliberate architecture sessions |

Effort (reasoning budget): low, medium, high, extra-high.

## Defaults by role and task

| Work | Tier / effort |
|---|---|
| Exploration, doc lookup | fast / low |
| Implementation slice, delegated or a session started from a brief | "Tier for a brief" below |
| Review of mechanical change or simple docs | fast / medium |
| Review of normal change | standard / high (never below the implementer) |
| Docs review with implications (ADR status, cross-doc) | standard / high |
| Critical review: security, auth, payments, data loss | strongest / extra-high; the caller never lowers it |
| Critical review when none of those applies (concurrency, migrations, release-critical) | standard / extra-high, same role, never below the implementer |
| Parent session coordinating a written plan | standard / medium |
| Planning or analysis session | strong or strongest, chosen by me |

## Tier for a brief

A brief's Model line comes from two questions, answered from what the brief
already holds, not from the task's title:

- **Exploration left.** *None*: the brief names the owned files and the facts
  to rely on. *Bounded*: a known area, a few files to read. *Open*: the
  cause or the place to change is still to be found.
- **Reasoning left.** *Specified*: the change follows from the settled
  decisions; the proof is objective (tests, compiler, lint, a named check).
  *Judgement*: choices inside the settled decisions, several interacting
  parts. *Open*: design or root cause undecided.

The first row that matches wins:

| Brief | Tier / effort |
|---|---|
| Exploration or reasoning open | standard / high, or strong / medium for hard design |
| Mechanical: formulaic output, objective proof (rename, fixtures, copy, screen to approved design), any size | fast / medium |
| Exploration none or bounded, reasoning specified, size S | fast / high |
| Anything else (judgement, or size M) | standard / medium |

Risk overrides the table: a brief whose Risk line is critical is never below
standard. The Model line names the two answers, for example "fast at high
(exploration bounded, reasoning specified)", so I can check the call. A
brief for review or exploration takes its row in the defaults table and
leaves the answers out; a session that starts by asking me takes the tier of
the work it would start. A fast-tier session
that meets a signal to go up (below) stops with a progress update and asks to
be moved up; the template's Handoff carries this.

## Size in responses

A brief is sized by the responses it will take. Each response re-sends the
whole context, so cost is the response count times the context each carries,
and the context grows until compaction; a slice that ran to 400 responses cost
at least twice one of 200. The count covers the session that does the work
and every agent it delegates to except review, since a delegated
implementer's responses cost about the same as the parent's; review is
mandatory (P4) and budgeted in its role.

| Size | Responses | How it runs |
|---|---|---|
| S | up to 100 | one slice |
| M | up to 200 | one slice, planned as phases that each end in proof |
| L | over 200 | never one slice: split into M steps before the session starts, each to a fresh implementer or a new session with its own brief |

The brief names the size (`templates/brief.md`). Whether to continue past the
budget is a decision I own (P5): a session that reaches it gives a progress
update and stops, even mid-plan; I decide whether the rest is a new step,
and a parent may only propose it. Compactions are not budgeted; more than about one per 100
responses means each response carries too much and the reading rules in
`practices/context-efficiency.md` apply.

## Signals to go up

Repeated failed attempts, unclear root cause, many interacting files, a
reviewer finding the implementer missed something basic, anything in the P4
critical list. A slice past its response budget is a signal to split, not to
go up a tier.

## Signals to go down

The brief fully specifies the change; the check is objective (compiler,
snapshot, lint); output is formulaic.

## Evidence log

Forks: record notable outcomes (tier too weak or wasteful) here.

- 2026-09, all projects: "Tier for a brief" moved scoped slices from
  standard to fast tier. A starting point, not yet measured: record fast-tier
  briefs that had to move up, and standard-tier briefs that fast would have
  finished.
- 2026-09, product repos: five briefs expected to be one slice ran 290 to
  430 responses each with five to seven compactions. The total response
  count, not who made the responses, was the cost driver. Led to "Size in
  responses".
- 2026-09, infrastructure and product repos: critical review was about 38%
  of delegated spend, a strongest-tier run costing about four plain reviews;
  a third of runs were confirm rounds or repeats of one change across repos.
  Two strongest-tier critical reviews that had found blocking issues were
  replayed at standard tier on the same commits: it found two of the three
  blockers, and one real blocker the original missed, at about 40% of the
  cost. The blocker the standard-tier run missed was an operator rollout
  step on a change touching a runner token, which stays at strongest tier.
  Led to P4a and the standard-tier row for critical review outside security,
  auth, payments and data loss.
