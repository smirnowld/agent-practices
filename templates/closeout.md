# Closeout: <title>

<!-- End of session (P15), written with the closeout skill. Lives in the PR
and chat, not the repo (P17).

Chat gets the part above "Record" only: about 120 words, links and
commands aside, read in under a minute on a phone. Plain words about what changes for me, my
users and my customers; no policy numbers, commit hashes, file paths or
check names unless I have to act on one. Leave out a field marked "only
when" if it does not apply; never fill it with "none". The summary ends with
Status and TL;DR, the lines I see first when a chat opens at its end. The PR
description holds the whole closeout. With no PR, the Record fields that
apply go in chat between the heading and the summary. -->

**Watch out:** <only when there is a real risk or gap I should know about:
something untested that could hurt users, data or money, an irreversible
effect, a surprise. One line each>

**Next:** <only when there is a recommended next task: what and why, in one
line>

**Full record:** <only when there is a PR: its link>

**Needs you:** <only when something waits on me after you did what you
could (P9a): numbered steps in order, as in practices/writing-to-me.md
"Steps for me"; name an effect a step has (for example "merging deploys")>

**Status:** <🟢 done | 🔵 ready for you | 🟡 partly done | 🔴 blocked |
⚪ abandoned> — <one sentence>

**TL;DR:** <one or two sentences: what is different now, as I or a user
would notice it>

## Record

<!-- For the PR description, and for chat only when there is no PR. Every
field appears in the PR; short is fine, "none" where it applies. -->

**What changed:** <bullets; full GitHub URLs to PRs and merged commits (P18)>

**Proof:** <checks green on final commit; acceptance given by me or n/a>

**Not verified:** <item and why; or "nothing">

**Records updated:** <docs, ADRs, question register changed in place; or "none">

**Also fixed:** <fixes made on the go and review findings fixed in the PR
(P6); or "none">

**Issues closed:** <issue links, each fixed by this PR (Fixes #N) or closed
as already fixed with the evidence link; or "none">

**Deferred:** <unfinished assigned work, review findings as issue links, or
advisory links for security findings (P4), and other follow-ups with where
they are tracked; only work that failed the fix-on-the-go test, each with
the reason, for a review finding its `Not fixed: PART — why` line
(practices/scope-and-batching.md), never for an advisory; or "none">

**Blocked on:** <each blocker or decision and who resolves it, decisions in
the question register (P11), other blockers where tracked; or "none">

**Merged without me:** <each critical change (P6a) merged without my OK: PR
link and one line on why no P6a item applied; or "none">

**Agents and models:** <role — model at effort — what it did>

**Cleanup:** <state of each: review, PR, CI, merge, local default branch
updated, remote branch, local branch, worktree, other resources released>

**Continuation:** <continue this session | start a new session |
wait for me | none> — <why>. <For a new session: the task in one line, briefed once I say
yes (closeout skill step 5)>
