# Adapters

How each agent consumes the neutral content. Vendor facts live only here, each
with its source and the date checked; "unverified" means not confirmed on the
vendor's own page.

| Content | Claude Code | Codex |
|---|---|---|
| Policy, local | Plugin `SessionStart` hook prints it, unless the project carries the synced copy | Global `AGENTS.md` pointing here, or the synced project copy |
| Policy, project and cloud | Synced block in the project's `AGENTS.md`, imported from `CLAUDE.md` | Synced block in the project's `AGENTS.md`, read natively |
| Skills | Plugin (repo-root `skills/`); cloud: setup script | `.agents/skills` (user or repo level) |
| Session bindings (action to tool) | `claude/session.md`, printed by the `SessionStart` hook | `codex/session.md`, pointed to from the global `AGENTS.md` |
| Roles | Generated `claude/agents/*.md` in the plugin | Generated `codex/agents/*.toml`, copied to `~/.codex/agents/` or `.codex/agents/` |
| Routines | Desktop scheduled tasks | Desktop scheduled tasks |
| Tiers | `claude/tiers.json` | `codex/tiers.json` |
| Templates, practices | Read from the plugin root | Read from a local clone |

## Why the synced copy stays

Cloud sessions of both agents only clone the project. Claude cloud sessions
do not load plugins, even when the project's settings declare them
(https://code.claude.com/docs/en/settings.md, "Settings in cloud sessions",
checked 2026-09-27). Codex cloud's plugin and skill loading is undocumented.
So the policy reaches every session only through the project's own
`AGENTS.md`, kept current by `scripts/sync-policy.sh`. For Claude cloud
sessions the adapter's setup script clones this repository and installs
skills and roles (observed working for skills 2026-09-27; see
[claude/README.md](claude/README.md#cloud-sessions)). For Codex cloud the
same approach is unverified.

## Keeping adapters current

- Roles and tier maps: edit `roles/` or a `tiers.json`, run
  `python3 scripts/build-adapters.py`, commit the output. CI runs it with
  `--check`.
- Policy: when a policy PR merges, the `sync-policy` workflow runs
  `scripts/push-policy-sync.sh` over the projects in the Actions variable
  `POLICY_SYNC_REPOS`. Each project gets one sync PR. Auto-merge goes on,
  pinned to the sync commit, only when that commit changes nothing but the
  policy block in `AGENTS.md`; otherwise the PR stays open for review. A
  later policy change updates that PR instead of opening another, and the
  next run closes it if the default branch caught up another way. The
  workflow also runs weekly, retrying failures; to run it at once, `gh
  workflow run sync-policy`.
- Re-check vendor facts when an adapter misbehaves or at the monthly audit.

Details: [claude/README.md](claude/README.md), [codex/README.md](codex/README.md).
