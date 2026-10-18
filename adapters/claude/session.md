# Claude Code session bindings

The policy and skills name actions; this is the tool that does each one in
Claude Code. Printed at every session start. Evidence and dates:
[README.md](README.md#session-rules-specific-to-this-agent).

Any tool named here may be deferred: if it is not callable, load it with
ToolSearch `select:NAME` before judging it absent. Chat is the fallback only
when ToolSearch cannot find it either, and the report says so.

- **Propose or start a session** (P2c, `brief` step 6, closeout, routines):
  `mcp__ccd_session__start_session`, one call per brief, `context` "fresh".
  The prompt is the filled brief, the title its title, `background` why now.
  Pass the Model line's model as `model` (the id the app's picker offers)
  and its effort as `effort`. `initiation` is "own_initiative" (a card I
  start) unless I asked here in words to start it now ("user_asked"), or
  "offer" when my latest message names the task without saying where it
  runs: the title alone first, then the brief with the returned
  `proposal_id` if I pick a new session. A turn another session or an
  event started may only propose. The app silently
  caps both values at the starter's own model and effort, cards included,
  so a session above that cap starts only as a card (a hook enforces
  this): its model check (P2d, below) asks this session to switch it up,
  which the app puts to me. Briefs listed only in chat are not proposed.
  Older app builds have `mcp__ccd_session__spawn_task` instead, with no
  model or effort: its summary repeats the Model line's.
- **Title and place a session** (P2a, `templates/session-title.md`): rename
  with `mcp__ccd_session_mgmt__set_session_title` and `session_id` `self`, at
  start once sized, before the first turn ends even for a one-answer task
  (started by a skill: before its first step), and whenever the autonomy
  marker moves up. A proposed session's title is already in that form; a
  Stop hook blocks a turn end while the title is not and no rename was
  tried. Move into a project with
  `mcp__ccd_directory__change_directory`; the move applies when the turn ends.
  A declined rename or move is not retried, and an unattended session does
  not move.
- **File into a thread group** (`practices/tracking.md`, Threads): once
  titled and the thread is known (the brief's Thread line, else the board
  item the work belongs to), list the sidebar groups with
  `mcp__ccd_sidebar__list_groups`; if none carries the thread's short name
  (or the name my own agent configuration gives it), `create_group` it;
  then `move_sessions` this session into it. No thread: the group "Other".
  No group-removal tool is verified, so groups of closed threads stay
  until one is. Only agents manage groups; a declined call is not retried,
  and an unattended session skips this. Desktop-app sessions only: cloud
  sessions have no sidebar tools; their thread is the brief's Thread line.
- **Work in flight** (`brief` step 1): `mcp__ccd_session_mgmt__list_sessions`
  (`linked` true for the sessions this one started, unfiltered for the
  rest), plus this session's
  own `start_session` cards not yet started, and the board's
  In progress and In review items (Board actions below). Cards not yet
  started from other sessions or routines are invisible; say so.
