# Question: <the question in one plain sentence>

<!-- One question for me, in chat (P6) or in the register (P11). I should be
able to answer it in under a minute, on my phone, without asking anything
back. Write it for the person deciding, not for the code:

- Lead with the question. No preamble, no history of how it came up.
- Plain words. Name a library, file or internal term only when the choice is
  about it; otherwise describe what it does.
- Describe options by their effect: what users see, what it costs, what is
  hard to undo later, what it blocks.
- Give a proposed default and the reason in one line.
- Make it answerable in one reply ("A", "B", or a short sentence). If you
  cannot write the options yet, you are not ready to ask: find out more first.
- Ask only what is mine to decide. Implementation choices behind it are yours:
  decide and log them (P6).
- In a batch, number the questions (Q1, Q2; reuse a register item's ID) so
  one reply answers all: "Q1 A, Q2 B".
- Technical detail only when it changes the answer, in the Technical note.
  Everything else goes behind a link.

Before: "The session middleware currently uses a Redis-backed store with a
24h TTL, but the refresh-token rotation in the auth module can race with it
when... should we switch to JWT or keep the store and add locking?"
After: "How long should people stay signed in on a device they don't use?"
with options by effect (A, proposed, 30 days: fewer sign-ins, a lost phone
stays signed in longer; B, 1 day: safer, people sign in again most days). The
store-versus-token choice is the agent's to decide and log. -->

**Why it matters:** <what changes for users, cost, risk or timeline; one or
two lines>

**Options:**
- **A (proposed):** <what happens> — <the trade-off, and why we propose it>
- **B:** <what happens> — <the trade-off>

**Until answered:** <we go with A | this blocks WHAT>

**Technical note:** <only if it changes the answer; otherwise delete this
line>

**Context:** <P18 link to the PR, doc or issue, if the reader might want more>
