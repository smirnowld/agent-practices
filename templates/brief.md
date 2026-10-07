# Brief: <title>

<!-- A work package for another session or agent (policy P2c). Conclusions,
not reasoning. The receiver must not need the sender's transcript. The title
follows templates/session-title.md and is the proposed session's title. -->

**Model:** <tier> (<model>) at <effort> (exploration <none | bounded | open>, reasoning <specified | judgement | open>; work briefs only)  <!-- the coordinator's tier; slices are sized under Delegation. practices/model-sizing.md, "Tier for a brief"; <model> is the adapter tiers.json name for the tier; P2d check -->
**Risk:** <low | normal | critical: what a mistake can do | critical, irreversible: what a revert cannot undo>  <!-- sets the reviewer, P4; irreversible only for harm reaching production data, backups, secrets, money or real people's data -->
**Size:** <XS | S | M>  <!-- response budget: practices/model-sizing.md, "Size in responses" -->
**Autonomy:** <Auto | Sign-off | Ask | With me>  <!-- what the session needs from me: templates/session-title.md -->
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

## Secrets

<!-- Templates this session may run with `with-secrets` (policy P10), or
none. Each line: the template path and what it is for. -->
- <template path: use | none>

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

<!-- Commands and statuses that must be green; evidence for acceptance. All
of it must be shown by merge: a check on staging or any later deploy is not
proof, and the session does not wait for one unless Work names it (`merge`
skill). A check only a deploy can show goes in Work, and the PR marks it
untested (P5). In a project with a staging or demo seed, what the seed must hold to
show the work, or why it needs none (practices/project-baseline.md, O5). -->
- <command or check>

## Delegation

<!-- The receiver coordinates: source and test changes go to implementer
slices, wide reading to an explorer, review always delegated (P2b,
practices/delegation.md). -->
- Implementer: <slice: files and proof>, <tier> at <effort>  <!-- one line per slice -->
- Explorer: <none | question and bound>
- Review: <light reviewer | reviewer | critical reviewer | strongest critical reviewer>, focus <...>
- Coordinator edits: <none | one config file by repo path>  <!-- the only non-doc file the coordinator may edit itself; set by the brief's author -->

## Handoff

<!-- A prerequisite is named by PR number or URL, never by session or branch
name; the receiver waits for it with `wait-for pr-merged PR` (merge skill). -->
<Where the result goes (PR URL, message to parent), what to report, when to stop
and ask. At the budget, or on a fast-tier brief at a signal to go up
(practices/model-sizing.md), progress update, then stop.>
