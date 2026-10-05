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
  `session-start.sh`, whose stdout becomes context (hooks.md). It prints
  [session.md](session.md) every time, and the policy only when the project lacks the synced block, so the policy never
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

To run a role below its tier (critical review at standard, per
`practices/model-sizing.md`), pass the standard tier's alias as the Agent
tool's per-invocation `model`. It takes precedence over the agent's
frontmatter `model` (sub-agents.md, "Choose a model", checked
2026-09-30). The page lists no per-invocation effort, so the frontmatter
`effort` is inferred to still apply, and whether `xhigh` is available on the
standard model is unverified.

## Session rules specific to this agent

The rules a session follows are in [session.md](session.md), which the
`SessionStart` hook prints every time, synced project or not. This section
holds the evidence behind them and the rules sessions do not need at start.
Tool names there were observed in desktop-app sessions (2026-09-30),
unverified against vendor docs.

- Model check (P2d): the rule is in [session.md](session.md).
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
  or whose Model line names a tier without its `tiers.json` model (sessions
  wrote "standard" and named the model only in their final message,
  2026-09-30), and returns the template so the retry is one call. The hook fires on the
  desktop app's `mcp__ccd_session__spawn_task` (observed 2026-09-29 with a
  test chip; unverified against vendor docs).
- Proposing sessions (`brief` skill): the rule is in
  [session.md](session.md); the model it names comes from `tiers.json`
  (Sonnet for fast, Opus for standard). Before session.md was
  printed at start, sessions told to use the `brief` skill wrote briefs in
  chat and made no chips until reminded (2026-09-30). Where sessions default to another model, I pick the
  chip's model when I start it; otherwise the started session stops at the
  model check and asks to be switched. In-flight work for the skill's
  step 1: the desktop app's `list_sessions` lists other sessions; its
  description does not mention chips not yet started (tool description, checked 2026-09-30, unverified
  against vendor docs), so the skill also checks this session's own earlier
  `spawn_task` calls; chips from other sessions or routines not yet started
  stay invisible.
