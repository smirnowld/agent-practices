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
| Critical review | strongest / extra-high; the caller never lowers it |
| Parent session coordinating a written plan | standard / medium |
| Planning or analysis session | strong or strongest, chosen by me |

## Signals to go up

Repeated failed attempts, unclear root cause, many interacting files, a
reviewer finding the implementer missed something basic, anything in the P4
critical list.

## Signals to go down

The brief fully specifies the change; the check is objective (compiler,
snapshot, lint); output is formulaic.

## Evidence log

Forks: record notable outcomes (tier too weak or wasteful) here.
