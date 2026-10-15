# Phase <N> work packages: <name>

<!-- Product repos (P19), stored as docs/plans/phase-<N>.md: the phase's
living plan (P17). Scope of the open packages, no status; what belongs here
and when a package leaves: practices/planning.md, "Two files per phase".
Budget: practices/record-keeping.md. -->

<Accepted; packages added later name their source.> Each work
package is one agent and one pull request (or a small series), with criteria
a reviewer can check. Package IDs are `WP` plus a number that continues
across phases and is never reused. Size per `practices/model-sizing.md`; an L
package is split before it is briefed. Status: on the [board](<board link,
Phase view; left out in a public repository>), or in [plan.md](../plan.md)
before the project's switch to a board. Order of outcomes:
[plan.md](../plan.md).

**Goal:** <what the user can see or do when this phase ends>

## Acceptance

<What the maintainer checks to accept the phase, as the user would
experience it. Evidence per the acceptance-evidence skill.>

## Not in this phase

- <item> — <which phase or "later">

## Risks

<!-- Only live ones. Omit if none. -->
- <risk> — <mitigation>

## Running the packages

<!-- Open packages only. AREA is the project's own split of work (a lane, a
platform, a component), if it has one. -->

**Package order:** the issues' blocked-by links on the board.

**Lanes:** <AREA: the packages in it, if the project splits work this way>

**Parallelism rule:** <which packages may run at the same time and which
must wait, with the shared files or resources that force the order>.

<!-- A project not yet on a board keeps the order chain here instead of the
"Package order" line; every dependency not listed has merged:

AREA:   WPA ─► WPB   what each delivers, a few words
AREA:   WPC          what it delivers
-->

## Completion states

- **Engineering complete:** <every criterion that depends only on the repository is met and verified>.
- **Externally blocked:** <the rest needs an account, a third party or someone's data; that work is written, marked untested (P5), and the blocker named>.

The phase is **engineering complete** when <...>. It is **finished** when <...>.

## Pending inputs and when they start to block

| Input | Blocks | Until then |
|---|---|---|
| <account, data, decision> | <packages or steps> | <the stand-in used meanwhile> |

## Open packages

<!-- A package merged as engineering complete stays here, reduced to its
externally blocked criteria, until it is finished. Each package links its
work-package issue, which in turn links this section at a commit SHA and
never copies the criteria (practices/tracking.md). Outcome names the
plan.md diagram node it delivers, with the same label. -->

### WP<N>: <what it delivers> (<area, if any>; <size>; <ADR link, if any>)

Issue: <#N | package ID only, in a public repository>
Outcome: <OUTCOME LABEL from the plan.md diagram>

<Scope in a few sentences: what it builds, where the logic lives, what it
must not do. Name the decision or question it rests on.>

Done when: <criteria a reviewer can check>.

## Parked packages

<!-- Omit if none. Parking is a scope decision of mine and is recorded only
here; the board mirrors it as Parked. -->

### WP<N>: <what it would deliver> (<area, if any>; <size>)

Issue: <#N | package ID only, in a public repository>
Outcome: <OUTCOME LABEL from the plan.md diagram>

Briefed only if <condition> (<the maintainer's decision, date, link>).
<Scope and "Done when", kept so it can be briefed without replanning.>

## Estimate

<!-- As accepted; not updated as packages leave, so the end-of-phase review
can compare (practices/planning.md). A package added later is added with
its source, so the review can tell the two apart. Phase health and the
expected end date go in the board's project status update; when the board
has none, the Expected end line holds the
date (practices/tracking.md, "Fields"). It is the one line here that is
updated. -->

<Packages by size, the longest chain of dependent packages, and the calendar
range with what it leaves out (acceptance, review rounds, outside inputs).>

**Expected end:** <date range>  <!-- only when the board has no status update; the one line kept current -->
