# Model sizing

Starting points for P2a. Tiers are vendor-neutral; adapters map them to
models. Adjust from evidence: the `cost-review` skill measures spend by role
and model and checks each change against what it predicted; its figures stay
in the results folder, and a change lands here with a general reason.

## Tiers

| Tier | For |
|---|---|
| fast | Search, lookups, summarising evidence, mechanical edits, scoped slices from a complete brief |
| standard | Implementation that needs exploration or judgement, routine and critical review |
| strong | Hard design, debugging, reviewing standard-tier work that is non-trivial |
| strongest | Critical review of harm a revert cannot undo that reaches production data, backups, secrets or credentials, money, or real people's data (P4), deliberate architecture sessions |

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
  change to a required check, auth on a product with no live users yet, and
  auth on a product with live users unless its brief shows a revert cannot
  undo the harm (data already exposed).
- **Reviewer or light reviewer**: docs and ADRs (the code that implements
  them is reviewed on its own), agent tooling (hooks, skills, policy
  wording), renames, version bumps CI proves, staging-only changes, moving
  jobs between runners, a change its brief rates low or normal risk, and
  every re-check of a fix given the finding (P4a).

Why: critical review at the strongest tier was a large share of delegated
spend, and much of it went to fix re-checks, repeats of one change across
repositories, and changes where a mistake could do no critical harm. A
standard-tier critical review found most of what the strongest one found, at
a fraction of the cost; what it missed was an operator rollout step on a
change touching a credential. A split that relied on each caller lowering
the model did not hold, since callers left the role's defaults in place, so
each stake is its own role.

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
standard. The table sizes both the coordinator, from the brief as a whole,
and each implementer slice, from that slice alone; a mechanical slice can run
at fast under a standard coordinator. The Model line names the tier's model from the adapter's
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
at least twice one of 200. The count covers the coordinator and every
implementer it delegates to, but not review, since a delegated
implementer's responses cost about the same as the coordinator's; review is
mandatory (P4) and budgeted in its role. One implementer stops past about
100 responses ([delegation.md](delegation.md#implementer-slices)), so an M
brief runs as two or more slices.

Why: briefs expected to be one slice ran to several hundred responses with
repeated compactions, and the total response count, not who made the
responses, drove their cost.

| Size | Responses | How it runs |
|---|---|---|
| S | up to 100 | one slice |
| M | up to 200 | one session, planned as phases that each end in proof, each phase one or more implementer slices |
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

The fast tier for briefs is still being tried: a fast-tier session that
asks to be moved up says so in its closeout, so a cost review can weigh how
often the table's fast rows held.

## Signals to go down

The brief fully specifies the change; the check is objective (compiler,
snapshot, lint); output is formulaic.
