# Brief: <title>

<!-- A work package for another session or agent (policy P2c). Conclusions,
not reasoning. The receiver must not need the sender's transcript. -->

**Model:** <tier> (<model>) at <effort> (exploration <none | bounded | open>, reasoning <specified | judgement | open>; work briefs only)  <!-- practices/model-sizing.md, "Tier for a brief"; <model> is the adapter tiers.json name for the tier; P2d check -->
**Risk:** <low | normal | critical: category>  <!-- sets the reviewer, P4 -->
**Size:** <S | M>  <!-- response budget: practices/model-sizing.md, "Size in responses" -->
**Repo / branch / worktree:** <path>, <branch from base>

## Goal

<One or two sentences: the outcome, and how I will know it is done.>

## Settled decisions

<!-- Not to be reopened. Link the ADR or message where each was made. -->
- <decision> (<link>)

## Core files and resources

<!-- Where the work is expected. Other files may change under fix on the go
(policy P6, practices/scope-and-batching.md); log them in the report. -->
- <path or resource>

## No-go

<!-- Never changed by this session: files and resources another session
holds, ADR statuses, secrets and infrastructure, plus anything listed here. -->
- <path or resource>

## Related issues

<!-- Open issues (deferred-review too) on the core files or goal. Fix each
that passes the fix-on-the-go test in this PR (Fixes #N); report the rest. -->
- <#N: title | none found>

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
and ask. At the budget, or on a fast-tier brief at a signal to go up
(practices/model-sizing.md), progress update, then stop.>
