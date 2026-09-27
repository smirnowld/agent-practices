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

## 3. Links (P18)

- PRs, issues, commits and CI runs: full `https://github.com/...` URLs.
- Files and lines: `https://github.com/OWNER/REPO/blob/SHA/PATH#L12`, with
  a 40-character commit SHA, never a branch name.
- A path in backticks is only a label next to its link, on the same line.
  Paths on their own may be turned into local links by the chat client,
  which break once the session ends or the working directory changes.
- Not pushed yet: push first, or attach the file.

## 4. Check before sending

Save the draft to a scratch file and run the link check from the
agent-practices root:

```
python3 scripts/check-links.py DRAFT_FILE
```

It fails on non-URL link targets, bare paths, branch-pinned file links and
GitHub URLs that do not resolve. Fix every failure, then send. If the check
cannot run (no `gh`, no network), say so under **Not verified**.
