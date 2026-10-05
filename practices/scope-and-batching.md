# Scope and batching

Detail for P6 "Fix on the go" and "Pull in related issues", and P4b. The aim:
one briefed session ends in one PR that also holds the small fixes found on
the way, with one final review and one final CI run, and I decide only what
is mine.

## The fix-on-the-go test

Fix without asking, and log it under **Also fixed**, when all hold:

- **Related:** it serves the brief's goal, or sits in the same files or
  modules as the change.
- **Reversible:** a revert undoes it; nothing outside the repository changes.
- **Small:** S-sized (`practices/model-sizing.md`, "Size in responses"),
  added to the session's work.
- **Same risk:** it keeps the PR in its risk category (P4). A fix that would
  need the critical reviewer in a PR that does not is out.
- **Free to touch:** no file or resource on the brief's No-go list.

Usually in: docs and comments that the change made stale, lint, type and
static-analysis findings in or next to the changed files, a one-line fix in
a neighbouring file the work needs, a missing test for touched code,
non-blocking review findings of that size, open issues on the same files.

Usually out: schema and data migrations, public API or contract changes,
user-visible behaviour no one asked for (P11), ADR status changes, secrets,
infrastructure and CI configuration that guards a check, another session's
files. These become a deferred item with the reason, and closeout asks
whether to do them now or later.

Fail the test only on the item, not the session: the brief still stands.

## Session order

1. Build what the brief asks.
2. Fix on the go, and fix the related issues that pass the test.
3. Acceptance, and my tweaks.
4. Final independent review of the whole PR (P4).
5. One push of the final head; CI runs once on it.
6. Merge.

Push earlier only when CI is the cheaper way to get a proof. A tweak after
step 4 follows P4b.

## Delta review (P4b)

The review that counts is the one of the final head. After it:

- A commit I approved after seeing its diff is reviewed by me (P4 allows a
  review "by me"); no reviewer rerun.
- Any other commit gets the resumed reviewer in delta-confirmation mode
  (`roles/reviewer.md`): only the new commits, not the whole PR again.
- A change that needs the critical reviewer keeps P4a and P6a: my OK names
  the head commit.

Safe because the delta is small and seen: the reviewer already covered the
rest, and a delta that goes wider or raises the risk category goes back to a
full review.

## Finding related issues

At session start (the brief may already list them) and once before the final
review:

```sh
gh issue list --state open --limit 200 --search "PATH_OR_SYMBOL in:title,body"
```

Search for the changed paths, module names and key symbols, and the goal's
words; `deferred-review` issues name the file they came from. Check each hit
with `issue-review` step 2: already fixed means close it with the evidence;
passing the test means fix it here with `Fixes #N` in the PR; anything else
is listed in the report, not fixed.

## Origin

Several product, app and CI repos, 2026-10. Over three days about a fifth
of answered questions were the agent asking leave for small fixes or
closures it could rule on, sessions stopped over one-line fixes outside
their owned files, one feature took seven PRs and as many reviews, a third
of review runs followed a tweak I had already seen, and nearly all open
issues were deferred review findings.
