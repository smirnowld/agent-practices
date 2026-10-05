# Writing to me

Detail for P21. Applies to every message meant for me: updates, questions,
acceptance cards, closeouts, PR descriptions. Templates set the structure
(fields, order, links); this sets the wording inside it.

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
  have to type or click it; links still follow P18. An unavoidable
  technical term gets a few words on what it means for me.
- **Asks stand out**: what to do, in what order, the exact command or link,
  and what happens when I do it ("merging deploys").
- **Real risks only**, one line each. Routine gaps that a check or review
  already covers stay out.
- **No padding**: no restating my request, no narrating the process, no
  sections that only say "none" (the PR record is the exception; see
  `templates/closeout.md`).
- **Short**: under about 150 words for most messages. If more is needed,
  the summary comes where I will see it first.

## Before and after

Before: "Failed reads retain their last good values; incomplete organisation
totals and unverified compute/billing/Apple values say unavailable."

After: "If GitHub doesn't answer, the dashboard keeps the last number it had.
Totals it can't fully count, and billing it can't check yet, show as
'unavailable' rather than a wrong number."

## Origin

All projects, 2026-10: two days of closeouts from two agents. The densest
ones (noun stacks, policy numbers, commit hashes in the text) were the
hardest to act on, and two asks were missed or out of order. The closeout
template took the structural fixes; this practice holds the wording rules so
every message gets them, whichever agent writes it.