- **Board actions** (P19b, `brief`, `closeout`, `board-review`, `idea`,
  `today`, `weekly-review`): `gh
  project` through the shell, with `gh api` for what it lacks (REST for
  sub-issues; graphql for issue timelines and an item's other boards). Read the board: `gh
  project item-list NUMBER --owner OWNER --format json`, narrowed with
  `--query` (the board's filter syntax); fields and option IDs: `gh project
  field-list`. Move an item: `gh project item-edit` with the item, field
  and option IDs. File an assigned item: `gh issue create --assignee @me
  --label maintainer-step`, then `gh project item-add`; in a public
  repository a draft with `gh project item-create`, assigned with `gh api
  graphql`, with its Kind and Area set. No board access (`gh auth status`
  lacks the `project` scope) in a repository with issues: still file a
  step with `gh issue create --assignee @me --label maintainer-step` and a
  finding with `gh issue create --label deferred-review`, the priority in
  the issue text; the board's auto-add picks them up. Only in a public repository, where no
  issue can be filed, say so and put the step or finding in chat. A cloud
  session cannot reach boards at all (no GraphQL, no organisation paths):
  board reads and writes, a thread's Next step at closeout included, need a
  local session, so a cloud session hands its board update to me as a step
  under **Needs you**, and a brief written there says `Thread: unknown,
  ask me` unless I named it. Whether `gh issue create` works there is
  unverified; if it fails, the step or finding goes in chat.
- **Delegate a role** (P2, P2b): the Agent tool with `subagent_type`
  `agent-practices:ROLE` (explorer, implementer, light-reviewer, reviewer,
  critical-reviewer, critical-reviewer-strongest); `model` sets a slice's
  tier (`tiers.json`) and never lowers a reviewer below the implementer's.
  A PreToolUse hook denies this session's own `Edit`/`Write` on source; docs
  and a config file on the brief's `Coordinator edits:` line pass.
- **Model check** (P2d): a session started at its brief's model and effort
  has nothing to switch; the handshake is for a brief above its starter's
  cap, or a session started without them. On a mismatch, send the parent "Switch me to MODEL at
  EFFORT: SESSION_ID" with `mcp__ccd_session_mgmt__send_message` and wait.
  The parent switches it with `mcp__ccd_session_mgmt__set_session_model` and
  `set_session_effort`, replies
  "Switched; continue with the brief." and does nothing else that turn. The
  model id is one the app's picker offers; a wrong id makes the tool list
  the valid ones. It switches its own child to a cheaper model or lower
  effort without asking me; a costlier one, above its own level included,
  only with my approval: ask me first unless the app will prompt for the
  call (not in bypass-permissions mode, tool not allow-listed), and then
  its prompt counts. Denied: tell me and stop. With no parent, ask me to
  switch with `/model` and `/effort` and stop.
- **Ask me, or wait on me** (P6b): questions and acceptance cards are chat
  text, numbered Q1, Q2 with options and a proposed default, answered in one
  reply ("Q1 A, Q2 B"); the closing Reply line
  ([question.md](../../templates/question.md)) is what the app's suggested
  reply can match. `AskUserQuestion` is not required. A turn that ends on
  my decision, acceptance, a closeout or a hand-off sends
  `PushNotification`: one line under 200 characters naming what waits on me. Everything a
  question depends on (commands, steps, a card) is in the chat text, never
  only in thinking or a tool result. Never re-ask an unchanged question.
- **Drive my browser** (P9a), within the limits in
  [writing-to-me.md](../../practices/writing-to-me.md#steps-for-me): Claude in
  Chrome (`mcp__claude-in-chrome__*`; load the tools the step needs plus
  `enter_verification_code` in one ToolSearch), my Chrome with its sign-ins;
  not the built-in browser, which has neither. Sign in with
  `request_credentials` for that login only, then `autofill_credential`; a
  code through `enter_verification_code` (I approve each; you never see the
  values); `release_credentials` when done. Not connected: numbered steps.
- **Publish an evidence page** (`acceptance-evidence` step 5): the Artifact
  tool, building without `--full` (the tool adds doctype, head and body).
  First publish: `file_path` `OUT_DIR/index.html`, `root` `OUT_DIR`, `files`
  the map in `OUT_DIR/files.json`, `icon` `camera`. Republish in the same
  session: the same call with the same `file_path`, which keeps the URL,
  and no `icon`; from another session, first `action` `read` with the
  page's `url`, then publish with that `url`. On every republish, list the
  page's files (`action` `list`, `scope` `files`, its `url`) and add to
  `files`, mapped to `null`, each `img/` path listed there but missing from
  `OUT_DIR/files.json`. Loading
  `artifact-design` is still required; its page contract (title, both
  themes, phone width) is met by the template, and its design pass does not
  apply (the skill's precedence line). Give me the URL; it stays private.
- **Wait on CI or a merge** (P6b, `merge` step 4): run `wait-for` (the
  plugin's `bin/` is on the Bash PATH) with Bash `run_in_background` and a
  `timeout` above its deadline: 4200000 ms covers the defaults (45 and 60
  min); the tool's maximum is 7200000. Run it bare, without `; echo $?`;
  read the exit code and last line it reports. Before a push or
  `gh pr merge --disable-auto` that makes your wait stale, stop it with
  `TaskStop`; at closeout none is running. The Auto-fix monitor
  (`mcp__ccd_pr__set_monitor`) is not a wait.
