---
name: issue-review
description: Routine every three days (baseline T4). Reviews a project's open GitHub issues by priority, checks whether each is still relevant, already addressed or a duplicate, and whether it belongs in planned work. Read-only; proposes one session with the actions to apply.
---

# Issue review

Goal: open issues stay true and prioritised, and none is forgotten, at the
lowest cost that can tell. Read-only: it never labels, closes, comments on or
edits anything; the proposed session applies the actions after my OK.

Runs from a scheduled routine, one run per project. The routine proposes a
session only when there is an action to take.

## 1. Select (fast tier)

List open issues with labels, linked PRs and last activity:

```sh
gh issue list --state open --limit 200 --json number,title,labels,updatedAt,createdAt,url
```

Review in priority order (labels in baseline R6): unprioritised first, then
`p1`, `p2`, `p3`. Each run covers issues that are new or changed since the
last run, every unprioritised or `p1` issue, and every issue not reviewed in
the last 30 days. No issues selected: report "no changes" and stop.

## 2. Check relevance (standard tier)

For each selected issue, from evidence only:

- **Addressed:** a merged PR or commit since the issue was opened fixes it
  (search PRs and commits for the issue number, the files and the symbols it
  names; read the code it points at on the default branch).
- **Obsolete:** the code, feature or decision it concerns is gone or was
  overturned (ADRs, `docs/questions.md`).
- **Duplicate:** another open issue says the same; keep the older or fuller
  one.
- **Roll up:** it fits an item already planned: a row in `docs/plan.md` or
  the roadmap, or an open issue or PR that item links. Name the item.
- **Still open:** none of the above.

Cite the evidence for each verdict (PR, commit or file link, P18). Unsure
means "still open", with the question.

## 3. Check priority

Propose a priority for each unprioritised issue, and a change where the
evidence moved (a `p3` that now blocks planned work, a `p1` that no longer
affects anyone). Definitions: baseline R6. `deferred-review` issues are
prioritised like any other.

## 4. Decide

| Result | Output |
|---|---|
| Nothing to change | One line: "issues current", with counts by priority |
| Closures, roll-ups, duplicates or label changes only | Proposed session: apply them after my OK, fast tier |
| Open `p1` issue not in planned work | Proposed session that asks me whether to plan it or start it |
| A verdict needs my decision (scope, requirement, overturning a decision, P11) | Ask me in the report; do not propose the change |

## 5. Report

One line per issue acted on: `#N — verdict — action — evidence`. Then counts
by priority and the oldest `p1`. Use `templates/brief.md` for the proposed
session. Store the report where the routine keeps its log, with the run date
and the issues reviewed, so the next run can select. Report the run's token
use.
