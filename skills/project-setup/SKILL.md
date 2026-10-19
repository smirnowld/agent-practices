---
name: project-setup
description: Bring a repository to the project baseline (P19, P20, practices/project-baseline.md), or audit it against the baseline (monthly routine, baseline T3). Setup mode makes changes through a PR; audit mode is read-only and reports gaps.
---

# Project setup

Two modes, same checklist: `practices/project-baseline.md`.

- **Setup:** a new repository, or one I asked to bring up to the baseline.
- **Audit:** read-only; run monthly by the local routine or on request.

## 1. Establish the facts

- Repo type (product, infrastructure, tooling) from `AGENTS.md`. Missing:
  propose one with the reason and ask me (P6); do not assume.
- Accessibility level (P22) from `AGENTS.md`. Missing: R8 is a gap;
  propose a level from who uses the project (`practices/accessibility.md`)
  and ask me (P6); do not assume.
- Public or private; hosting plan (see R4 in `practices/project-baseline.md`).
- Deployed or not; holds user data or not; has code beyond docs; has
  `docs/adr/`; has a staging or demo environment, and how its data is reset.
- Languages and package ecosystems, for Dependabot and scanners.
- Existing CI entry point and aggregate check name.
- The project's board (R7): linked from `AGENTS.md`, or for a public
  repository named in my own agent configuration; and the template board's
  owner and number, from my own agent configuration. Missing: ask me. Never
  write a board's owner, number or URL into agent-practices.

These decide which rows apply. Record them at the top of the output.

## 2. Check each row

For every applicable row, find evidence: file path, setting read through the
host's API, workflow run URL. Report per `practices/project-baseline.md`
("Audit output"):

`<#> <item> — present | missing | partial: <what> | n/a: <why>`

"Present" needs evidence; a setting assumed on is "unknown", which counts as
missing. Rows that depend on external services (O1–O4) are checked from the
observability manifest and a live health call; `triage` owns the signals.

For O5, find the seed in the repository, the job that resets staging or the
demo to it, and the seed rule in `AGENTS.md`. A seed without the reset or
without the rule is "partial"; setup adds the rule, and a missing reset job
is a gap for me (it changes infrastructure, P9). With no seed at all, O5 is
"missing" and creating the seed is a gap for me; setup adds the rule only
together with the seed.

For R1, a present block must also be current: run
`scripts/sync-policy.sh --check <project>` from a local agent-practices
clone, and check that the project is listed in agent-practices' Actions
variable `POLICY_SYNC_REPOS` (`gh variable get POLICY_SYNC_REPOS --repo
<agent-practices>`). A stale copy or a missing listing is "partial"; setup
appends the project to the listing (a host setting, P9; `gh variable set`
replaces the whole value, so read it first), then starts the workflow with
`gh workflow run sync-policy.yml --repo <agent-practices>` to bring the copy
current.

For R6, run `scripts/ensure-labels.sh --check <owner/repo>` (read-only; exit
1 names each label missing or different). Any gap is "partial" or "missing".

For R7, run `scripts/ensure-board.sh --check <owner> <number>
<template-owner> <template-number>` (read-only), adding `--threads` for the
shared board. Exit 1 lists each field,
option, view or workflow that differs from the template, or a workflow that
is missing or disabled: R7 is "partial". Exit 2 means a board could not be
read or the template number is not the template: R7 is "missing" when the
project has no board, otherwise report the error. Workflow settings, the
auto-add filter, the description and the base role have no API: they stay
"unknown" unless I confirm them or they are read in my browser. Missing
fields, options or views (the template changed after the copy) are fixable
by `--sync` in setup mode (below). R7 also needs the work-package issue
template at
`.github/ISSUE_TEMPLATE/work-package.md`, matching
`templates/github/work-package-issue.md`; missing or different is
"partial".

