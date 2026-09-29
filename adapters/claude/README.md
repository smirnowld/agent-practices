# Claude Code adapter

Checked 2026-09-27 against https://code.claude.com/docs/en/ (pages cited
inline, relative to that URL).

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
- `skills/`: found by the default scan. A `skills` key would add to that
  scan, not replace it, and the `agents` key does not affect skills, so
  `plugin.json` needs no `skills` key (plugins/manifest-reference.md, "How
  each key combines with its default location").
- No `version` in either manifest, so the installed version is the commit SHA
  and every commit on the default branch becomes an available update
  (plugins/loading.md, "How Claude Code computes the version"); how it
  reaches a machine is under [Updates and running
  sessions](#updates-and-running-sessions).
- `hooks/hooks.json`: `SessionStart` on `startup|clear|compact` runs
  `session-start.sh`, whose stdout becomes context (hooks.md). It prints the
  policy only when the project lacks the synced block, so the policy never
  loads twice. `PreToolUse` on `mcp__ccd_session__spawn_task` runs
  `check-chip-brief.py` (see Chips below); it denies with
  `hookSpecificOutput.permissionDecision: "deny"`, and on its own errors
  exits 0 so the call proceeds (hooks.md, checked 2026-09-29). It needs
  `python3`; without it the hook fails and chips go through unchecked.
  `Stop` runs `check-attention.py` (see Waiting on me below); it blocks with
  top-level `decision: "block"` and a `reason`, reads the final text from
  `last_assistant_message` and skips when `stop_hook_active` is true or
  `background_tasks` is not empty (hooks.md, "Stop", checked 2026-09-29).

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
    "agent-practices": {
      "source": { "source": "github", "repo": "OWNER/agent-practices" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": { "agent-practices@agent-practices": true }
}
```

and imports the synced policy from `CLAUDE.md` with `@AGENTS.md`; `CLAUDE.md` holds only that import (baseline R1).

Plugin skills and agents are namespaced (`agent-practices:closeout`,
`agent-practices:reviewer`) (plugins/manifest-reference.md, `name`). If you
also keep user-level agents with the same names, both sets appear; keep one.

### Updates and running sessions

Sources: plugins/loading.md, settings-reference.md
(`extraKnownMarketplaces`), env-vars.md, sub-agents.md.

- A session loads plugins at startup and keeps that set. After an install
  or update, run `/reload-plugins` or start a new session. A session started
  before the install shows none of the plugin's skills or agents.
- A marketplace added from GitHub, like this one, does not auto-update by
  default, so the installed copy stays at the commit it was installed from.
  Turn it on with `"autoUpdate": true` on the marketplace's
  `extraKnownMarketplaces` entry in any settings file, as in the snippet
  above, or with **Enable auto-update** under `/plugin` → Marketplaces. When
  several settings files define the marketplace, the highest-precedence entry
  is used whole, so a project entry without `autoUpdate` hides the
  user-settings value in that project (inferred from both pages, not
  tested). Auto-update runs up to ten
  minutes after an interactive session's first message and applies from the
  next session or `/reload-plugins`. To update by hand:

  ```
  claude plugin marketplace update agent-practices
  claude plugin update agent-practices@agent-practices
  ```

- `DISABLE_AUTOUPDATER=1` (and likewise `DISABLE_UPDATES=1` or
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`) turns off the whole plugin
  auto-update pass and hides the **Enable auto-update** toggle, whatever
  `autoUpdate` says, unless `FORCE_AUTOUPDATE_PLUGINS=1` is also set
  (plugins/loading.md, "Which marketplaces and plugins auto-update";
  env-vars.md). The desktop app starts Claude Code with
  `DISABLE_AUTOUPDATER=1` (observed 2026-09-27 in the process environment,
  not stated in the docs). So in the desktop app, add this to user settings
  (`~/.claude/settings.json`) as well as setting `autoUpdate`; the variable
  was seen to reach desktop sessions, but an update arriving that way is not
  yet tested:

  ```json
  { "env": { "FORCE_AUTOUPDATE_PLUGINS": "1" } }
  ```

- When moving from user-level agents to the plugin, a session started before
  the install loses the user-level agents as soon as their files in
  `~/.claude/agents/` are deleted, and gets the plugin agents only after
  `/reload-plugins`. Claude Code watches that directory for added and edited
  files (sub-agents.md, "Write subagent files"); removal from running
  sessions was observed 2026-09-27 and is not stated in the docs.

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
- Chips (P2c): a session I am offered as a desktop-app chip, whether from
  `spawn_task` or a scheduled routine (below), is a brief. Its prompt is filled
  from [`templates/brief.md`](../../templates/brief.md), heading and Model line
  at the top, not written as a free-form task. `spawn_task` cannot set model or
  effort (it takes a title, a summary, a prompt and a directory; observed
  2026-09-29, unverified against vendor docs), so the chip's summary repeats
  the Model line's model and effort for me to pick when I start it, and the
  started session runs the model check above. A `PreToolUse` hook
  ([`hooks/check-chip-brief.py`](hooks/check-chip-brief.py)) denies a
  `spawn_task` prompt without the brief's heading, Model line, Goal and Proof,
  and returns the template so the retry is one call. The hook fires on the
  desktop app's `mcp__ccd_session__spawn_task` (observed 2026-09-29 with a
  test chip; unverified against vendor docs).
- Waiting on me (P6b): the desktop app shows a session as needing input
  only while a permission prompt, `AskUserQuestion` or another input prompt
  is open (agent-view.md, checked 2026-09-29); a turn ending in prose counts
  as finished. So a decision or acceptance is asked with `AskUserQuestion`
  (an acceptance card as accept / change / reject, proposed first) after the
  card is shown, and a closeout or a hand-off to me (a merge I own, a command
  to run) ends with `PushNotification`, one line under 200 characters; the
  tool skips it while I am at the session (both from the tool's own
  description, observed 2026-09-29, unverified against vendor docs). Both
  can be deferred tools, loaded with ToolSearch `select:NAME` first. The
  `Stop` hook ([`hooks/check-attention.py`](hooks/check-attention.py))
  blocks a turn once when its final message, outside code fences, holds an
  acceptance card, question, "Decision needed", a "Waiting on me" line other
  than "nothing", "none" or "n/a", or a closeout heading, and neither tool was
  called since my last message or my last answer to `AskUserQuestion`. It
  finds that boundary in the transcript by entry shape (observed, not
  documented). If the plugin is enabled for headless (`-p`) or SDK runs,
  where `AskUserQuestion` may be unavailable, the one forced extra turn
  there is unverified. Whether the app's
  finished-session notification reaches me, and whether phone pushes are on,
  are my app settings (settings-reference.md, `preferredNotifChannel`;
  remote-control.md, "Mobile push notifications"; not checked on this
  machine).
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
  context").

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
