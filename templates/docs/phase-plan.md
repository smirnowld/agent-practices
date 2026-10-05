# Phase <N> work packages: <name>

<!-- Product repos (P19), stored as docs/plans/phase-<N>.md: the phase's
living plan (P17). Scope of the open packages, no status; what belongs here
and when a package leaves: practices/planning.md, "Two files per phase".
Budget: practices/record-keeping.md. -->

<Accepted; packages added later name their source.> Each work
package is one agent and one pull request (or a small series), with criteria
a reviewer can check. Package IDs are `WP` plus a number that continues
across phases and is never reused. Size per `practices/model-sizing.md`; an L
package is split before it is briefed. Status: [plan.md](../plan.md).

**Goal:** <what the user can see or do when this phase ends>

**Not in this phase:** <what is deliberately left out, and where it goes>

## Order and dependencies

<!-- Open packages only; every dependency not listed has merged. AREA is the
project's own split of work (a lane, a platform, a component), if it has
one. -->

```
AREA:   WPA ─► WPB   what each delivers, a few words
AREA:   WPC          what it delivers
```

**Parallelism rule:** <which packages may run at the same time and which
must wait, with the shared files or resources that force the order>.

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
externally blocked criteria, until it is finished. -->

### WP<N>: <what it delivers> (<area, if any>; <size>; <ADR link, if any>)

<Scope in a few sentences: what it builds, where the logic lives, what it
must not do. Name the decision or question it rests on.>

Done when: <criteria a reviewer can check>.

## Parked packages

<!-- Omit if none. Parking is a scope decision of mine and is recorded only
here; plan.md shows "Parked" and links this section. -->

### WP<N>: <what it would deliver> (<area, if any>; <size>)

Briefed only if <condition> (<my decision, date, link>). <Scope and "Done
when", kept so it can be briefed without replanning.>

## Estimate

<!-- As accepted; not updated as packages leave, so the end-of-phase review
can compare (practices/planning.md). A package added later is added with
its source, so the review can tell the two apart. -->

<Packages by size, the longest chain of dependent packages, and the calendar
range with what it leaves out (acceptance, review rounds, outside inputs).>
