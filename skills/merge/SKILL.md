---
name: merge
description: Merge your own pull request once P6 allows it. Picks the merge method, enables auto-merge pinned to the reviewed commit, waits for CI in one blocking call, confirms the merge and cleans up.
---

# Merge

Goal: a verified, reviewed PR reaches the default branch without an
unreviewed commit slipping in and without polling. The project's own merge
procedure, if it has one, replaces this skill, except for the P6a
safeguards, which always hold: never bypass branch protection (no admin
override such as `gh pr merge --admin`, no relaxing the ruleset; only I do,
for a case I name), and a change that needs the critical reviewer under P4
is handed to me to merge.

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

Keep the printed check name for step 4. Empty output (including a branch
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

An auto-mode permission classifier may refuse a merge until a reviewer
verdict exists in the session. Run the review first, then merge in the
foreground; don't retry a combined watch-and-merge command after a refusal.

```sh
gh pr merge PR --auto --METHOD --match-head-commit REVIEWED_SHA
```

`--match-head-commit` makes GitHub refuse the merge if the branch moved past
the reviewed commit. A PR that is already mergeable (checks green, nothing
pending) cannot get auto-merge; merge it directly with the same
`--match-head-commit`. Before any later push: `gh pr merge PR --disable-auto`,
get the new commits reviewed, then enable again with the new SHA.

## 4. Wait once

Find the run behind the required check from step 1 on the reviewed commit
(the run id is in the details URL, `.../actions/runs/RUN_ID/job/...`) and
block on it:

```sh
gh api 'repos/{owner}/{repo}/commits/REVIEWED_SHA/check-runs' --jq '.check_runs[] | select(.name=="CHECK") | .details_url'
gh run watch RUN_ID --exit-status
```

Just after a push the check can be missing; wait briefly and look once
more. Do not poll. Do not rely on `gh pr checks --watch`: it exits at once when no
check has reported yet, and exits green when the checks that have reported
pass before the others appear. If no run appears for the check while CI is
running, take the id from `gh run list --branch BRANCH` and block on that. A failed run: fix forward on the same PR (P6),
then return to step 3.

## 5. Confirm and clean up

Auto-merge lands a few seconds after the run ends. Check once, and once more
after a short wait if needed:

```sh
gh pr view PR --json state,autoMergeRequest,mergeStateStatus
```

`state` must be `MERGED`. Otherwise report the cause from `mergeStateStatus`
and `autoMergeRequest` (a pending required status, a conflict, auto-merge
switched off). Then clean up per P16: delete your local branch and worktree,
release your resources (P7).
