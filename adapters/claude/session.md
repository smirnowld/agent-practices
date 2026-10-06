# Claude Code session bindings

The policy and skills name actions; this is the tool that does each one in
Claude Code. Printed at every session start. Evidence and dates:
[README.md](README.md#session-rules-specific-to-this-agent).

Any tool named here may be deferred: if it is not callable, load it with
ToolSearch `select:NAME` before judging it absent. Chat is the fallback only
when ToolSearch cannot find it either, and the report says so.

- **Propose a session** (P2c, `brief` step 6, closeout, routines): one
  `mcp__ccd_session__spawn_task` chip per brief. The prompt is the filled
  brief; the title is its title; the summary says why now and repeats the
  Model line's model and effort. Briefs listed only in chat are not proposed.
- **Work in flight** (`brief` step 1): `mcp__ccd_session_mgmt__list_sessions`,
  plus this session's own `spawn_task` calls. Chips not yet started from other
  sessions or routines are invisible; say so.
- **Delegate a role** (P2): the Agent tool with `subagent_type`
  `agent-practices:ROLE` (explorer, implementer, light-reviewer, reviewer,
  critical-reviewer, critical-reviewer-strongest); pass `model` only to
  raise a reviewer to the implementer's tier (`tiers.json`), never to lower one.
- **Model check** (P2d): on a mismatch, send the parent "Switch me to MODEL at
  EFFORT: SESSION_ID" with `mcp__ccd_session_mgmt__send_message` and wait.
  The parent switches it with `mcp__ccd_session_mgmt__set_session_model` and
  `set_session_effort`, replies
  "Switched; continue with the brief." and does nothing else that turn. With
  no parent, ask me to switch with `/model` and `/effort` and stop.
- **Ask me, or wait on me** (P6b): questions and acceptance cards are chat
  text, numbered Q1, Q2 with options and a proposed default, answered in one
  reply ("Q1 A, Q2 B"); the closing Reply line
  ([question.md](../../templates/question.md)) is what the app's suggested
  reply can match. `AskUserQuestion` is not required. A turn that ends on
  my decision, acceptance, a closeout or a hand-off sends
  `PushNotification`: one line under 200 characters naming what waits on me. Everything a
  question depends on (commands, steps, a card) is in the chat text, never
  only in thinking or a tool result. Never re-ask an unchanged question.
- **Wait on CI or a merge** (P6b, `merge` step 4): run `wait-for` (the
  plugin's `bin/` is on the Bash PATH) with Bash `run_in_background` and a
  `timeout` above its deadline: 4200000 ms covers the defaults (45 and 60
  min); the tool's maximum is 7200000. Run it bare, without `; echo $?`:
  the task notification reports its exit code, and the Stop hook reads a
  landed auto-merge from it. Its exit wakes the session on every
  outcome; read the exit code and the last line of its output. Before a push
  or `gh pr merge --disable-auto` that makes your own wait stale, stop it
  with `TaskStop`; at closeout none of your own waits is still running. The
  app's Auto-fix monitor (`mcp__ccd_pr__set_monitor`) wakes it only on
  failures, conflicts and review comments, never on success, so it is not a
  wait. Never end a turn saying you are waiting with none of your own waits
  running.
