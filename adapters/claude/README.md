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
  `last_assistant_message` and skips when `stop_hook_active` is true
  (hooks.md, "Stop", checked 2026-09-29). It ignores `background_tasks`
  and reads the session's waits from the transcript instead (Waiting on CI
  below).

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
  as finished. `PushNotification` reaches me instead; it skips while I am at
  the session (its own description, observed 2026-09-29, unverified against
  vendor docs). Questions were first required to go through
  `AskUserQuestion`, enforced by a `PreToolUse` hook and the `Stop` hook. Over
  about two weeks of sessions (counted 2026-10-06) the question hook denied
  47 questions before I saw them, I dismissed 19, and the `Stop` hook forced
  139 extra turns (59 in one day), each re-reading the whole context. So
  questions moved to chat, numbered with a default (`templates/question.md`),
  plus one `PushNotification`; the question hook was removed, and so was the
  `Stop` hook's open-PR rule, which blocked 30 turns in ten days and in a
  home-server repo (2026-10-05) turned a dismissed question into a premature
  closeout. The trade-off: the session no longer shows "needs input" for a
  chat question; the notification carries that. Thinking is not shown to me
  (the app shows a one-line summary that reads as if the content was sent),
  and sessions in a product repo (2026-10-04) and a home-server repo
  (2026-10-05) wrote the commands I was to run only in thinking; the session
  rule therefore puts everything a question depends on in chat text, but no
  hook checks it now.
  The `Stop` hook ([`hooks/check-attention.py`](hooks/check-attention.py))
  now blocks a turn once, all reasons in one block, when:
  - its final message, outside code fences, holds an acceptance card, a
    question (heading, "Decision needed", or a numbered Q1 line), a
    "Waiting on me" or "Waiting on the maintainer" line other than
    "nothing", "none" or "n/a", or a closeout heading, and neither
    `PushNotification` nor `AskUserQuestion` was called since my last
    message. It finds that boundary in the transcript by entry shape
    (observed, not documented). A turn that starts with my dismissing a
    question is waiting on me and is not blocked for this. When my answer
    to a question is the turn's last entry and no text follows it, a final
    message equal to the text I answered is not checked again;
  - it says it is waiting on CI, a run or a merge while none of the
    session's own GitHub waits is running, or it ends while one of its own
    `wait-for` waits runs without saying it is waiting (below);
  - a chat closeout misses a required summary field of
    `templates/closeout.md` (Status, TL;DR), or was written without the
    `agent-practices:closeout` skill loaded this session (a `Skill` call or
    the `/closeout` command);
  - a PR merged this turn without a later body rewrite (`gh pr edit` with a
    body flag, or `gh api` with `body=`), without the closeout skill, or
    with no closeout sent in chat this session. A merge is a successful
    `gh pr merge` (not `--auto`, `--disable-auto` or `--help`) or, once the
    session turned auto-merge on and did not turn it off, its landing: a
    background `wait-for pr-ci` or `pr-merged` whose task notification
    reports exit code 0 (the notification carries no output; a wrapper such
    as `; echo $?` hides the code, so it is not counted, while a redirection
    is), or a tool result holding wait-for's final `merged:` or `passed:`
    line or `"state":"MERGED"` from `gh pr view`, each for the PR that
    auto-merge was turned on for (by number or URL, never a redirection's
    fd or the `--match-head-commit` SHA; none means the branch's own, which
    matches any, and a numbered `--disable-auto` turns that off too). A
    landing counts once, in the turn that sees it first. `passed:` means CI
    passed, so an auto-merge that then stalls is blocked once; a later
    `gh pr view` of that PR showing `"state":"OPEN"` with a non-null
    `autoMergeRequest` (merge skill step 5) re-arms it, so its real landing,
    in that turn or a later one, is blocked again.
  It reads only the session's own transcript, so a merge run by a subagent
  is not seen. A question denied by some other `PreToolUse` hook counts as
  neither asked nor answered. If the plugin is enabled for headless (`-p`) or SDK
  runs, the one forced extra turn there is unverified. Whether the app's
  finished-session notification reaches me, and whether phone pushes are on,
  are my app settings (settings-reference.md, `preferredNotifChannel`;
  remote-control.md, "Mobile push notifications"; not checked on this
  machine).
