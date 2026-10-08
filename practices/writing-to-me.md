# Writing to me

Detail for P21. Applies to every message meant for me: updates, questions,
acceptance cards, closeouts, PR descriptions, ADRs. Templates set the
structure (fields, order, links); this sets the wording inside it. Where a
template field is itself a list of identifiers (files, commits, models,
checks), the template wins.

## Who reads it

I run the business and direct the agents. I read on my phone, between other
work, and mostly skim. Most of my value is in checking what changed for me,
my users and my customers, and in the decisions only I can make. Write like
a colleague giving a quick spoken update, not like a log.

## Rules

- **Result first**, in one or two plain sentences, unless a template sets
  the order. Add detail only when it helps me decide or act.
- **Full sentences**, with verbs and linking words ("because", "so", "which
  means"). Don't stack nouns or pack clauses with slashes, semicolons and
  parentheses.
- **Effects, not mechanisms.** Say what someone will notice, not how the
  code achieves it.
- **No internal labels in the text**: policy numbers, commit hashes, file
  paths, test and check names, flags, schema versions. Name one only when I
  have to act on it: type or click it, or it identifies what I am approving
  (the PR in a merge question). Links still follow P18. An unavoidable
  technical term gets a few words on what it means for me.
- **Asks stand out**: what to do, in what order, the exact command or link,
  and what happens when I do it ("merging deploys").
- **Real risks only**, one line each. Routine gaps that a check or review
  already covers stay out.
- **No padding**: no restating my request, no narrating the process, no
  sections that only say "none", unless a template asks for it (the PR
  record, acceptance-card assumptions).
- **Short**: under about 150 words for most messages. If more is needed,
  the summary comes where I will see it first.

## Steps for me

Detail for P9a. A step I have to do by hand is the costliest line in any
message, so first try not to need it, then make it impossible to miss.

- **Try first.** Run what you can: install, configure, create the label or
  the repository setting through `gh`, write the config file, start the
  service. Check the result. A step becomes mine only for a real reason:
  consent (P9), a secret (P10), root, a sign-in, an approval prompt, or a
  setting with no command or API. Say the reason in a few words.
- **Shrink what is left.** Prepare everything around it: write the script
  so I run one command, fill the file so I only paste a value, give the
  direct link to the exact settings page rather than "go to settings".
- **Say it in chat**, numbered, in the order to do it. A README, runbook or
  PR body may also keep a step that must be repeated later, but a step that
  is only there, in a code comment or in thinking is a step I never saw.
  Steps a worker reports go into the coordinator's message the same way.
- **Each step** says where (which machine, directory or page), the exact
  command in its own code block, one command per block, ready to paste with
  no placeholders I must invent (name the value and where it comes from
  when one is unavoidable), what I should see when it worked, and what
  happens next: "then tell me" or "the session picks it up by itself".
- **After I do it**, verify it yourself and continue; don't ask me to check.

Before: "You'll need to add the deploy key and enable the workflow."

After: "1. On your laptop, add the deploy key (it is a secret I must not
read), then reply 'done':

```bash
gh secret set DEPLOY_KEY --repo OWNER/REPO < ~/.ssh/deploy_key
```

You should see 'Set Actions secret DEPLOY_KEY'. I enable the workflow and
start the first run myself."

## Before and after

Before: "Upstream timeouts now fall back to cached values; partial
aggregates and unreconciled amounts render as unavailable."

After: "If the data source doesn't answer, the page keeps the last number it
had. Totals it can't fully count show as 'unavailable' rather than a wrong
number."

## Origin

All projects: closeouts from two agents. The densest ones (noun stacks,
policy numbers, commit hashes in the text) were the hardest to act on, and
asks in them were missed or wrong. The closeout
template took the structural fixes; this practice holds the wording rules so
every message gets them, whichever agent writes it.
