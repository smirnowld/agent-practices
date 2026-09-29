# Context efficiency

How to keep sessions cheap without losing decisions or skipping proof. Backs
P14; compaction thresholds themselves live in the adapters.

## Where context goes

- **Long same-task history.** Every call re-sends the whole transcript. A
  session left to run until the model's full window is nearly exhausted pays
  for that history on every step; one compaction at a stable point usually
  cuts per-call input several-fold.
- **Fixed startup load.** Instructions, tool schemas and memory load on every
  call. Duplicated or reference-only material in instruction files is pure
  cost: keep instruction files to rules, move facts into docs that are read
  when needed.
- **Large tool output.** Full logs, file dumps and repeated status polls.

## Reading code

- Locate once (search or a symbol index), then read the section whole in one
  call: the function or block and the lines it needs around it. Do not page
  through one file in successive windows; each window is another response
  carrying the whole context.
- Do not re-read what is still in context and unchanged; re-read after the
  file changed or after a compaction.
- A parent session's question over more than about three files, or over
  history, goes to an explorer with the question and a bound, unless the
  parent already holds the context (P2b); the explorer returns the conclusion
  with `path:line`, not the files.
- Ask the tool for the result, not the file: a build error's message, a test's
  failing lines, one grep with the pattern, not a listing to scan.

Evidence: five product-repo sessions measured in 2026-09, each expected to be
one slice, made 125 to 165 read-style shell calls, mostly windows over the
same files, at about 120k context per call.

## Rules of thumb

- Keep full logs on disk; report the result, failing lines and log path.
- Set the compaction point well below the model's window, in the adapter.
  Agents with a heavier startup load need a higher point.
- Never shrink the context window to force compaction; move the compaction
  point instead.
- Compact at a checkpoint, never mid-step, after a progress update
  (`templates/progress-update.md`) so the summary keeps goal, decisions, owned
  files, proof status and next step.
- A new task gets a new session with a brief, not a fork: a fork inherits the
  history.
- Delegated agents get a brief, not the transcript, and return conclusions.
- When a late tweak meets a large context, hand it to a fresh small session.
- Summarise tool output, except exact diffs and visual renders when the task
  needs them.
- Add machinery (for example re-injecting state after compaction) only when a
  measured case shows compaction losing a decision.

## Measuring a change

A threshold or instruction change is kept only if it saves context without
costing quality. Compare at least three similar slices before and after.
Take each slice's model, responses, input / cached / output tokens,
compaction count and elapsed time from the usage collector's per-session
data; judge proof completed and rework caused by lost context from the
sessions themselves. Never record usage figures by hand, in the repo or
elsewhere; keep only the conclusion here.
