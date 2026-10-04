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
  prompt and its title. Every brief launch must pass both `model` and
  `thinking`, exactly matching its approved Model line. A Model line in the
  prompt does not configure the chat. An explicit request to start selected
  briefs also approves their displayed model and effort: "start B1", "kick it
  off" or "start all" is sufficient when the selected briefs and their
  settings are unambiguous. Do not ask for separate settings confirmation;
  ask if the selected brief or its model or effort is missing or ambiguous.
  Never omit either field, use the configured default, substitute a
  model, or dispatch first and rely on P2d to catch a mismatch. If the exact
  model/effort pair is unavailable or rejected, keep the brief pending and
  report the blocker; do not retry with defaults. Keep P2d as a second check.
  Use the local project environment unless I explicitly request a
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
- **Ask me, or wait on me** (P6b): check the active mode and exposed tool
  contract. Use `request_user_input` only where the mode permits it (the
  observed desktop contract restricts it to Plan mode); use
  `request_user_input_async` for clarification during normal work when
  exposed and permitted. Follow the tool's allowed scope: a clarification
  tool is not an approval mechanism. If no permitted structured tool exists
  for the question, ask in chat. Call the tool directly from the parent
  chat; delegated agents return questions to the parent to present.
  `accepted: true` confirms submission, not display or an answer. Continue
  only independent work while a required answer is pending. For an
  asynchronous question that needs an answer, keep the turn active: after
  independent work, use an exposed interruptible wait (such as
  `clock.sleep`) in intervals of at most 60 seconds until an answer arrives
  or I ask to stop. Do not finish just because submission was accepted.
  Tell me I can answer through the card; a clear typed reply is also an
  answer when it unambiguously matches the pending question. If the card
  disappears after that reply, do not treat its disappearance as withdrawal
  of my answer. Clarify ambiguous replies before drawing conclusions.
  If waiting is unavailable or the turn must end with an answer pending,
  include the complete question, all options and the
  recommended choice in the final chat message as well as any structured
  prompt, so the question remains answerable if the card is missing. Never
  treat silence, elapsed time or a preselected option as an answer or
  approval. No agent-callable notification is checked; send the card or
  closeout and questions in chat, and act on actual answers when they arrive.
  Evidence and limits: [README.md](README.md#structured-questions).
