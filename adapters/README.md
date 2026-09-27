# Adapters

How each agent consumes the neutral content. Vendor facts live only here, each
with its source and the date checked; "unverified" means not confirmed on the
vendor's own page.

| Content | Claude Code | Codex |
|---|---|---|
| Policy, local | Plugin `SessionStart` hook prints it, unless the project carries the synced copy | Global `AGENTS.md` pointing here, or the synced project copy |
| Policy, project and cloud | Synced block in the project's `AGENTS.md`, imported from `CLAUDE.md` | Synced block in the project's `AGENTS.md`, read natively |
| Skills | Plugin (repo-root `skills/`) | `.agents/skills` (user or repo level) |
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
`AGENTS.md`, kept current by `scripts/sync-policy.sh`. Skills, roles and
templates are not available in cloud sessions. Setup scripts have network
access on both, so cloning this repo during setup may work (unverified).

## Keeping adapters current

- Roles and tier maps: edit `roles/` or a `tiers.json`, run
  `python3 scripts/build-adapters.py`, commit the output. CI runs it with
  `--check`.
- Policy: after a policy PR merges, run `scripts/sync-policy.sh` over the
  project checkouts and open a PR in each.
- Re-check vendor facts when an adapter misbehaves or at the monthly audit.

Details: [claude/README.md](claude/README.md), [codex/README.md](codex/README.md).
