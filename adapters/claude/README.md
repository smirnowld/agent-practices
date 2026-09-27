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
claude plugin marketplace add OWNER/agent-practices
claude plugin install agent-practices@agent-practices
```

A project that wants it for everyone adds to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "agent-practices": { "source": { "source": "github", "repo": "OWNER/agent-practices" } }
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
  desktop app's session-model and session-effort tools, replies "Switched;
  continue with the brief." and does nothing else that turn. With no
  reachable parent, the session asks me to switch it with `/model` and
  `/effort` and stops.
- Scheduled routines (`docs-drift-check`, `triage`, `issue-review`,
  `project-setup` audit) run as local desktop-app scheduled tasks, one per
  project; a proposed session appears as a chip. Local tasks fire only while the app is open and the
  machine awake; a missed run catches up once
  (https://code.claude.com/docs/en/desktop-scheduled-tasks, checked
  2026-09-27).
- Local-only paths are not links (P18): cite a GitHub URL pinned to a commit,
  or attach the file.
- Context: the compaction threshold is `autoCompactWindow` in user settings
  (model-config.md); tuned per `practices/context-efficiency.md`. Before
  suggesting compaction, check `/context`; suggest
  `/compact keep: goal, decisions, owned files, proof status, next step`
  (https://code.claude.com/docs/en/claude-code-on-the-web.md, "Manage
  context"). `/usage` supplies totals for
  [measuring a change](../../practices/context-efficiency.md#measuring-a-change)
  (unverified that it splits cached tokens).

## Cloud sessions

Cloud sessions run the environment's setup script as root on Ubuntu, and a
script that exits non-zero stops the session from starting
(https://code.claude.com/docs/en/cloud-environments.md, "Setup scripts",
checked 2026-09-27). Plugins do not load there
([why](../README.md#why-the-synced-copy-stays)); this adapter installs skills,
roles and the path to templates from the setup script instead. Documented
alternatives are skills and agents committed in the project's `.claude/`, and
skills enabled on the claude.ai account (same page, "What carries over").

```bash
#!/bin/bash
root=/opt/agent-practices
line="agent-practices root (templates, practices, policy): $root"
{
  echo "pwd: $(pwd) HOME: $HOME"
  rm -rf "$root"
  git clone --depth 1 https://github.com/OWNER/agent-practices "$root" \
    && mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents" \
    && cp -R "$root/skills/." "$HOME/.claude/skills/" \
    && cp "$root"/adapters/claude/agents/*.md "$HOME/.claude/agents/" \
    && { grep -qxF "$line" "$HOME/.claude/CLAUDE.md" 2>/dev/null || echo "$line" >> "$HOME/.claude/CLAUDE.md"; } \
    && echo "copied: $(ls "$HOME/.claude/skills" | tr '\n' ' ')"
} >/tmp/setup.log 2>&1
exit 0
```

- **Caching.** The script runs once; later sessions reuse a snapshot until
  the script or allowed hosts change or about 7 days pass (same page,
  "Environment caching"). After a merge here, or if skills are missing, edit
  the script (any change, e.g. a comment with the date) to rebuild.
  `/tmp/setup.log` describes the build, not the current session.
- **Observed 2026-09-27, one session, undocumented:** the script runs in
  `/home/user`, the project is cloned to `/home/user/REPO`, and skills in
  `$HOME/.claude/skills/` and the line in `$HOME/.claude/CLAUDE.md` load in
  the session.
- The policy still comes from the project's synced `AGENTS.md`.

## Not verified

- Whether the desktop app's scheduled tasks can be defined from a repo file.
- Cloud: that `/home/user` is stable, that files the setup script writes to
  `$HOME/.claude/` keep loading, and that roles copied to
  `$HOME/.claude/agents/` load (skills were observed; roles not yet).
- Starting a cloud session from the desktop app failed once ("Failed to
  fetch", 2026-09-27) while the web worked.
