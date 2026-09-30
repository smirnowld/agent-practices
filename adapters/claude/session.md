# Claude Code session bindings

The policy and skills name actions; this is the tool that does each one in
Claude Code. Printed at every session start. Evidence and dates:
[README.md](README.md#session-rules-specific-to-this-agent).

A tool listed only by name is deferred: load it with ToolSearch
`select:NAME` first. Chat is the fallback only when the tool is absent, and
the report says so.

- **Propose a session** (P2c, `brief` step 6, closeout, routines): one
  `mcp__ccd_session__spawn_task` chip per brief. The prompt is the filled
  brief; the title is its title; the summary says why now and repeats the
  Model line's model and effort. Briefs listed only in chat are not proposed.
- **Work in flight** (`brief` step 1): `mcp__ccd_session_mgmt__list_sessions`,
  plus this session's own `spawn_task` calls. Chips not yet started from other
  sessions or routines are invisible; say so.
- **Delegate a role** (P2): the Agent tool with `subagent_type`
  `agent-practices:ROLE` (explorer, implementer, reviewer, critical-reviewer).
- **Model check** (P2d): on a mismatch, send the parent "Switch me to MODEL at
  EFFORT: SESSION_ID" and wait. The parent switches it with
  `mcp__ccd_session_mgmt__set_session_model` and `set_session_effort`, replies
  "Switched; continue with the brief." and does nothing else that turn. With
  no parent, ask me to switch with `/model` and `/effort` and stop.
- **Ask me, or wait on me** (P6b): a decision or acceptance goes through
  `AskUserQuestion` after the card is shown. A closeout or hand-off to me ends
  with `PushNotification`, one line under 200 characters.