- Waiting on me (P6b): the desktop app shows a session as needing input
  only while a permission prompt, `AskUserQuestion` or another input prompt
  is open (agent-view.md, checked 2026-09-29); a turn ending in prose counts
  as finished. Hence the `AskUserQuestion` and `PushNotification` rule in
  [session.md](session.md). `PushNotification` skips while I am at the
  session (both from the tool's own description, observed 2026-09-29,
  unverified against vendor docs). `AskUserQuestion` takes at most four
  questions of two to four options each (its schema, observed 2026-09-30,
  unverified against vendor docs). Both
  can be deferred tools, loaded with ToolSearch `select:NAME` first. The
  `Stop` hook ([`hooks/check-attention.py`](hooks/check-attention.py))
  blocks a turn once when its final message, outside code fences, holds an
  acceptance card, question, "Decision needed", a "Waiting on me" or
  "Waiting on the maintainer" line other than "nothing", "none" or "n/a",
  or a closeout heading, and neither tool was called since my last message or my last answer to `AskUserQuestion`. It
  finds that boundary in the transcript by entry shape (observed, not
  documented). It also blocks a chat closeout missing a required summary field of
  `templates/closeout.md` (Status, TL;DR), and a turn whose `gh pr merge` call succeeded
  (not `--auto`, `--disable-auto` or `--help`) without a later body rewrite
  (`gh pr edit` with a body flag, or `gh api` with `body=`) or with no
  closeout sent in chat this session. It blocks a turn that ends while a PR
  created this session with a successful `gh pr create` has no later
  `gh pr merge` (`--auto` counts; a later `--disable-auto` undoes it unless
  the PR was already merged or closed) or `gh pr close`, unless a closeout was
  sent this session or the turn called `AskUserQuestion` that is not yet
  answered. A turn that starts with my dismissing a question is waiting on me,
  so neither this rule nor the ask-signal rule fires; the merge and closeout
  checks still do. In a home-server repo (2026-10-05) the open-PR
  rule turned a dismissal into a premature closeout. A question a hook denied
  counts as neither asked nor answered. A dismissal's tool
  result reads "User dismissed" (observed, not documented). Each PR is tracked by the one PR URL its create printed, else by
  the first number or URL a merge or close names for it as its first
  argument that is not a flag or a flag's value. One naming no PR settles
  the latest still open, else the latest on auto-merge; one naming it by a
  variable bound by a `for` over literal PR numbers or URLs (until a
  `name=` assigns it again) settles those, and any other variable settles all
  it would change; a lone quoted `"$n"` counts as the variable. A create run alone in its
  call that printed output but no PR URL is taken as failed, since an error
  piped through `tail` does not fail the call. Commands run by subagents
  count: their transcripts sit in a nested `subagents/` folder (hooks.md,
  "SubagentStop", `agent_transcript_path`, checked 2026-09-30), which is
  observed to be beside the session's transcript, with workflow agents one
  level deeper, and they are merged by entry timestamp (observed, not
  documented). Quoted strings, heredoc bodies, comments and `echo` or
  `printf` arguments are not read as commands. All reasons go in one block.
  Known limits: a PR created or merged inside a script, an alias or `gh api`
  is not seen, nor one whose URL went elsewhere while other output was
  printed; a create whose output holds several PR URLs is known by none of
  them; a merge or close of another PR can settle one of the session's whose
  create printed no URL (as in `url=$(gh pr create)`); a merge or close in a
  call that failed for another reason is not counted; and PR numbers are not
  told apart by repository. If the plugin is enabled for headless (`-p`) or SDK runs,
  where `AskUserQuestion` may be unavailable, the one forced extra turn
  there is unverified. Whether the app's
  finished-session notification reaches me, and whether phone pushes are on,
  are my app settings (settings-reference.md, `preferredNotifChannel`;
  remote-control.md, "Mobile push notifications"; not checked on this
  machine).
- Questions that point at unseen content (P6b): thinking is not shown to me;
  the desktop app shows a one-line summary of it, which reads as if the
  content was sent. Sessions in a product repo (2026-10-04) and a home-server
  repo (2026-10-05) wrote the commands I was to run only in thinking, then
  asked "tell me when you've run them". Both later told me the app had
  collapsed a sent message, but their transcripts held no text block; that
  explanation was wrong. The `PreToolUse` hook
  [`hooks/check-question.py`](hooks/check-question.py) denies an
  `AskUserQuestion` call when no chat text came after the last tool result (a
  `PushNotification` or `ToolSearch` result does not count, so a closeout's
  question passes, and so does this hook's own denial); the reason says the
  user has not seen anything planned in thinking. Its first version (2026-10-05) checked only questions under 100
  characters and let an unchanged retry through if the question was
  self-contained. Within hours agents took that retry almost every time, three
  seconds after the denial, still believing their thinking had been sent, and
  questions over 100 characters pointed at commands only in thinking too
  (a product repo, a home-server repo). So now every question needs text
  before it, and a retry passes only if that text is in the transcript. Replayed on 486 questions from ten
  days of sessions (2026-10-05), 350 had no text right before them; each
  costs one denial until the agent writes some, which the session rule says
  to do first. The hook cannot judge whether that text holds what the
  question depends on: thinking is mostly stored empty, so it cannot be
  compared. Text written in the same message as the question is sometimes
  not yet in the transcript when the hook runs: of 13 questions with text
  before them on 2026-10-05, 3 were denied, the text 3 to 5 seconds before the
  call. The denial's own result
  therefore does not count as a step, so the unchanged retry finds that text
  and passes. Text before parallel tool calls whose results land first would
  still cause a needless denial (not observed).
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
  `/compact keep: goal, decisions, core files, proof status, next step`
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
