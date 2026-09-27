# Claude Code adapter

Checked 2026-09-27 against https://code.claude.com/docs (pages cited inline).

## Packaging

The repository root is the plugin (`.claude-plugin/plugin.json`) and its own
marketplace (`.claude-plugin/marketplace.json`, plugin source `"."`), so
`skills/` loads as-is and `${CLAUDE_PLUGIN_ROOT}` reaches `templates/`,
`practices/` and `policy/`
(plugins/manifest-reference.md, plugins/marketplace-reference.md).

- `agents/`: generated from `roles/`; listed in `plugin.json`, which replaces
  the default `agents/` scan. Frontmatter `model` takes `sonnet`, `opus`,
  `haiku`, `fable` or `inherit`; `effort` takes `low` to `max`
  (sub-agents.md).
- `hooks/hooks.json`: `SessionStart` on `startup|clear|compact` runs
  `session-start.sh`, whose stdout becomes context (hooks.md). It prints the
  policy only when the project lacks the synced block, so the policy never
  loads twice.

## Install

User level, once per machine:

```
claude plugin marketplace add <owner>/agent-practices
claude plugin install agent-practices@agent-practices
```

A project that wants it for everyone adds to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agent-practices": { "source": { "source": "github", "repo": "<owner>/agent-practices" } }
  },
  "enabledPlugins": { "agent-practices@agent-practices": true }
}
```

and imports the synced policy from `CLAUDE.md` with `@AGENTS.md`.

Plugin agents are namespaced (`agent-practices:reviewer`). If you also keep
user-level agents with the same names, both sets appear; keep one.

## Tier mapping

`tiers.json` maps tiers to model aliases (`sonnet`, `opus`, `fable`), which
move with releases, so no numbered model IDs. "Read-only" tool sets include
the shell, so read-only is enforced by the role's instructions, not by tools.

## Session rules specific to this agent

- Model check (P2d): a session started from a brief whose model or effort
  differs from the brief's Model line sends its parent "Switch me to <model>
  at <effort>: <session id>" and waits; the parent switches it with the
  desktop app's session-model and session-effort tools.
- Scheduled routines (`docs-drift-check`, `triage`, `issue-review`,
  `project-setup` audit) run
  as local desktop-app scheduled tasks, one per project; a proposed session
  appears as a chip. Local tasks fire only while the app is open and the
  machine awake; a missed run catches up once
  (https://code.claude.com/docs/en/desktop-scheduled-tasks, checked
  2026-09-27).
- Local-only paths are not links (P18): cite a GitHub URL pinned to a commit,
  or attach the file.
- Context: the compaction threshold is `autoCompactWindow` in user settings
  (model-config.md); tuned per `practices/context-efficiency.md`.

## Not verified

- Whether the desktop app's scheduled tasks can be defined from a repo file.
