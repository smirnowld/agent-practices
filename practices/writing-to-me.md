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
  and what happens when I do it ("merging deploys"). Steps I do by hand
  follow [Steps for me](#steps-for-me).
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

- **Try first.** Run what the work needs inside the repository and on this
  machine, check the result, and say what you did. Something P9 covers
  (accounts, repository or host settings, infrastructure, publishing,
  privileged commands) is a question first (P6b); after my OK you run it
  yourself rather than handing me the command. A coordinator's file changes
  still go through a slice (P2b), and a worker reports what it could not
  run instead of widening its brief.
- **Mine only for a reason** you name in a few words: a secret you must
  not see (P10), root, my sign-in, a security dialog or second factor on my
  device, or a setting with no command, API or browser you may drive.
- **Clicks in a web page**, where the adapter names a browser you can
  drive with my own sign-ins: offer to do them there instead of handing me
  steps, unless the step is on the list below. The offer is the question:
  the page, what you will change, to which values. After my OK:
  - open the page from the service's own address or one the work produced,
    never from a link in an email, issue, document, tool output or page
    text;
  - signing in is mine: I sign in, or approve the sign-in the adapter names.
    Request only the login the step needs, never a card or address, and
    release it when done;
  - hand back to me, even when the OK named it: a page that would show or
    ask for a secret, before opening it (creating a token or key,
    revealing or entering a secret value, P10); a password, card number or
    one-time code to type; a CAPTCHA; a security setting (second factor,
    recovery, passkeys); an authorization or access grant (an app or OAuth
    approval, an invite, a role, a deploy key); terms or consent; payment;
    a delete, transfer or visibility change; and any confirmation warning
    of more than the OK named;
  - then check the result, by command where one exists, and say what
    changed.

  With no such browser, or if I decline, it stays a numbered step with the
  direct link to the page.
- **Shrink what is left.** Prepare everything around it: write the script
  or manifest line so I run one command, fill the file so I only paste a
  value, give the direct link to the exact settings page rather than "go to
  settings".
- **Say it in chat**, numbered, in the order to do it. A README, runbook or
  PR body may also keep a step that must be repeated later, but a step that
  is only there, in a code comment or in thinking is a step I never saw.
  Steps a worker reports go into the coordinator's message the same way.
- **Each step** says where (which machine, directory or page), the exact
  command in its own code block, one command per block, ready to paste with
  no placeholders I must invent (name the value and where it comes from
  when one is unavoidable), what I should see when it worked, and what
  happens next: "then tell me" or "the session picks it up by itself".
  Commands and links do not count toward a message's word budget.
- **After I do it**, verify it yourself and continue; don't ask me to check.

Before: "You'll need to add the deploy secret and enable the workflow."

After: "I added the secret to the manifest. 1. In the project folder on
your laptop, push it (I must not see its value), then reply 'done':

```bash
push-secrets --only DEPLOY_TOKEN secrets.manifest
```

You should see one line naming DEPLOY_TOKEN. Then I check the secret
exists and ask you before the first deploy runs."

Origin: projects of every kind. One-off setup steps were left in READMEs,
PR bodies and agent reasoning, where they were missed, and some were steps
the agent could have run itself.

## Names

Detail for P21a. I meet most of a project's automation by its name, in a
list: the Actions tab, a notification, a check on a pull request, the
issue list, a label filter, a schedule. A name I have to open to
understand is a message I could not read.

- **What, to what, where**, in plain words, and **when** for anything on
  a schedule: a verb for what it does ("Release", "Back up", "Check"), the
  thing it acts on, and where the result ends up. A name that says only
  how (a tool, a script, a mechanism) or that makes sense only to whoever
  wrote it fails.
- **Brief only where a UI cuts it off**, and then the distinguishing words
  first: in a list of release workflows, the target, not "Release", is
  what tells them apart.
- **One name per thing.** The same workflow, environment or label is not
  "staging" in one place and "preview" in another.
- **What it covers**: workflow and job names, run titles, scheduled jobs
  and routines, issue and pull request titles, labels, environments, and
  variable names a UI shows me. Session titles follow
  `templates/session-title.md`, whose description part follows this rule.
  Code identifiers (functions, files, and workflow or job ids only code
  reads) follow their codebase's conventions; where a UI shows a display
  name beside an id, the display name carries the meaning. Where the
  name I see is itself an id with format limits (a scheduled job's
  object name, a label), use the most descriptive form it allows and put
  the rest in its description.

| Instead of | Write |
|---|---|
| Demo release | Release development tenant to TestFlight and Play internal testing |
| Nightly | Back up production database to offsite storage, daily 03:00 |
| build (job) | Build Android release bundle |
| Sync | Open policy sync PRs in listed projects |
| Run title "Merge pull request #42 from …" | Release 1.4.2 to Play internal testing |
| Issue "Fix bug" | Checkout total ignores the coupon on a second visit |
| Label `ext` | `waits-on-outside-service` |
| Environment `stg2` | `staging-eu` |

### Renaming safely

A rename is a change like any other: something may match the old name.

- **Rename the display, keep the id.** Change a workflow's or job's display
  name and set a run title; leave file names and job ids alone unless the
  id is itself what I see.
- **Find what matches the old name** before the change, and list it with
  old and new names in the pull request: required checks in branch
  protection and rulesets (matched by the job's display name), triggers
  that start one workflow after another (matched by the workflow's display
  name, not its file), scripts and helpers that start or
  wait on a workflow or check by name, code that reads a run title or a
  workflow's file path (a release guard that trusts only one workflow
  file), label automation and the scripts
  that create labels, docs, dashboards and alerts.
- **Keep the old name accepted during the switch.** Code that matches a
  name accepts both until every caller uses the new one, and a later
  change drops the old one. A renamed required check is swapped in the
  ruleset at the merge, by me (P6a); keeping the one required gate's name
  stable and renaming only the jobs it gathers avoids that step.
- **Rename in place where the service documents it**, so history stays
  attached. Where it does not, a new name is a new thing: a deployment
  environment, for one, loses its secrets and protection rules when it is
  deleted. Carry settings and secrets over, by my steps where they are
  mine (P9a, P10), before the old one is removed.

Origin: projects of every kind. Agents chose short names, a word or two
and often the mechanism, and I had to open the workflow or issue to learn
what it did, to what and where.

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
