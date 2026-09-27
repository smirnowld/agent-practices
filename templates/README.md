# Templates

Output formats shared by policy and skills. A template defines what a result
contains, not how to produce it. Link to a template rather than restating its
fields. Using the template is mandatory; empty sections may be omitted.

| Template | Used for | Stored |
|---|---|---|
| `brief.md` | Work package for another session or agent (P2c) | Message or chat, not the repo |
| `progress-update.md` | Checkpoint and compaction handoff (P14) | Chat |
| `acceptance-card.md` | My acceptance of user-facing work (P6) | Chat and PR |
| `closeout.md` | End of session (P15) | PR and chat |
| `pull-request.md` | PR description | PR |
| `adr.md` | Lasting decision, summary above the divider (P17) | `docs/adr/` |
| `docs/spec.md` | Current-state description of a feature | Project `docs/` |
| `docs/runbook.md` | Repeatable operational procedure | Project `docs/` |
| `docs/roadmap.md` | Product direction by phase (P19) | Project `docs/` |
| `docs/plan.md` | Current phase at a glance (P19) | Project `docs/` |
| `docs/architecture.md` | How the system fits together (P19) | Project `docs/` |
| `docs/tech-stack.md` | Choices, version policy, decisions (P19) | Project `docs/` |
| `docs/visuals.md` | Spec for the HTML visuals of those four docs | Project `docs/visuals/` |
| `docs/operations.md` | Where it runs, health, alerts, observability manifest (P20) | Project `docs/` |
| `docs/inventory.md` | What runs where, for infrastructure (P19) | Project `docs/` |
| `docs/recovery.md` | Backup and recovery procedures, last test (P19) | Project `docs/` |

Every link a template asks for follows P18: a full GitHub URL (commit SHA for
files, not a branch) or an attached file, never only a local path.
