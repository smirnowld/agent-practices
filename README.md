# agent-practices

The single source of truth for how coding agents work on my projects: policy,
best practices learnt along the way, workflows, role definitions and output
templates. Rules live in this repository rather than in per-machine agent config, so a
new machine or a cloud sandbox starts from the same rules.

It is vendor-neutral. Claude Code and Codex both consume it through thin
adapters; no rule is written for one vendor only.

## Layout

```
policy/AGENTS.md        Always-on rules for every session (the policy)
practices/              Best practices and lessons, with the evidence behind them
skills/<name>/SKILL.md  Workflows loaded on demand (how to do a task)
roles/<name>.md         Agent roles: purpose, tools, capability tier
templates/              Output formats: updates, summaries, briefs, PRs, documents
.claude-plugin/          Plugin and marketplace manifests (the repo root is the plugin)
adapters/claude/        Claude Code agents, hooks, tier map
adapters/codex/         Codex role TOML, tier map, install notes
scripts/                sync-policy.sh (policy into projects), build-adapters.py (roles into agents), test-sync.sh
Makefile                `make check`: the same checks CI runs
```

## What goes where

| If it is… | Put it in | Test |
|---|---|---|
| A rule that must hold in every session | `policy/` | Would a session break the rule by not knowing it up front? |
| Knowledge with a reason and evidence | `practices/` | Is it advice to consult, not a rule to enforce? |
| A repeatable procedure | `skills/` | Does it describe *how* to do a task, step by step? |
| A delegated agent's job | `roles/` | Is it a kind of worker the parent hands work to? |
| The shape of an output | `templates/` | Does it describe *what* a result looks like? |
| Anything naming a vendor's file format, key or event | `adapters/<vendor>/` | Would it change if the vendor changed? |

Policy stays short because it loads into every session and some agents cap
instruction size (see adapters). Detail belongs in a practice, skill or
template, with policy linking to it.

## Precedence

Policy statement P1 in [policy/AGENTS.md](policy/AGENTS.md#p1-precedence)
sets what can override the policy: an explicit project override naming the
statement, or my explicit OK for one action.

## Vendor-neutral approach

- Content is plain Markdown. Roles and skills describe capability tiers
  ("fast exploration", "capable reasoning"), never model IDs.
- Adapters translate content into each vendor's format and are generated or
  thin wrappers, never hand-maintained second copies.
- If only one vendor supports a feature (for example per-role effort), the rule
  says what outcome is needed and the adapter explains the fallback.
- See [adapters/README.md](adapters/README.md) for the mapping and the facts it
  rests on.

## How sessions get it

- **Local:** each adapter installs from this repo (Claude plugin marketplace;
  Codex: skills, role files and a global `AGENTS.md`; see its adapter README).
- **Project repos:** each project's `AGENTS.md` carries the policy between
  sync markers, maintained by `scripts/`, so a project works even with no
  adapter installed, including in cloud sandboxes that only clone that project.
- **Cloud:** cloud sessions only clone the project and load no plugins, so
  they get the policy from the synced copy; skills and templates are local
  only ([adapters/README.md](adapters/README.md#why-the-synced-copy-stays)).