- Waiting on CI (P6b, `merge` step 4): in 5 of the 7 sessions over about two
  weeks where I had to nudge an agent about CI (counted 2026-10-06), it had
  written that it was waiting and would report, then ended its turn with
  nothing running that could wake it; one more expected the app's Auto-fix
  monitor to wake it. That monitor (`mcp__ccd_pr__set_monitor`) wakes a
  session on CI failures, merge conflicts and review comments, never on
  success (its tool description, observed 2026-10-06, unverified against
  vendor docs). A Bash call with `run_in_background` re-invokes the session
  when it exits (its tool description, unverified against vendor docs), and
  did so in all 344 background waits checked; a
  foreground call stops at 10 minutes, and 36 foreground CI waits timed out
  that way. The hook finds the session's waits in its transcript (all
  observed 2026-10-06, not documented): a Bash call running `wait-for`,
  `gh run watch` or `gh pr checks --watch` whose result reads "running in
  background with ID: ID" or, after a foreground timeout, "moved to the
  background (ID: ID)"; it ends with a `<task-notification>` naming the task
  or tool-use id, found in a user message or, mid-turn, in a
  `queued_command` attachment and queue operations, or with a `TaskStop` of
  the task (or of its older name, `KillShell`). Run over 150 recent
  sessions, it reported no wait still open.
  It blocks a final message whose sentence pairs a waiting phrase with CI,
  a run, a check or a merge while no such wait runs, unless the wait is on
  me ("once you accept"); a "when CI passes or fails" list of outcomes
  describes waits and passes. It also blocks a turn that ends while a
  `wait-for` of its own runs and no sentence pairs a waiting phrase with a
  wait, CI, a run or a merge, asking it to say so or `TaskStop` the wait; a
  closeout leaves none running. It ignores `background_tasks` in the hook
  input: its entries' shape is unverified, and an unrelated dev server must
  not excuse a waiting claim. Known limits: a waiting claim in other words
  passes, as does one tied to "you" or "your" ("once your CI passes"); a
  claim to wait on a background test run or subagent, which does notify
  the session, is blocked once (the reason says to end the turn again); a
  wait started in a form it does not parse (as an `if` or `while` condition, say) is not seen;
  a wait that ended without a notification in the transcript, such as one
  lost to a crash, still counts as running, and a sentence that mentions
  both waiting and CI for another reason is blocked once (the reason says
  to end the turn again if nothing is awaited). A repeat stop always ends
  the turn, so no rule can block twice in a row.
- Waits that never end (`bin/wait-for`, `merge` steps 4 and 5): in the
  transcripts of sessions on a product repo from 2026-09-30 to 2026-10-06,
  191 of 515 background tasks were waits on GitHub (observed). Waits built
  on `gh run watch RUN_ID` always ended. Hand-written loops did not: a merge
  wait that looked up a prerequisite PR by the other session's branch name
  got `null null` (the PR was on another head branch), read it as pending
  and ran into its 2-hour timeout, and a second session's copy ran 116 min
  before failing; a CI wait pinned to a head commit exited only on merged,
  closed or a failed check, so a merge conflict, which stopped CI from
  starting, left the session silent for 37 min, and after the next push
  the watcher outlived the merge; `until state != OPEN` merge loops ran 50
  to 83 min, since a push turns auto-merge off and leaves the PR open with
  nothing pending. Sleeping cost no tokens; the cost was lost time and
  attention, and a wake-up after more than an hour idle rewrites the cache:
  in one stuck session of about 23.6M cache reads, the turn woken by the
  killed 2-hour wait used 0.68M cache reads and 83k cache writes, about 7%
  of the session's cost (observed 2026-10-06). `wait-for` therefore ends on every state, and an unreadable one ends
  the wait. The plugin's `bin/` is on the Bash tool's PATH (observed
  2026-10-06, unverified against vendor docs). Whether `background_tasks`
  entries name their command or description is unverified: a `Stop` hook
  added to a running session's project settings did not fire, so the
  `Stop` hook reads the session's own waits from the transcript (above).
- Decision card (tried 2026-10-06, dropped the same day, P6b): one page
  per wait with the proposed option preselected for each item, one-tap
  choices and a single answer line ("#78 accept, Q1 B, briefs: 1"), shown
  in addition to the chat text and the push. Tried in a session of a
  tooling repo:
  - In-chat widget (`show_widget`): renders on desktop but not on the
    phone. With one of the app's two copies of the tool, `sendPrompt`
    posted nothing; with the other, it filled my message box and I still
    pressed Enter. About 1,500 output tokens per card, plus up to about
    60 KB of tool guide once per session.
  - Private Artifact page with the `db` capability: renders on the phone
    and Send saves the answer, but the page cannot wake the session, so I
    still typed "sent". 1-2 minutes per card; about 350-500 output tokens
    per card plus about 12,000 input tokens of guides once per session.
  - Why it lost: opening a page for every wait is tedious, and it never
    became send-and-forget, since I still had to type in the session. Chat
    text costs about 200 tokens per wait, and the app usually suggests the
    proposed reply, which I accept with Tab. So questions stay chat text
    that ends with the full proposed reply on its own line
    ([question.md](../../templates/question.md)), which the suggestion
    can match. Tool behaviour and the suggested reply observed 2026-10-06,
    unverified against vendor docs; sizes are estimates.
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
