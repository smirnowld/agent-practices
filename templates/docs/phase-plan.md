# Phase <N> work packages: <name>

<!-- Product repos (P19), stored as docs/plans/phase-<N>.md. What the open
packages of the current phase must deliver, the rules for running them and
the estimate. No status: status, progress and pull request links live only in
plan.md, whose rows map to these package IDs. A package leaves this file when
it merges; its outcome lives in the code, contracts, ADRs and READMEs, and
git keeps the rest. Written by the planning session and accepted by me before
the first brief. Deleted when the phase ends, after its lasting outcomes move
to the roadmap and docs. Budget: 30 KB. -->

<Accepted by me on DATE; packages added later name their source.> Each work
package is one agent, one lane and one pull request (or a small series), with
criteria a reviewer can check. Size: S = <measure>, M = <measure>; an L
package is split before it is briefed. At a glance: [plan.md](../plan.md).

**Goal:** <what the user can see or do when this phase ends>

**Not in this phase:** <what is deliberately left out, and where it goes>

## Order and dependencies

<!-- Open packages only; every dependency not listed has merged. -->

```
<Lane>:   WP<A> ─► WP<B>   <what each delivers, a few words>
<Lane>:   WP<C>            <what it delivers>
```

**Parallelism rule:** <which packages may run at the same time and which
must wait, with the shared files or resources that force the order>.

## Completion states

<!-- How a package, and the phase, is reported: never a bare "done" where
part of it depends on something outside the repository. -->

- **Engineering complete:** <every criterion that depends only on the repository is met and verified>.
- **Externally blocked:** <the rest needs an account, a third party or someone's data; that work is written, marked untested, and the blocker named>.

The phase is **engineering complete** when <...>. It is **finished** when <...>.

## Pending inputs and when they start to block

| Input | Blocks | Until then |
|---|---|---|
| <account, data, decision> | <packages or steps> | <the stand-in used meanwhile> |

## Open packages

### WP<N> <Lane>: <what it delivers> (<lane>, <size>; <ADR link if any>)

<Scope in a few sentences: what it builds, where the logic lives, what it
must not do. Name the decision or question it rests on.>

Done when: <criteria a reviewer can check, demoable where the project
demands it>.

## Parked packages

<!-- Omit if none. A package paused by my decision, with the condition that
brings it back. -->

### WP<N> <Lane>: <what it would deliver> (<lane>, <size>)

Briefed only if <condition> (<my decision, date, link>). <Scope and "Done
when", kept so it can be briefed without replanning.>

## Estimate

<Packages by size, planned agent-days, the longest chain, and the calendar
range with what the measurement does not cover (practices/planning.md).>

## Review at the end of the phase

<Re-measure, compare with the estimate, move lasting outcomes into the
roadmap and current-state docs, and write the next phase's plan in this
shape.>
