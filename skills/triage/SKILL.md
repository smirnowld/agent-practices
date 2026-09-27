---
name: triage
description: Daily routine (baseline T2). Reads a deployed project's observability manifest, checks health, errors, alerts, uptime and logs since the last run, and reports what is new, recurring or worse. Read-only; proposes a session only for something that needs action.
---

# Triage

Goal: each morning, know whether each deployed project is healthy and what
changed, without opening dashboards. Read-only: it never restarts, redeploys,
silences alerts or edits anything.

Runs from a scheduled routine, one run per project with
observability set up. The routine proposes a session only for projects that
need action.

## 1. Load the manifest

Read the block between `<!-- observability:begin -->` and
`<!-- observability:end -->` in `docs/operations.md` on the default branch
(`practices/observability.md`). Check `contract` is a version this skill
supports (1).

Missing, unparsable or unsupported: report it as the finding and stop. Do
not guess signals.

## 2. Collect (fast tier)

For each environment, since the last run (or 24 hours):

- **Health:** call it; record status and version. Compare version with the
  latest release or default-branch deploy.
- **Uptime:** incidents and downtime minutes.
- **Alerts:** fired and resolved alerts, by name.
- **Errors:** new issues, and issues whose rate rose, with first-seen
  release.
- **Logs:** the manifest's query, filtered to error level and above; group by
  message pattern.

Credentials come only from where `access` says they are stored (P10). A
signal you cannot reach is a finding ("errors: no access"), not a skip.

## 3. Compare

Against `normal` and the previous run's report:

- **New:** not seen before.
- **Recurring:** seen before, same level.
- **Worse:** rate or duration up.
- **Resolved:** gone since the last run.

Routine noise described in `normal.notes` is not reported.

## 4. Decide

| Result | Output |
|---|---|
| Healthy, nothing new or worse | One line: "healthy", versions, range checked |
| New or worse error, fired alert, failed health | Proposed session: investigation session (standard tier; strong for data loss or security signals), with evidence |
| Alert fired without a runbook, manifest names a dead signal, manifest out of date | Proposed session: operations fix |
| Anything that may be an incident in progress (down now, data at risk) | Proposed session marked urgent, and notify me through the routine's notification |

## 5. Report

Per project: status line, then findings as
`signal — what — since — link (P18)`. Store the report where the routine keeps
its log, so the next run can compare. Never include secret values, personal
data from logs, or tokens; quote log lines only after removing them.
