---
name: merge
description: Merge your own pull request once P6 allows it. Picks the merge method, enables auto-merge pinned to the reviewed commit, waits for CI in one blocking call, confirms the merge and cleans up.
---

# Merge

Goal: a verified, reviewed PR reaches the default branch without an
unreviewed commit slipping in and without polling. The project's own merge
procedure, if it has one, replaces this skill.

## 1. Check that P6 allows it

All must hold on the PR's head commit: work verified, review passed (blocking
findings fixed and confirmed, deferred ones filed per P4), every status the
project treats as proof present and green or pending, nothing awaiting my
answer or acceptance, and the critical reviewer was not required.

The base branch must require a status check pinned to GitHub Actions.
Without one, auto-merge merges at once, before CI:

```sh
gh api repos/OWNER/REPO/rules/branches/BRANCH --jq '.[] | select(.type=="required_status_checks")'
```

Empty output: do not merge; tell me the PR is ready and that I merge
(baseline R4).

## 2. Pick the method

In order: the method the project documents; else the only one the repository
allows (`gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`);
else the one its recent merges used (`git log --first-parent` on the default
branch: merge commits mean merge, single commits with PR numbers mean squash).

## 3. Enable auto-merge

```sh
gh pr merge PR --auto --METHOD --match-head-commit REVIEWED_SHA
```

`--match-head-commit` makes GitHub refuse the merge if the branch moved past
the reviewed commit. Before any later push: `gh pr merge PR --disable-auto`,
get the new commits reviewed, then enable again with the new SHA.

## 4. Wait once

Find the head commit's CI run and block on it:

```sh
gh run list --commit REVIEWED_SHA --json databaseId,workflowName
gh run watch RUN_ID --exit-status
```

Do not poll. `gh pr checks --watch` returns at once while no check has
reported yet, so it can look green before CI started. A failed run: fix
forward on the same PR (P6), then return to step 3.

## 5. Confirm and clean up

`gh pr view PR --json state --jq .state` must print `MERGED`; if not, report
why (a pending required status, a conflict). Then clean up per P16: delete
your local branch and worktree, release your resources (P7).
