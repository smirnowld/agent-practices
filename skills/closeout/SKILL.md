---
name: closeout
description: Write the end-of-session closeout (P15) from templates/closeout.md, with every link opening on my phone after the session ends (P18) and the agents and models named. Use before the final message of any session that changed something, and for the closeout part of a PR description.
---

# Closeout

Goal: a reader with no context knows what happened, can check it from their
phone, and knows what comes next. The closeout goes in chat and in the PR
(P17), never in the repository.

## 1. Gather

- The PRs opened, their state, and the merge commit SHA of each merged one.
  State what is finished from the merged default branch, never from a
  branch or a worker's report, and update the living plan (P17), if any, to match; in a product
  repo, `docs/plan.md` and the phase plan (`practices/planning.md`,
  "When a package leaves").
- The files a reader needs to see, pinned to that SHA (or the PR head SHA if
  not merged).
- Proof: the checks on the final commit, with the CI run URL.
- The agents and models used: role, model, effort, and what each did. Name
  any fallback when a role's agent was unavailable.
- Anything not verified, deferred review findings, records updated, cleanup
  done.

## 2. Fill the template

Fill `templates/closeout.md` field by field. Keep each field to what a reader
needs; leave out process detail.

For **Continuation**:

- **Continue this session** when the next step finishes the current task
  with the same ownership and context and needs no new decision or
  authority. A ready branch or open PR is not a reason to stop (P5).
- **Start a new session** after merge and cleanup, when the next task is a
  distinct objective, needs another worktree or owner, or would benefit from
  fresh context.
- **Wait for me** when the next step is a decision, production action or
  other step that is mine.

## 3. Links (P18)

Follow P18. The rule this skill adds: a path in backticks or plain text is
only a label next to its link, on the same line. On its own, a chat client
may turn it into a local link that breaks once the session ends or the
working directory changes.

## 4. Check before sending

Save the draft to a scratch file and run the link check that ships next to
this skill, with an absolute path to the draft:

```
python3 SKILL_DIR/../../scripts/check-links.py /ABSOLUTE/PATH/DRAFT.md
```

`SKILL_DIR` is the folder holding this file; the path works through a
symlinked install. Fix each failure. A flagged token that is not a file
reference (a command, a branch name) can stay. Without `gh` or network, rerun
with `--offline` for the local checks and name the unchecked links under
**Not verified**.

## Origin

A product repository, 2026-09: the done rule, blocked outcome, cleanup
checklist, blocker owner and continuation routing came from its closeout.
