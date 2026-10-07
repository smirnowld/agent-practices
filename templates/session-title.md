# Session title

<!-- The title every session carries, proposed or started by me (P2a). It
lets me see from the session list what a session does and whether it waits
on me. The project is not in the title: the session list groups sessions by
folder. -->

```
AUTONOMY Type·Size — REF what it does
```

Example: `🔵 Build·M — WP73b cart contract before the location is known`.

## Autonomy

How much of me the session needs. The estimate comes from the brief or from
sizing the task (P2a).

| Marker | Name | What it needs from me |
|---|---|---|
| 🟢 | Auto | Nothing: the brief settles everything and it merges itself (P6). I read the closeout. |
| 🔵 | Sign-off | One touch at the end: a merge P6a leaves to me, an acceptance card, or "ready for you". |
| 🟡 | Ask | One batch of questions that change the result (P6), then it runs alone. |
| 🔴 | With me | Throughout: decisions I own (P11), rulings, steering research, or steps I do by hand. |
| ⏱ | Routine | Nothing: scheduled and read-only, it only proposes sessions. |

The marker only moves up, never down: a session that starts waiting on me
beyond its estimate retitles itself to the marker that now applies, and the
closeout names the miss.

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

## Rest

`REF` is the plan or register reference when there is one (`WP73b`, `Q98`,
`ADR-0058`, `#706`). The description says what the session does, in my
words, not the first message that started it.

## Placement

A session started in a folder above several projects, to route a request or
explore a wider problem, moves into the project once the work clearly belongs
to one. Work that spans projects stays where it started.
