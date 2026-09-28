# Project baseline

The automations and settings every repository has, by type (P19, P20). The
`project-setup` skill applies this list and audits against it. Rows marked
"when" apply once the condition holds. Hosting is assumed to be GitHub; a
project elsewhere maps each row to its host's equivalent.

## Checklist

| # | Item | product | infrastructure | tooling |
|---|---|---|---|---|
| **Repository** |||||
| R1 | `AGENTS.md` declares the type and carries the synced policy block; vendor-specific agent files only import it | ✓ | ✓ | ✓ |
| R2 | Required docs for the type (P19), with visuals for product docs | ✓ | ✓ | README |
| R3 | Auto-merge allowed; head branches deleted on merge | ✓ | ✓ | ✓ |
| R4 | Default-branch ruleset: pull request required, no deletion, no force push, one aggregate check pinned to GitHub Actions | ✓ | ✓ | ✓ |
| R5 | Public repos: licence, `SECURITY.md`, private vulnerability reporting on | when public | when public | when public |
| R6 | Issue labels: `deferred-review`, and priorities `p1` (blocks planned work, or risks users or data), `p2` (belongs in the current or next phase), `p3` (when convenient) | ✓ | ✓ | ✓ |
| **CI** |||||
| C1 | Checks run on every PR and on the default branch | ✓ | ✓ | ✓ |
| C2 | One aggregate job the ruleset requires; lanes skip only when not applicable, never fake green (note below) | ✓ | ✓ | ✓ |
| C3 | The same checks run locally through one entry point (e.g. `make check`) | ✓ | ✓ | ✓ |
| C4 | Actions, first-party included, pinned to a commit SHA with a comment ending in the version (`# vX.Y.Z`), enforced by a pin check | ✓ | ✓ | ✓ |
| C5 | ADR check (`scripts/check-adrs.py`): status lines, numbering without gaps, index (`templates/docs/adr-index.md`) complete with no archived ADR listed | when ADRs | when ADRs | when ADRs |
| **Dependencies** |||||
| D1 | Dependabot version updates, weekly, grouped per ecosystem, including GitHub Actions | ✓ | ✓ | ✓ |
| D2 | Dependabot security updates on | ✓ | ✓ | ✓ |
| D3 | Licence check against an allow-list | ✓ | — | when published |
| D4 | Dependencies pinned to exact versions, lockfile committed | ✓ | ✓ | ✓ |
| **Security** |||||
| S1 | Secret scanning: GitHub's with push protection when public; a free scanner in CI (e.g. gitleaks) when private | ✓ | ✓ | ✓ |
| S2 | Code scanning: GitHub CodeQL when public; a free scanner in CI (e.g. Semgrep Community Edition) when private | ✓ | when code | when code |
| S3 | Secrets only in the host's secret store or my vault, named in docs (P10) | ✓ | ✓ | ✓ |
| **Operations** (when deployed) |||||
| O1 | Observability contract: health, manifest in `docs/operations.md` (`practices/observability.md`) | ✓ | ✓ | — |
| O2 | Minimum monitoring for the type: uptime, logs, errors, alerts with runbooks | ✓ | ✓ | — |
| O3 | Backups with a tested restore; `docs/recovery.md` with the last test date | when user data | ✓ | — |
| O4 | Restore test at least quarterly | when user data | ✓ | — |
| **Routines** (scheduled, one entry per project) |||||
| T1 | Weekly docs drift check (`docs-drift-check`) | ✓ | ✓ | when docs beyond README |
| T2 | Daily triage of errors, alerts, uptime and logs (`triage`) | when deployed | ✓ | — |
| T3 | Baseline audit (`project-setup`, audit mode), monthly | ✓ | ✓ | ✓ |
| T4 | Open issues reviewed every three days (`issue-review`) | ✓ | ✓ | ✓ |

## Security scanning cost

GitHub's code scanning and secret scanning are free on public repositories.
On private ones they need the paid GitHub Code Security or Secret Protection
add-ons, sold only with Team or Enterprise plans
(https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security,
checked 2026-09-27; per-committer prices not confirmed on the pricing page).
The CodeQL CLI's licence reportedly also excludes private code without the
add-on (unverified).
Private repositories therefore run open-source scanners as a CI lane; the
only cost is CI minutes.

## Pins and new dependencies

- **Exact versions** (P20). Manifests name exact versions, not ranges, so a
  build changes only through a reviewed PR. Update PRs move the pins.
- **New dependencies.** The PR says why it is needed and why existing code or
  dependencies do not cover it. A novel one (a new runtime, framework, service
  or vendor) also gets an ADR, listed in the tech-stack doc.
- **Action pins.** Write `uses: OWNER/ACTION@SHA # vX.Y.Z` with the version as
  the last thing on the line. Dependabot rewrites the comment only when it
  ends with the old version; any trailing text leaves a stale version next to
  the new SHA. The pin check fails on a missing SHA or a comment that does not
  end in a version. Learnt in a product repo, 2026-09-27.

## Dependency update PRs

Dependabot PRs follow P4 like any change, scaled to risk:

- Patch and minor updates with green CI: a fast-tier reviewer checks the
  changelog for breaking notes, then auto-merge.
- Major updates, runtime or framework updates, and anything touching auth,
  crypto or data access: normal review, and the critical reviewer where P4
  says so.
- A failing update is fixed on its PR or closed with the reason; it is never
  left open silently.

## Audit output

`project-setup` in audit mode reports one line per applicable row:
`<#> <item> — present | missing | partial: <what> | n/a: <why>`, then the
fixes it can make itself and the ones that need me (accounts, paid plans,
secrets). Private repositories on a free personal plan cannot have rulesets;
report R4 as "not available: plan" and note that I merge.

## Why

Consistent automation means the routines, reviews and dashboards work the
same in every project, gaps are visible instead of silent, and a new project
reaches a known-good state in one session.

**C2 note: aggregate gate conditions.** A gate with `if: ${{ !cancelled() }}`
still runs when a job it needs times out: `cancelled()` describes the run,
not the results in `needs`. A gate is skipped only when its own condition is
false (a skipped required check counts as passing, which is the danger). A
gate still waiting when its run is cancelled reports cancelled, which blocks
the merge. Don't switch such a gate to `always()` for the timeout reason.
Origin: a CI infrastructure repo, 2026-09, both cases measured with a
throwaway workflow.
