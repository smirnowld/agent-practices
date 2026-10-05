# Phase <N>: <name>

<!-- The current phase, at a glance (P19). One screen should tell me where
it stands. The only place for status (practices/planning.md, "Two files per
phase"). Plain words: rows name what they deliver; package IDs appear only in
the Packages column. Replaced when the phase ends, after its outcomes move to
the roadmap and docs. Budget: practices/record-keeping.md. -->

**Goal:** <what the user can see or do when this phase ends>
**Status:** <on track | at risk | blocked> — <one sentence why>
**Progress:** <done>/<total> packages · **Started:** <date> · **Expected:** <date range>
**Waiting on the maintainer:** <decision or acceptance, with link — or "nothing">

## Order

<!-- The dependency picture. Keep under ~15 nodes; group small items. -->

```mermaid
flowchart LR
  classDef done fill:#cfe8cf,stroke:#3a7d3a
  classDef active fill:#fff1c2,stroke:#b58900
  classDef blocked fill:#f6cccc,stroke:#b03030
  classDef parked fill:#eeeeee,stroke:#999999,stroke-dasharray:4
  A[OUTCOME A]:::done --> B[OUTCOME B]:::active
  A --> C[OUTCOME C]:::blocked
  B --> D[OUTCOME D]
  C --> D
```

## Items

<!-- One row per deliverable, in user terms, with one status; split a
deliverable only where its packages' statuses differ. Status: Done, In
review, In progress, Ready, Not started, Blocked: <why>, Engineering
complete and Parked (both link the phase plan's section, where the
blocked criteria or the reason live). Needs = open packages only. Link = PR or
issue URL, or the package's section in the phase plan as a SHA permalink
(P18) until a PR exists. -->

| Delivers | Packages | Status | Needs | Link |
|---|---|---|---|---|
| <plain-language outcome> | WPA, WPB | Done | — | <PR URL> |
| <outcome> | WPC | In progress | — | <PR URL> |
| <outcome> | WPD | Blocked: <why> | WPC | <phase plan section, SHA permalink> |

## Acceptance

<What I will check to accept the phase, as the user would experience it.
Evidence per the acceptance-evidence skill.>

## Not in this phase

- <item> — <which phase or "later">

## Risks

<!-- Only live ones. Omit if none. -->
- <risk> — <mitigation>
