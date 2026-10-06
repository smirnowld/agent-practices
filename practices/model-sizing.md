# Model sizing

Starting points for P2a. Tiers are vendor-neutral; adapters map them to
models. Adjust from evidence.

## Tiers

| Tier | For |
|---|---|
| fast | Search, lookups, summarising evidence, mechanical edits, scoped slices from a complete brief |
| standard | Implementation that needs exploration or judgement, routine and critical review |
| strong | Hard design, debugging, reviewing standard-tier work that is non-trivial |
| strongest | Critical review of harm a revert cannot undo (P4), deliberate architecture sessions |

Effort (reasoning budget): low, medium, high, extra-high.

## Defaults by role and task

| Work | Tier / effort |
|---|---|
| Exploration, doc lookup | fast / low |
| Implementation slice, delegated or a session started from a brief | "Tier for a brief" below |
| Review of mechanical change or simple docs | fast / medium (light reviewer) |
| Review of normal change, agent tooling, or a fix of a critical finding (P4a) | standard / high (reviewer; never below the implementer) |
| Docs review with implications (ADR status, cross-doc) | standard / high (reviewer) |
| Critical review (P4) | standard / high (critical reviewer); the caller raises the model to the implementer's tier, never lowers it |
| Critical review of harm a revert cannot undo that reaches production data, backups, secrets or credentials, money, or real people's data | strongest / extra-high (strongest critical reviewer); the caller never lowers it |
| Parent session coordinating a written plan | standard / medium |
| Planning or analysis session | strong or strongest, chosen by me |

## Which reviewer

P4 sorts changes by what a mistake would do. Examples:

- **Strongest critical reviewer**: a backup copy job; a one-way database
  migration with no backup; a job that writes a real tenant's data; a
  production database role; redacting secrets from scan output; a change
  that handles secrets.
- **Critical reviewer**: everything else P4 calls critical, such as a
  migration with a backup or a way back, a release or deploy workflow, a
  change to a required check, and auth on a product with no live users yet.
- **Reviewer or light reviewer**: docs and ADRs (the code that implements
  them is reviewed on its own), agent tooling (hooks, skills, policy
  wording), renames, version bumps CI proves, staging-only changes, moving
  jobs between runners, a change its brief rates low or normal risk, and
  every re-check of a fix given the finding (P4a).

## Tier for a brief

A brief's tier comes from two questions, answered from what the brief
already holds, not from the task's title:

- **Exploration left.** *None*: the brief names the core files and the facts
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
standard. The Model line names the tier's model from the adapter's
`tiers.json` and the two answers, for example "fast (MODEL) at high
(exploration bounded, reasoning specified)", so I can start the session on
that model and check the call. A
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

- All projects: "Tier for a brief" moved scoped slices from
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
  Led to P4a and a standard-tier critical review outside security, auth,
  payments and data loss, since replaced (next entry).
- 2026-09-29 to 2026-10-06, all projects: 87 critical reviews cost about
  $380, about $4.30 each, with about 42k output tokens per run, mostly
  thinking. After that split, 33 of 34 still ran at strongest / extra-high,
  11 of them only release or migration work: the split depended on each
  caller lowering the model, and callers did not. Sorted by what a mistake
  would do, 6 needed the strongest tier, about 48 a standard-tier critical
  review, and about 31 no critical review (9 fix re-checks, 5 agent tooling
  changes, 5 rated low or normal risk, 4 ADRs and docs, plus runner moves, a
  rename, a version bump CI proved and a table layout). The plain reviewer
  ran 284 times; 29% were docs, plan or policy reviews, almost all at
  standard / high, and callers who lowered the model to fast left effort at
  high, since effort comes from the role, not the call. Led to the
  effect-based critical list in P4, the strongest critical reviewer as a
  separate role, the light reviewer, and P4a's fix re-check by the reviewer;
  expected critical review spend about $125 a week.
