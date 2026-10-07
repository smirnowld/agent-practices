---
name: merge
description: Merge your own pull request once P6 allows it. Picks the merge method, enables auto-merge pinned to the reviewed commit, waits for CI with one background wait-for call that wakes the session on every outcome, confirms the merge, cleans up and runs the closeout skill.
---

# Merge

Goal: a verified, reviewed PR reaches the default branch without an
unreviewed commit slipping in and without polling. The project's own merge
procedure, if it has one, replaces this skill, except for the P6a
safeguards, which always hold: never bypass branch protection (no admin
override such as `gh pr merge --admin`, no relaxing the ruleset; only I do,
for a case I name), and a critical change that the critical reviewer's
report puts on the P6a list is handed to me unless I OK it as P6a says (the
closeout asks). A critical change the report puts off the list merges once
the critical reviewer passes it, and the closeout says why it was safe. A
report without its P6a line clears nothing: get the line from the reviewer
or hand the merge to me. New
commits follow P4b: classify the commit's own risk; one I approved after
seeing its diff needs no new review if neither it nor the PR needs the
critical reviewer; a fix of a finding is confirmed by the reviewer given the
finding (P4a); any other gets a delta-only confirmation from the resumed
reviewer of the change's tier, the critical reviewer for a critical delta.
"The critical reviewer" here is either critical level (P4).
My OK carries over to a confirmed commit only if its own diff is off the
P6a list.

## 1. Check that merging is allowed

P6's merge conditions hold on the PR's head commit. Work marked untested
under P5 may lack a proof status for the blocked part; never create a fake
one. Auto-merge waits only for
checks the ruleset requires, so any other proof status (for example
`verified-locally/LANE`) must already be green before you enable it.

The base branch must require a status check pinned to GitHub Actions
(`integration_id` 15368). Without one, auto-merge merges at once, before CI:

```sh
gh api 'repos/{owner}/{repo}/rules/branches/BRANCH' --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[] | select(.integration_id==15368) | .context'
```

`wait-for` (step 4) reads the same checks. Empty output (including a branch
protected only by classic branch protection, which this endpoint does not
show): do not merge; tell me the PR is ready and that I merge (baseline R4).

A PR that cannot merge within the rules is handed to me (P6a).

## 2. Pick the method

In order: the method the project documents; else the ruleset's
`allowed_merge_methods` (the `pull_request` rule in the output above, without
the jq filter) together with the repository's allowed methods
(`gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`),
if only one remains; else the one recent merges used
(`git log --first-parent origin/DEFAULT`: merge commits mean merge, single
commits with PR numbers mean squash).

## 3. Enable auto-merge

The harness's permission check may refuse a merge until a reviewer verdict
is visible in this session. Get the verdict into the session, then merge in
the foreground; don't retry a combined wait-and-merge command after a
refusal.

```sh
gh pr merge PR --auto --METHOD --match-head-commit REVIEWED_SHA
```

`--match-head-commit` makes GitHub refuse the merge if the branch moved past
the reviewed commit. A PR that is already mergeable (checks green, nothing
pending) cannot get auto-merge; merge it directly with the same
`--match-head-commit` and go to step 5. Before any later push: stop your own
running wait (the adapter names the tool), then
`gh pr merge PR --disable-auto`,
get the new commits reviewed under P4b (delta only), then enable again with
the new SHA. Batch late fixes into one push so CI runs once.

## 4. Wait once, in the background

Wait with `wait-for` (`SKILL_DIR/../../bin/wait-for`, `SKILL_DIR` being the
folder holding this file; the adapter says whether it is on the PATH) as a
background task, so its exit wakes the session (adapter):

```sh
wait-for pr-ci PR
```

Start it right after step 3, so the PR's head is REVIEWED_SHA; its final line
names the commit it waited on, and a different one means start again from
step 3. It finds the run behind each required check from step 1 on that head and
waits on it with `gh run watch RUN_ID --exit-status`, and it ends on every
state: 0 CI passed (or the PR already merged), 1 a check failed, 2 PR closed,
3 head moved or auto-merge turned off, 4 merge conflict, 5 a state it cannot
read, 6 deadline (45 min; `--deadline MINUTES`). An unknown state ends the
wait; never restart it unchanged hoping it settles. Give the background task
a timeout above the deadline. Never end a turn saying you are waiting on CI
or a merge unless that wait is running; a CI monitor that reports only
failures is not a wait. Do not write your own polling loop, and do not rely
on `gh pr checks --watch`: it exits at once when no check has reported yet,
and exits green when the checks that have reported pass before the others
appear. If it exits 5 because no run appeared while CI is running, take the
id from `gh run list --branch BRANCH --commit REVIEWED_SHA` and wait with
`wait-for run RUN_ID`. A failed run: fix forward on the
same PR (P6) through an implementer slice that gets the failing lines (P2b),
then return to step 3.

## 5. Confirm and clean up

Auto-merge lands a few seconds after the run ends. Check once, and once more
after a short wait if needed:

```sh
gh pr view PR --json state,autoMergeRequest,mergeStateStatus
```

`state` must be `MERGED`. Otherwise report the cause from `wait-for`'s exit
code and final line, with `mergeStateStatus` and `autoMergeRequest` (a
pending required status, a conflict, auto-merge switched off). On exit 3
from your own push, go back to step 3; on 4, resolve the conflict on the
branch and go back to step 3; on 5 or 6, look once at the PR and its run and
report what you found; neither ever counts as passed. When the merge is someone else's (another session's PR you
depend on), wait for it with `wait-for pr-merged PR`; its exit 3 means the
author pushed or turned auto-merge off, so start it again (each run ends at
its deadline). Leave no wait of your
own running. Then clean up per P16: delete your local branch and worktree,
release your resources (P7).

## 6. Close out

Once `state` is `MERGED`, run the `closeout` skill now, in the same turn,
whether the merge was direct or auto-merge landed while you waited: it
rewrites the PR description with the post-merge record and writes the chat
summary. A closeout written without the skill, or a PR comment in place of
the description, is not one.

The session ends with the merge, cleanup and closeout. It does not wait for
or check a deploy (staging or otherwise) unless its brief names that step;
health after a deploy is the project's smoke tests and triage.
