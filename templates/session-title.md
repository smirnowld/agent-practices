# Session title

<!-- The title every session carries, proposed or started by me (P2a). It
lets me see from the session list what a session does and whether it waits
on me. The project is not in the title: where sessions are listed, they are
grouped by project. -->

```
AUTONOMY Type·Size — REF what it does
```

Example: `🔵 Build·M — WP12 checkout contract for guest orders`.

## Autonomy

How much of me the session needs, in rising order 🟢 🔵 🟡 🔴; the highest
that applies wins. The estimate comes from the brief or from sizing the task
(P2a).

| Marker | Name | What it needs from me |
|---|---|---|
| 🟢 | Auto | Nothing: the brief settles everything and it merges itself (P6). I read the closeout. |
| 🔵 | Sign-off | One touch at the end: a merge P6a leaves to me, an acceptance card, or "ready for you". |
| 🟡 | Ask | One batch of questions that change the result (P6), then it runs alone. |
| 🔴 | With me | Throughout: decisions I own (P11), rulings, steering research, or steps I do by hand. |
| ⏱ | Routine | Nothing: scheduled and read-only, it only proposes sessions. |

⏱ goes only with the Routine type and no size: `⏱ Routine — daily triage`.

## Type

| Type | Use for |
|---|---|
| Build | New capability |
| Fix | Something observed broken |
| Follow | Leftovers of a merged session: deferred-review findings, follow-up issues |
| Chore | Maintenance: dependency bumps, renames, cleanup |
| Land | Finishing, merging or closing pull requests that already exist |
| Ops | Release, deploy and infrastructure, effects a revert does not undo |
| Research | Answering a question or investigating; findings, not code |
| Decide | ADRs, rulings, briefs, accepting a phase |
| Routine | Scheduled checks |

## Size

XS, S or M, the response budget in `practices/model-sizing.md` ("Size in
responses"). L is never one session, so never a title. Routines carry no
size.

## Sessions started by a skill

A session whose first message runs a skill titles itself before the skill's
first step, from what the skill will do, not from the command. Defaults
when nothing else is known:

| Skill | Title |
|---|---|
| `brief next` | `🟡 Decide·S — choose next tasks` |
| `merge` | `🟢 Land·XS — #N merge` |
| `cost-review` | `🟡 Research·M — agent spend review` |
| `project-setup` | `🟡 Chore·M — baseline setup` (audit: `🟢 Research·S — baseline audit`) |
| `docs-gardening` | `🟢 Chore·S — consolidate DOCS` |
| `project-visuals` | `🟢 Chore·S — redraw VISUAL` |
| a routine skill run by hand | `🟢 Research·XS — NAME by hand` |

A skill run inside a session already titled, such as `closeout` or
`acceptance-evidence`, keeps the title. A scheduled routine is titled
where it is configured (`⏱ Routine — NAME`).

## Rest

`REF` is the plan or register reference when there is one (`WP12`, `Q3`,
`ADR-0001`, `#42`). The description says what the session does, in my
words, not the first message that started it.
