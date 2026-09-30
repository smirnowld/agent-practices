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
  fresh context. It, and any leftover work the closeout lists, is proposed
  with the `brief` skill once I say yes in step 5.
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

## 5. Signal and ask

Send the closeout, then the notification with the outcome (P6b). Then ask
whichever of these apply, together in one structured question prompt:

- **Acceptance or decision** the closeout waits on (P6).
- **Merge**: a PR that is verified, reviewed and green but left to me to
  merge (P6a or the project's procedure). The question names the PR link,
  why it is mine and its head commit; merging is proposed first. A yes is my
  explicit OK (P1) for that commit only, and counts only if I also accepted
  and left no decision open. Merge by the project's procedure or the `merge`
  skill, whose other checks still apply. Any new commit needs the question
  again.
- **Follow-ups**: when **Deferred**, **Next** or **Continuation** lists work
  for a new session. Ask whether to brief it: all (proposed first), let me
  pick (a second prompt lists them), or none. On a yes, run `brief` with
  those candidates.

After acting on the answers, update the PR's closeout to match and say in
one line in chat what happened (merge SHA, sessions proposed); do not repost
the closeout. The adapter's `session.md` names the tools.

## Origin

A product repository, 2026-09: the done rule, blocked outcome, cleanup
checklist, blocker owner and continuation routing came from its closeout.
