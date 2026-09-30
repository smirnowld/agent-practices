# Codex session bindings

The policy and skills name actions; this is the tool that does each one in
Codex. Not printed at start: the user-level `AGENTS.md` points here
([README.md](README.md#what-works), Policy). Items not in the README are
unverified (2026-09-30).

- **Propose a session** (P2c, `brief` step 6): no tool checked. Send each
  brief in chat as one fenced block, ready to paste into a new session, and
  say in the report that no session was created.
- **Work in flight** (`brief` step 1): open PRs and pushed branches only; no
  tool for other Codex sessions or unstarted proposals is checked. Say so.
- **Delegate a role** (P2): spawn the custom agent by name (`explorer`,
  `implementer`, `reviewer`, `critical-reviewer`), installed as copies in
  `~/.codex/agents/` or the project's `.codex/agents/`.
- **Model check** (P2d): no tool to switch a running session is checked; on
  a mismatch, ask me to switch the model and effort and stop.
- **Ask me, or wait on me** (P6b): the structured question tool where the
  surface exposes one; otherwise the question in chat. No agent-callable
  notification is checked; end with the card or closeout in chat, followed
  by the closeout's questions, and act on the answers next turn.
