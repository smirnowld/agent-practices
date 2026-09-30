# Codex session bindings

The policy and skills name actions; this is the tool that does each one in
Codex. Not printed at start yet; the user-level `AGENTS.md` points here.
Evidence and dates: [README.md](README.md).

- **Propose a session** (P2c, `brief` step 6): no tool checked. Send each
  brief in chat as one fenced block, ready to paste into a new session, and
  say in the report that no session was created.
- **Work in flight** (`brief` step 1): open PRs and pushed branches only;
  other Codex sessions and unstarted proposals are not visible. Say so.
- **Delegate a role** (P2): spawn the custom agent by name (`explorer`,
  `implementer`, `reviewer`, `critical-reviewer`), installed as copies in
  `~/.codex/agents/`.
- **Model check** (P2d): no tool switches a running session; on a mismatch,
  ask me to switch the model and effort and stop.
- **Ask me, or wait on me** (P6b): the structured question tool where the
  surface exposes one; otherwise the question in chat. No agent-callable
  notification is checked; end with the card or closeout in chat.
