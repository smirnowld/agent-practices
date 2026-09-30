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

Since the last run (or 3 days), check whether any issue changed or the
default branch had merges. Neither, and no issue is due for its 30-day
review: report "no changes" and stop.

Otherwise list open issues:

```sh
gh issue list --state open --limit 500 --json number,title,labels,createdAt,updatedAt,url,closedByPullRequestsReferences
```

If 500 come back, say the list was truncated and review the highest
priorities first. Select issues that are new or changed since the last run,
issues a merge since the last run may address (it names the issue, or touches
the files or area the issue names; a cheap match on titles, bodies and changed
paths), and any issue not reviewed in the last 30 days. Review in priority order
(labels in baseline R6): unprioritised first, then `p1`, `p2`, `p3`.

## 2. Check relevance (standard tier)

For each selected issue, from evidence only:

- **Addressed:** a merged PR or commit since the issue was opened fixes it
  (linked PRs; PRs and commits naming the issue number, files or symbols;
  the code it points at on the default branch).
- **Obsolete:** the code, feature or decision it concerns is gone or was
  overturned (ADRs and `docs/questions.md`, where present).
- **Duplicate:** another open issue says the same; keep the older or fuller
  one.
- **Roll up:** it fits an item already planned: a row in `docs/plan.md` or
  the roadmap where present, or an open issue or PR that item links. Name the
  item.
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
| Open `p1` issue not in planned work | Proposed session that asks me first whether to plan or start it |
| A verdict needs my decision (scope, requirement, overturning a decision) | Proposed session that asks me first and records the question (P11); do not propose the change |

Ask about an issue once. The log records what was asked; later runs only
count it until the issue changes or I answer.

## 5. Report

One line per issue acted on: `#N — verdict — action — evidence`. Then counts
by priority and the oldest `p1`. Write the proposed session with the
`brief` skill (steps 4 to 6). Store the report where the routine keeps its log, with the run date,
the issues reviewed and the questions asked, so the next run can select.
Report the run's token use.
