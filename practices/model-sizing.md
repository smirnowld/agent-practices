# Model sizing

Starting points for P2a. Tiers are vendor-neutral; adapters map them to
models. Adjust from evidence.

## Tiers

| Tier | For |
|---|---|
| fast | Search, lookups, summarising evidence, mechanical edits |
| standard | Most implementation and routine review |
| strong | Hard design, debugging, reviewing standard-tier work that is non-trivial |
| strongest | Critical review (P4 categories), deliberate architecture sessions |

Effort (reasoning budget): low, medium, high, extra-high.

## Defaults by role and task

| Work | Tier / effort |
|---|---|
| Exploration, doc lookup | fast / low |
| Mechanical slice (rename, fixtures, copy, screen to approved design) | fast / medium |
| Normal coding slice | standard / medium |
| Hard design or debugging slice | standard / high, or strong / medium |
| Review of mechanical change or simple docs | fast / medium |
| Review of normal change | standard / high (never below the implementer) |
| Docs review with implications (ADR status, cross-doc) | standard / high |
| Critical review | strongest / extra-high |
| Parent session coordinating a written plan | standard / medium |
| Planning or analysis session | strong or strongest, chosen by me |

## Size in responses

A brief is sized by the responses it will take. Each response re-sends the
whole context, so cost is the response count times the context each carries,
and the context grows until compaction; a slice that ran to 400 responses cost
at least twice one of 200. The count covers the session that does the work
and every agent it delegates to, since a delegated implementer's responses
cost about the same as the parent's.

| Size | Responses | How it runs |
|---|---|---|
| S | up to 100 | one slice |
| M | up to 200 | one slice, planned as steps that each end in proof |
| L | over 200 | never one slice: split into M steps before the session starts, each to a fresh implementer or a new session with its own brief |

The brief names the size (`templates/brief.md`). Whether to continue past the
budget is a decision I own (P5): a session that reaches it gives a progress
update and stops, even mid-plan, and the parent or I decide whether the rest
is a new step. Compactions are not budgeted; more than about one per 100
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

- 2026-09, product repos: five briefs expected to be one slice ran 290 to
  430 responses each with five to seven compactions. The total response
  count, not who made the responses, was the cost driver. Led to "Size in
  responses".
