# Delegation

Detail for P2 and P2b in [policy/AGENTS.md](../policy/AGENTS.md#p2-roles-sizing-and-delegation).
Tiers and effort per role are in [model-sizing.md](model-sizing.md).

## The coordinator

Every top-level session is the coordinator, whether I started it, it came
from a brief chip or from a routine. Subagents are not coordinators: they do
the slice they were given and report.

The coordinator plans, integrates, verifies and reports. It does not
implement (P2b):

- **Edits.** It never edits source or iterates on builds or tests, even when
  the brief is complete and the change is small. An implementer slice does
  that. The coordinator edits only docs, briefs, plans, PR text, and a
  one-file config change the brief names.
- **Reading.** It reads the brief's core files at section level. A codebase
  search, history, or more than about 3 other files goes to an explorer,
  which returns conclusions with references.
- **Review** is always delegated (P4).
- **Running.** It runs the checks that verify a slice (P3), but fixing what
  they find is the implementer's next slice, not the coordinator's loop.

A brief that lets the coordinator change a config file names it on a
`Coordinator edits:` line ([templates/brief.md](../templates/brief.md)). The
line is set by whoever writes the brief, never by the coordinator for itself.

## Why

Coherence, not cost. A coordinator that implements fills its context with
diffs, build output and retries, compacts more often, and loses the brief's
decisions across compactions. Coordinator sessions across my projects,
measured 2026-10:

| Sessions | n | Median cost | Compactions per session | Median coordinator reads |
|---|---|---|---|---|
| Coordinator implemented itself | 13 | $13.3 | 4.0 | 171 |
| Handed implementation to implementers | 14 | $14.6 | 2.6 | 113 |
| Did neither | 171 | $5.8 | 1.6 | 66 |

Handing off did not save money: cost was about the same. It cut
compactions and the coordinator's own reading. Reading was the larger
spend: the 171 sessions that only read cost $1,363, 57% of the total, which
is why wide reading goes to an explorer too. Delegated implementers reached
a median peak context of 131k, so a slice needs its own budget (below).

## Implementer slices

A slice is one bounded change with named files, acceptance criteria and the
verification to run ([roles/implementer.md](../roles/implementer.md)). The
brief's Delegation section lists each slice with its tier and effort; the
brief's Model line is the coordinator's.

- **Report**: what changed (files, one line each), the proof (command and
  result), and anything left open. No logs or diffs.
- **Questions over logs**: a detail that changes the plan (a settled
  decision looks wrong, the slice needs files outside it) comes back as a
  question, and the implementer stops.
- **Budget**: an implementer that passes about 100 responses stops and
  reports progress; the coordinator splits the rest. The brief's Size still
  counts every implementer response ([model-sizing.md](model-sizing.md#size-in-responses)).

## Enforcement

An adapter hook may deny the coordinator's source edits and point it to the
implementer; the adapter README says what its hook covers. A hook keys on
whether the call comes from a subagent and fails open on any error. Shell
writes and reading are not covered by any hook; they fall under the rule
alone. Where an adapter has no such hook, the whole rule is wording.

## Lanes

Several implementers may run at once on disjoint slices. Concurrent writers
never share files or resources (P2); the coordinator assigns each lane its
files and integrates the results in one branch. A shared skill to run lanes
is not written yet.
