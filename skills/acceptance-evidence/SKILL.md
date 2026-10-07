---
name: acceptance-evidence
description: Choose and produce the evidence I need to accept user-facing work (P6), cheapest level that lets me judge it, delivered as links that open on my phone (P18). Use before presenting an acceptance card.
---

# Acceptance evidence

Goal: I can judge the change in under a minute, on my phone, without the
session. Pick the **lowest level that answers "is this what I wanted?"**, then
fill `templates/acceptance-card.md`.

## Decide whether acceptance is needed

Needed when the change is visible to a user: UI, copy, flows, notifications,
generated documents, behaviour I described. Not needed for refactors, internal
tooling, CI, dependency bumps; say "n/a" on the PR instead.

## Pick the level

| Level | Use when | Produce |
|---|---|---|
| 1. Screenshots | Static layout, copy, a few states | Before/after per changed screen and state (empty, error, long text, dark mode if supported), phone size first |
| 2. PR preview | Flow across screens, interaction, real data matters | The PR's own preview URL plus the click path, or a local run on demo data with screenshots of each step; screenshots of key steps as backup |
| 3. Phone build | Native feel, gestures, device APIs, performance, notifications | Install link (TestFlight or equivalent) plus what to try |
| Recording | Only motion that stills cannot show: animation, transitions, timing | Short clip for me to watch, on the private evidence page; never a substitute for 1–3 |

Go up a level when the lower one would leave me guessing; go down when a
higher one costs a build or deploy for a copy change. When unsure between two,
pick the lower and say what it does not show.

Acceptance comes before merge, so the evidence must show unmerged work. A
shared deploy of the default branch (staging) shows only merged work: it is
not evidence unless the project deploys a preview per PR. Without one, the
card's "Not covered" says I cannot try the flow myself, or I get a phone build.

## Produce it

- Capture from the real build or preview, not a mockup. Name each image by
  screen and state.
- Deliver so it opens anywhere (P18): put the images on a private published
  page linked from the PR (`practices/record-keeping.md#visual-evidence`);
  preview and build links must be reachable without the local machine.
- Build the page from `templates/evidence-page.html`, so images open in its
  in-page viewer with a way back, never as links to the image files.
- Check every link resolves before sending.

## Report

Fill the acceptance card: what changed in user terms, the "try it" link,
evidence list, assumptions with how to undo, what the evidence does not
cover, and known gaps from this PR's deferred findings so far. Then wait
for accept / change / reject; do not merge user-facing work before it.
