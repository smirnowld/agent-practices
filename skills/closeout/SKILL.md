---
name: closeout
description: Write the end-of-session closeout (P15) from templates/closeout.md - a short plain-language summary in chat, the full record with agents and models in the PR - with every link opening on my phone after the session ends (P18). Use right after a PR of this session merges (directly or by auto-merge) or is abandoned, before the final message of any session that changed something, and for the closeout part of a PR description.
---

# Closeout

Goal: in under a minute I know what is different, whether anything needs me
and whether anything is risky. The PR keeps the full record, so anyone can
check the work from their phone later. The closeout goes in chat and in the
PR (P17), never in the repository.

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
  done. Records name each proposed ADR this PR added or built and my ruling
  on it, or why it stays proposed (P11). Cleanup includes your own
  background waits: none may still be running; stop any left (the adapter
  names the tool) and say so.
- Steps addressed to me anywhere: the PR body, changed READMEs and docs,
  workers' reports, your own notes. Run each one you can (P9a; file changes
  through a slice, P2b); the rest go under **Needs you**.
- What was fixed on the go and which issues the PR closed (P6). Work left
  over that would have passed the fix-on-the-go test is a miss: say so under
  **Deferred** and why it was not done.

## 2. Fill the template

Write the summary first, from what I will see, not from what you did. Keep
the template's order: the asks and the TL;DR come last, where a chat opens.

- **Watch out**: only what could hurt users, data, money or time if I
  missed it: something untested that matters, a surprise, a new cost. Not
  routine gaps such as a skipped local check that CI covered.
- **Next**: one line, only when there is a real next task.
- **Needs you**: every step that waits on me, numbered in order, each with
  where, the exact command in its own code block, link or choice, and what I
  should see (`practices/writing-to-me.md#steps-for-me`). Name an irreversible effect next to its step
  ("merging deploys"). Check the order against what I have already done. An
  acceptance waits on its own card (`templates/acceptance-card.md`); point
  to it rather than repeating it.
- **Status**, with its colour mark so I can read it at a glance:
  - 🟢 **done**: merged and cleaned up; a deploy that follows is not
    waited on (`merge` skill);
  - 🔵 **ready for you**: finished, reviewed and green, waiting only on my
    acceptance or merge;
  - 🟡 **partly done**: assigned work is left undone;
  - 🔴 **blocked**: cannot go on without something outside the session;
  - ⚪ **abandoned**: stopped, with the reason.
- **TL;DR**: what is different now for me, my users or my customers, in one
  or two sentences. A change with nothing visible says what it protects or
  makes possible.

Plain words throughout (P21, `practices/writing-to-me.md`). About 120
words, links and commands aside. If it runs longer, cut process, not the ask or the risk.

Then fill the Record field by field for the PR. Keep each field to what a
reader needs; leave out process detail. Every Record field appears in the PR,
"none" where it applies. In chat, send the summary only and link the PR under
**Full record**; with no PR, put the Record fields that apply between
the heading and the summary, so the chat still ends on Status and TL;DR.

For **Continuation**:

- **Continue this session** when the next step finishes the current task
  with the same ownership and context and needs no new decision or
  authority. A ready branch or open PR is not a reason to stop (P5).
- **Start a new session** after merge and cleanup, when the next task is a
  distinct objective, needs another worktree or owner, or would benefit from
  fresh context. It, and leftover work that failed the fix-on-the-go test,
  is proposed with the `brief` skill once I say "now" in step 5.
- **Wait for me** when the next step is a decision, acceptance, merge,
  production action or other step that is mine. Never for work with nothing
  left to wait on.
- **None** when the task is done (merged and cleaned up, or abandoned) and
  there is no next step for me or a new session.

## 3. Links (P18)

Follow P18. The rule this skill adds: a path in backticks or plain text is
only a label next to its link, on the same line. On its own, a chat client
may turn it into a local link that breaks once the session ends or the
working directory changes.

## 4. Check before sending

Save the draft to a scratch file and run the link check that ships next to
this skill, with an absolute path to the draft: `--closeout` for the chat
summary, `--closeout-pr` for the PR description.

```
python3 SKILL_DIR/../../scripts/check-links.py --closeout /ABSOLUTE/PATH/DRAFT.md
```

`SKILL_DIR` is the folder holding this file; the path works through a
symlinked install. Fix each failure. A flagged token that is not a file
reference (a command, a branch name) can stay. Without `gh` or network, rerun
with `--offline` for the local checks and name the unchecked links under
**Not verified** in the PR record. Check the exact text you will send and
send it unchanged; drop the flag only for a PR body that holds no closeout.

## 5. Signal and ask

Send the closeout with its questions in the same message, then the
notification with the status (P6b). Ask whichever of these apply, numbered
in one batch (`templates/question.md`), so one reply answers all:

- **Acceptance or decision** the closeout waits on (P6).
- **ADR acceptance**: "Accept ADR-NNNN (title)?" for each ADR the
  [trigger](../../practices/record-keeping.md#triggers) names and not asked
  earlier, linked at the PR head, with its three options.
- **Merge**: a PR that is verified, reviewed and green but left to me to
  merge (P6a or the project's procedure). The question names the PR link
  and which P6a item makes it mine, in plain words; merging is proposed
  first. A yes is my explicit OK (P1), and counts only if I also accepted
  and left no decision open. Merge by the project's procedure or the `merge`
  skill, whose other checks still apply. A later commit needs the question
  again if its own diff is on the P6a list or it is not confirmed under P4b.
- **Follow-ups**, only for real ones: the next plan step this session
  unblocked, work deferred because it failed the fix-on-the-go test
  (bigger or riskier changes above all), and anything under **Not
  verified** that a session could still verify. Merge duplicates first. For each, ask now or
  later: now briefs it (or, for a deferred change in an unmerged PR, does
  it in this PR); later leaves the plan row or issue. On "now", run `brief`
  with those candidates. Leftovers that passed the test are a miss to report,
  not a question.

After acting on the answers, rewrite the closeout in the PR description
(`gh pr edit --body-file`; a comment does not replace it) so Status, Needs
you, Proof (with any post-merge run), Blocked on, Cleanup and Continuation
match the merged state, and check it again as in step 4. Then say in one
line in chat what happened (merged PR link, sessions proposed); do not repost the
closeout. If no closeout summary went to chat earlier, send it now. The adapter's `session.md` names
the tools.

## Origin

A product repository: the done rule, blocked outcome, cleanup
checklist, blocker owner and continuation routing came from its closeout.
All projects: many answered questions were "brief this small fix?", so
small fixes now land in the PR and only real follow-ups are asked about.
All projects: closeouts ran long and were mostly process fields; asks sat
deep in the list, some were missed or wrong, and finished work waiting on my merge read as
"partly done". The chat closeout became a short summary ending with a
colour-marked status and a TL;DR, with the record moved to the PR.
