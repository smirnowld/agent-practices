# Shared local resources: on demand, claimed, last one out

A best practice for coding agents (any vendor) and the people running them. It applies whenever several agent
sessions on one machine share a long-running local resource: a database container, a VM or container engine
(Colima, Docker Desktop, a Lima VM), an emulator or simulator, a dev server on a fixed port, a local queue, a mock
service.

## The failure it prevents

An agent starts a resource for its task and never stops it. Nobody else knows whether it is still needed, so nobody
dares to stop it, and it runs idle for days, costing heat, memory and battery on a machine that also runs other sessions
and background jobs. The opposite failure is just as real: an agent tidies up and stops a resource that another
session's test run is using at that moment.

Typical cost: a container VM left running for days, holding one idle service.

## The practice

1. **Start on demand, not by habit.** Bring the resource up only when the task actually needs it (a test lane, a
   local run), not at session start and not "just in case".
2. **Claim what you use.** Starting or joining the resource records a claim for your checkout or session: who (a
   name another session can reach), where (checkout path, branch), since when. The claim lives in a place every
   session sharing the resource can see, outside version control (for example a directory in the git common
   directory, which all worktrees of a clone share).
3. **Release as soon as your work with it is done, and always at closeout.** Stopping is part of the closeout
   checklist, next to removing worktrees and branches, and ordered before anything that deletes the checkout the
   stop command needs.
4. **Last one out turns off the lights.** Releasing removes only your own claim. The resource actually stops only
   when no other claim remains and nothing is visibly using it (open connections, running containers). Otherwise it
   stays up and the command says who holds it; responsibility passes to them, and your handoff says so.
5. **Check before you affect anyone else.** Before stopping, restarting, recreating or reconfiguring a shared
   resource by any other means, look at the claims and at live usage. Something you cannot account for belongs to
   someone until shown otherwise.
6. **Communicate, don't guess.** Ask the claimant's session through whatever channel the tooling offers, or me,
   and leave the resource running while unsure. Only the claimant or I release someone else's
   claim. A claim is dropped automatically only when its claimant provably no longer exists (its checkout is gone).
7. **Never destroy data as a side effect of tidying.** Stopping keeps volumes, profiles and state; deleting them
   (`down -v`, `delete`, `reset`) needs my explicit say-so and no other claimant.
8. **Make the right thing one command each way.** Wrap start, stop and status in the repository's task runner
   (`make db-up`, `make db-down`, `make db-status`) and point every instruction, README and error hint at those
   commands, so no document still teaches the raw, claim-less command.

## Implementation notes

- **Claim before starting, under a lock.** Write the claim before starting anything, and take a lock around
  "write claim" in start and around "check claims, then stop" in stop. A stopper then either sees the new claim or
  finishes before the starter proceeds. A `mkdir` lock directory holding the holder's pid, taken over when that
  process is gone, is simple and portable; note that it is advisory.
- **Undo a failed start.** If the start fails or is interrupted (INT, TERM, HUP), remove the claim this run created,
  but keep a claim the checkout already held: its earlier work may still use the resource. Don't rely on shell
  `ERR` traps inside functions (bash does not inherit them without `set -E`); handle failures explicitly.
- **Write claims atomically** (temp file, then rename) and ignore malformed ones, so a half-written file is never
  mistaken for a stale claim.
- **Unique claim names.** Derive the file name from a checksum of the checkout path, and check the recorded path
  before removing, so two checkouts never release each other's claim.
- **Uncertainty means "in use".** If usage cannot be measured (the service is starting, unhealthy, a status command
  fails), leave the resource running and say why.
- **Stop the right thing.** Before stopping an engine or VM, confirm it is the one the commands actually talked to
  (the current Docker context, for example) and that it holds nothing else; a failed listing counts as "not empty".
- **Don't let a start recreate the shared instance.** Start with "don't recreate" / "no dependencies" flags when
  your checkout's configuration might differ from the one the running instance was created with.
- **Name the limits.** Users who hold no claim (older branches, hand-run commands, other clones, CI helper scripts)
  are protected only by the usage check at the moment of stopping. Say so in the docs rather than implying full
  protection.
- **Verify the stop path.** Test "leave running because someone else holds it" and "failed start releases the
  claim" with fakes, so a real shared resource is never stopped during testing.

## Checklist for an agent

- Does the task need the resource now? If not, don't start it.
- Start through the wrapper with the session's name, so others can reach you.
- When your work with it is done, and at closeout, run the stop command before removing the checkout.
- If it says others hold it: leave it, and mention it in the handoff.
- If you see a claim or usage you can't explain: ask its session or me; never force it.
- Never delete data or profiles without my explicit say-so.
- In a parallel round sharing one simulator or emulator, one owner builds and installs the app once; lanes only
  run the bundler or dev server against it and never build.

## Origin

A product repository, 2026-09: a container database shared by several agent
sessions on one laptop. The single-build rule: a mobile product repository,
2026-09, parallel lanes rebuilding the app on one simulator.
