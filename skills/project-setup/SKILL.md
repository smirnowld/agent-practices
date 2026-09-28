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
- Public or private; hosting plan (see R4 in `practices/project-baseline.md`).
- Deployed or not; holds user data or not; has code beyond docs.
- Languages and package ecosystems, for Dependabot and scanners.
- Existing CI entry point and aggregate check name.

These decide which rows apply. Record them at the top of the output.

## 2. Check each row

For every applicable row, find evidence: file path, setting read through the
host's API, workflow run URL. Report per `practices/project-baseline.md`
("Audit output"):

`<#> <item> — present | missing | partial: <what> | n/a: <why>`

"Present" needs evidence; a setting assumed on is "unknown", which counts as
missing. Rows that depend on external services (O1–O4) are checked from the
observability manifest and a live health call; `triage` owns the signals.

For R1, a present block must also be current: run
`scripts/sync-policy.sh --check <project>` from a local agent-practices
clone. A stale copy is "partial: policy block out of date" and proposes a
sync session.

For R6, run `scripts/ensure-labels.sh --check <owner/repo>` (read-only; exit
1 names each label missing or different). Any gap is "partial" or "missing".

For C4, run `scripts/check-action-pins.py <project>` from a local
agent-practices clone (exit 1 names each unpinned `uses:`; exit 2 means the path is wrong or holds no workflow). "Present" also
needs the project's `make check` to run the check; the script has no
dependencies, so setup copies it into the project's `scripts/`. A copy that
differs from the agent-practices version is "partial: pin check out of date";
setup replaces it.

In audit mode, stop here and deliver the report (step 5).

## 3. Plan the fixes (setup mode)

Sort gaps into:

- **Can fix in the repo:** files (`AGENTS.md` type line and policy block,
  docs from `templates/docs/`, `SECURITY.md`, Dependabot config, CI lanes,
  pinned actions and the pin check, scanners, `make check`).
- **Can fix through the host's API:** auto-merge, branch deletion, ruleset,
  security features, issue labels (R6). These change settings: list them and
  get my OK first (P9). Labels are applied with
  `scripts/ensure-labels.sh <owner/repo>`, which is idempotent.
- **Needs me:** accounts, paid plans, secrets, choosing a monitoring or
  hosting tool (then an ADR, P11).

Order: CI and the aggregate check first, then the ruleset that requires it
(a ruleset without a check lets auto-merge merge at once), then the rest.

## 4. Apply (setup mode)

One PR for repository files, grouped commits per section of the checklist.
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
  routine proposes a session with a brief (`templates/brief.md`) for a setup
  session covering the "can fix" list.
- For a new project: the routine entries to add (routines
  T1–T4 that apply), for me to paste; the skill does not edit that list.