For C4 and C5, run `scripts/check-action-pins.py <project>` and
`scripts/check-adrs.py <project>` from a local agent-practices clone. Exit 1
names each failing line (an unpinned `uses:`; an ADR status, numbering or
index problem); exit 2 means the path is wrong or holds no workflow, or
no `docs/adr/`, which makes C5 "n/a: no ADRs" rather than a failure.
"Present" also needs the project's check entry point (`make check`) to run
each check; the scripts have no dependencies, so setup copies them into the
project's `scripts/`. A copy that differs from the
agent-practices version is "partial: check out of date"; setup replaces it.
C5 with ADRs also needs the PR-mode job in CI, gated by the aggregate job
and triggered on `edited`
([project-baseline.md](../../practices/project-baseline.md#adr-ruling-line-in-prs));
without it, C5 is "partial: no PR-mode job".

In audit mode, stop here and deliver the report (step 5).

## 3. Plan the fixes (setup mode)

Sort gaps into:

- **Can fix in the repo:** files (`AGENTS.md` type line and policy block,
  docs from `templates/docs/`, the work-package issue template
  (`templates/github/work-package-issue.md` copied to
  `.github/ISSUE_TEMPLATE/work-package.md`), `SECURITY.md`, Dependabot config, CI lanes,
  pinned actions and the pin check, the ADR check, scanners, `make check`).
- **Can fix through the host's API:** auto-merge, branch deletion, ruleset,
  security features, issue labels (R6). These change settings: list them and
  get my OK first (P9). Labels are applied with
  `scripts/ensure-labels.sh <owner/repo>`, which is idempotent. The board
  (R7) is created with `scripts/ensure-board.sh create <owner> "<title>"
  <template-owner> <template-number> --repo <owner/repo>`, adding
  `--with-kind` for a board that holds draft items (it adds Kind, Area and
  a Drafts by kind view; Area's options are the board's own and reruns
  never change them). When a public repository's work moves to the shared
  board, add the repository's name as an Area option there. The shared
  board also takes `--threads` (Focus, Rank, Next step and the two Threads
  views, `practices/tracking.md`, Threads); no other board does. Templates exist
  in organisations only; a user's board is copied across owners from the
  organisation's template. A board copied before the template changed is
  brought up to it with `scripts/ensure-board.sh --sync <owner> <number>
  <template-owner> <template-number>`: show me its `--dry-run` output first.
  It only adds what is missing, never deletes or renames, and reports the
  rest. The script is idempotent. The board link goes into `AGENTS.md`, except for a
  public repository, whose board is named in my own agent configuration
  instead (`practices/tracking.md`, "Finding the board").
- **Needs the board's settings page:** the steps `ensure-board.sh` prints
  (auto-add from the repository with `is:issue -label:initiative`, base
  role No access, the description linking the Assigned to me view and
  `docs/questions.md`, workflows that differ). Where the adapter names a browser
  I am signed in to, offer to do them there; otherwise list them for me.
- **Needs me:** accounts, paid plans, secrets, choosing a monitoring or
  hosting tool (then an ADR, P11).

Order: CI and the aggregate check first, then the ruleset that requires it
(a ruleset without a check lets auto-merge merge at once), then the rest.

## 4. Apply (setup mode)

One PR for repository files, grouped commits per section of the checklist.
Docs and policy text are the coordinator's; CI lanes, workflows, scanners,
Makefile targets and other source or config go to implementer slices (P2b),
one per checklist section, each with the check that proves it.
New docs start from the templates, with only facts that are known; unknowns
go to the question register (`templates/docs/questions.md`) or my open
points, never invented. CI must pass on the PR, including new lanes; a new scanner's first findings are reported, not
suppressed. Review per P4; security lanes and rulesets are release-critical
work for the reviewer choice. Host settings are applied after my OK and
recorded in the PR description with the command used.

## 5. Output

- The row-by-row report with evidence links (P18).
- Setup mode: the PR URL, settings changed, what still needs me.
- Audit mode: gaps only, grouped as "can fix" and "needs me"; if any, the
  routine proposes a session (`brief` skill) for a setup
  session covering the "can fix" list.
- For a new project: the routine entries to add (routines
  T1–T4 that apply, titled per `templates/session-title.md`), for me to paste; the skill does not edit that list.
