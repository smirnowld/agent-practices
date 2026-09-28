# Brief: <title>

<!-- A work package for another session or agent (policy P2c). Conclusions,
not reasoning. The receiver must not need the sender's transcript. -->

**Model:** <tier> at <effort>  <!-- adapter maps tier to a model; P2d check -->
**Risk:** <low | normal | critical: category>  <!-- sets the reviewer, P4 -->
**Size:** <S | M>  <!-- response budget: practices/model-sizing.md, "Size in responses" -->
**Repo / branch / worktree:** <path>, <branch from base>

## Goal

<One or two sentences: the outcome, and how I will know it is done.>

## Settled decisions

<!-- Not to be reopened. Link the ADR or message where each was made. -->
- <decision> (<link>)

## Owned files and resources

<!-- Only these may be changed. Anything else: stop and report. -->
- <path or resource>

## Already verified

<!-- Facts the receiver must not re-establish. -->
- <fact> (<evidence: file:line, command, URL>)

## Work

1. <step>

## Proof

<!-- Commands and statuses that must be green; evidence for acceptance. -->
- <command or check>

## Delegation

<!-- What the receiver delegates and to which role; review is always delegated. -->
- Review: <reviewer | critical reviewer>, focus <...>
- Other: <none | role and slice>

## Handoff

<Where the result goes (PR URL, message to parent), what to report, when to stop
and ask. At the budget: progress update, then stop.>
