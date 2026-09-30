# Codex session bindings

The policy and skills name actions; this is the tool that does each one in
Codex. Not printed at start: the user-level `AGENTS.md` points here
([README.md](README.md#what-works), Policy). Items not in the README are
unverified (2026-09-30).

- **Propose a session** (P2c, `brief` step 6, closeout, routines): present
  each complete brief in chat with a stable label, title, model, effort,
  size and dependencies. When supported, add one `:codex-followup` action
  labelled "Approve and start LABEL"; its prompt explicitly requests a new
  chat from that labelled brief with the displayed model and effort. This
  proposes work; it does not create a chat. Requesting briefs or approving
  their contents alone does not authorize starting them. Without follow-up
  actions, offer the same explicit start request in chat.
- **Start approved sessions:** only on my explicit request to start selected
  briefs, use `mcp__codex_app__list_projects` to resolve the project and
  `mcp__codex_app__create_thread` with the complete approved brief as its
  prompt and its title. Set `model` and `thinking` only when I explicitly
  approved those settings; otherwise omit them and retain the brief's P2d
  check. Use the local project environment unless I explicitly request a
  worktree. Recheck work in flight and dependencies immediately before each
  creation. "Start all" covers the selected independent briefs, not work
  whose prerequisites are still pending; keep dependent briefs pending until
  those prerequisites are satisfied on a later continuation (no automatic
  wakeup is scheduled). Resolve the exact complete approved brief; ask if
  it is unavailable or ambiguous. Record each returned `threadId` or
  pending `clientThreadId` against its brief, report it with the app's
  `::created-thread` directive when supported (otherwise the identifier in
  chat), and do not create the same brief again. For
  an ambiguous creation outcome, inspect chats before retrying; if it cannot
  be resolved, ask me rather than risk a duplicate. After creation, use one
  bounded `mcp__codex_app__wait_threads` snapshot with the returned
  `threadId` and `hostId`; never pass a pending `clientThreadId`. Creation
  does not authorize follow-up messages to the new chat. Creation starts work;
  there is no draft or paused-start option in this tool's exposed schema.
  Discover these tools if deferred; if unavailable, send a fenced pasteable
  brief and say no chat was created. Full syntax and evidence:
  [README.md](README.md#proposing-and-starting-sessions).
- **Work in flight** (`brief` step 1): open PRs and pushed branches, plus
  `mcp__codex_app__list_threads` when available; inspect relevant chats with
  `mcp__codex_app__read_thread` as needed. Include this chat's pending briefs
  and creation results. Unstarted proposals from other chats are not a
  dedicated inventory, and listings may be incomplete; say what could not
  be checked. Discover deferred tools before falling back.
- **Delegate a role** (P2): spawn the custom agent by name (`explorer`,
  `implementer`, `reviewer`, `critical-reviewer`), installed as copies in
  `~/.codex/agents/` or the project's `.codex/agents/`.
- **Model check** (P2d): no tool to switch a running session is checked; on
  a mismatch, ask me to switch the model and effort and stop.
- **Ask me, or wait on me** (P6b): the structured question tool where the
  surface exposes one; otherwise the question in chat. No agent-callable
  notification is checked; end with the card or closeout in chat, followed
  by the closeout's questions, and act on the answers next turn.
