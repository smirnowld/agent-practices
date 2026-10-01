# Codex adapter

Checked 2026-09-30 against the official OpenAI Codex documentation and a
local Codex build. Local compatibility observations do not establish behavior
on every Codex host or cloud environment.

## What works

- **Policy:** Codex reads `AGENTS.md`. Install a pointer to this
  repository's policy and to [session.md](session.md) at
  `~/.codex/AGENTS.md` for your user, or sync it into a project's `AGENTS.md`
  with `scripts/sync-policy.sh`.
- **Skills:** Codex scans `~/.agents/skills` (user) and `.agents/skills` at
  repository/current-directory levels. Symlinked skill folders are followed.
  `~/.codex/skills` is not listed as a skill discovery path. Each `SKILL.md`
  needs YAML frontmatter with `name` and `description`; the folders in this
  repository meet that requirement and can be used as-is. For a user install
  from the repository root, run:

  ```sh
  mkdir -p ~/.agents/skills
  ln -s "$PWD"/skills/* ~/.agents/skills/
  ```

  Official guide: https://developers.openai.com/codex/skills.
- **Roles:** Generated standalone TOML files use the custom-agent schema.
  Install the files under `~/.codex/agents/` for personal agents or
  `.codex/agents/` for project-scoped agents. Copy them: symlinked role
  files did not load in the build tested (see
  [Role files are copies](#role-files-are-copies)). Each file requires `name`,
  `description`, and `developer_instructions`; `model`,
  `model_reasoning_effort`, and `sandbox_mode` are supported config keys.
  Official schema and locations:
  https://learn.chatgpt.com/docs/agent-configuration/subagents.
- **Effort:** `model_reasoning_effort` accepts reasoning levels supported by
  the selected model; `low`, `medium`, `high`, and `xhigh` are documented
  Codex values. `agents.default_subagent_reasoning_effort` sets the default
  for spawned agents:
  https://learn.chatgpt.com/docs/config-file/config-reference.
- **Compaction:** `model_auto_compact_token_limit` sets the token threshold
  for automatic history compaction:
  https://learn.chatgpt.com/docs/config-file/config-reference.
- **Hooks:** Codex documents `SessionStart` and other lifecycle hooks. They
  can add developer context at session start. User hooks can live in
  `~/.codex/hooks.json`; non-managed hooks require review and trust before
  they run. Project hooks load only for trusted projects.
  https://learn.chatgpt.com/docs/hooks (checked 2026-09-30).
- **Plugins:** Codex plugins can bundle skills and lifecycle hooks. This could
  distribute this repository's skills and session-start policy loader as one
  installable package, but local marketplace plugins run from an installed
  cache copy; changing the source calls for updating the plugin and restarting
  the desktop app. This does not give the live checkout automatic updates.
  https://developers.openai.com/plugins/build/plugins (checked 2026-09-30).
- **Scheduled tasks:** Codex desktop scheduled tasks can replace manually
  started recurring routines. Local project tasks require the computer to
  remain on with the app running; CLI and IDE do not provide the scheduling
  interface. https://developers.openai.com/codex/app/automations.

## Proposing and starting sessions

The workflow binding lives in [session.md](session.md). Proposals stay in the
originating chat until an explicit start request, so the user can review,
revise and start them individually. Approving a brief's contents does not
start it. A request such as "Approve and start B1 using its displayed model
and effort" authorizes creation and those settings; "start all using each
brief's displayed model and effort" may start independent briefs, while
dependent briefs remain pending. Pending does
not schedule a future run: check prerequisites when this chat is next asked
to continue. Briefs are not committed to the repository (P17).

The Codex desktop instructions exposed on 2026-09-30 support an inline
follow-up action in a Markdown list item:

```text
- :codex-followup[Approve and start B1]{prompt="Create a new Codex chat for brief B1 above using gpt-6-luna at high effort. Pass the complete brief unchanged, after checking work in flight and dependencies. Start only B1."}
```

This example assumes B1 names that model and effort. Each real action names
its own brief and displayed settings. Escape double quotes in the prompt.
The action requests work in the originating chat; the agent then calls
`create_thread`. Resolve the complete approved brief before creating; if it
is unavailable or the request is ambiguous, ask rather than reconstruct it.
Follow-up rendering, click behavior and persistence have not been tested;
the syntax is supplied by the desktop instructions, unverified against
official documentation. A typed explicit start request is the fallback.

The same desktop instructions require a creation result on its own line in
the final response, using the identifier actually returned:

```text
::created-thread{threadId="RETURNED_THREAD_ID"}
```

For pending worktree setup, use `::created-thread{clientThreadId="RETURNED_CLIENT_THREAD_ID"}`
instead. This reports a creation result; it is not a proposal or start action.
Its rendering is also untested and unverified against official documentation;
on surfaces without this directive, report the returned identifier in chat.

The `codex-app-tools` tool definitions exposed in a desktop session on
2026-09-30 include:

- `list_projects`: project identifiers, hosts and repository eligibility.
- `create_thread`: a complete prompt, title, project or projectless target,
  local or explicitly requested worktree environment, and optional `model`
  and `thinking`. The tool requires an explicit request for a new chat;
  model overrides require an explicit request for that model. A start action
  naming the displayed settings supplies that request. For brief launches,
  both fields are mandatory in the call and must match the approved Model
  line. Putting the settings only in the prompt leaves them unconfigured.
  A start request that does not explicitly approve the settings needs one
  clarification before dispatch, not a launch with omitted fields. If the
  pair is unavailable or rejected, keep the brief pending rather than retry
  with defaults. Creation dispatches
  work asynchronously; there is no exposed draft or paused-start parameter.
- `list_threads` and `read_thread`: chat status and summaries for checking
  work in flight. Listings are best effort, not a complete registry of
  unstarted proposals. Track this chat's pending briefs and creation results
  separately, including a `clientThreadId` while worktree setup is pending.
- `wait_threads`: a bounded progress snapshot after creation. Use the
  returned `threadId` and `hostId`, never a pending `clientThreadId`; report
  pending setup without creating a replacement. A created chat is owned by
  the user; creation does not authorize later follow-up messages to it.

These are exposed tool contracts, not end-to-end compatibility tests, and
are unverified against official documentation for these specific tools. No
test chat was created. Do not assume availability in CLI, IDE or cloud
sessions; discover deferred tools and use the chat fallback when absent.
The official app-server distinguishes creating a thread (`thread/start`)
from starting generation (`turn/start`), but it does not establish a dormant
mode for the desktop `create_thread` tool. A custom integration could use
that separation; this adapter uses the available desktop tools instead.
https://learn.chatgpt.com/docs/app-server (checked 2026-09-30).

### Launch checks

Before calling `create_thread`, compare the approved brief, the start request
and the actual tool arguments. For a brief naming `gpt-6-luna` at high:

| Case | Required result |
|---|---|
| Explicit request to start with the displayed model and effort | Pass `model: "gpt-6-luna"` and `thinking: "high"` together with the complete brief. |
| Model and effort appear only in the prompt | Do not dispatch; fill both tool fields after settings approval. |
| Request says only "start B1" or "start all" | Obtain an explicit settings-approved start request before dispatching. |
| Either setting differs from the approved Model line | Do not dispatch; resolve the discrepancy first. |
| Exact pair unsupported or creation rejects it | Report the blocker and retain the brief; no default or more expensive retry. |

Report the settings actually passed alongside the returned chat identifier.
Do not claim the running model was verified unless returned metadata or
subsequent inspection establishes it. P2d remains a second check; it does not
replace configuring the launch.

Observed 2026-10-01 in a product repo: three brief launches named a model and
effort in their prompts but omitted both creation arguments. The user reported
unexpected Astra usage. The omitted arguments are confirmed; which configured
default selected Astra and the resulting spend were not independently
verified. These launch checks replace the adapter's previous instruction to
omit unapproved settings and rely on P2d. They use the desktop tool contract
exposed on 2026-10-01; end-to-end enforcement is still unverified against
official documentation. The app-server's explicit model configuration is
documented at https://learn.chatgpt.com/docs/app-server (checked 2026-10-01),
but that API does not establish this desktop tool's behavior.

## Models

The tier map uses the documented model IDs: `gpt-6-luna` (fast), `gpt-6.1-sol`
(standard and strong), and `gpt-6-astra` (strongest). Model guidance for Luna
and Astra:
https://developers.openai.com/api/docs/guides/latest-model (checked
2026-09-27). The Sol pin was updated to GPT-6.1 Sol against its model page:
https://developers.openai.com/api/docs/models/gpt-6.1-sol (checked
2026-09-30).

No Codex `auto latest` setting or moving GPT-6 alias is documented in the
Codex config reference or GPT-6 model guidance checked on 2026-09-27. The
adapter therefore pins explicit model IDs and should be rechecked as OpenAI
releases models. Codex accepts model names in its `model` setting:
https://learn.chatgpt.com/docs/config-file/config-reference (checked
2026-09-27).

Codex documents an explicit per-spawn model and effort choice, but a custom
agent file's `model` and `model_reasoning_effort` take precedence over those
choices. The generated role files set both, so per the docs an explicit spawn
override cannot lower a pinned critical-reviewer role to the standard tier described
in `practices/model-sizing.md`; use the pinned tier until the role-generation
design changes. https://learn.chatgpt.com/docs/agent-configuration/subagents
(checked 2026-09-30). Live per-spawn override behavior for a custom role is
unverified.

## Role files are copies

The documented custom-agent location and schema do not state whether role
files there may be symlinks:
https://learn.chatgpt.com/docs/agent-configuration/subagents (checked
2026-09-30). With Codex CLI `0.155.0-alpha.2.6`, all four generated role files
linked individually into `~/.codex/agents` failed to spawn: the loader logged
`failed to apply role to config: Too many levels of symbolic links` (likely
a loader that refuses to follow symlinks; inferred, not documented), then
returned
`agent type is currently not available`. The same files copied into
`~/.codex/agents` spawned from `codex exec` (observed 2026-09-30, same
build). Copies go stale:
recopy them after `scripts/build-adapters.py` changes a role. Linked skill
folders did load, including `brief`, and resolved repository-relative paths
from the checkout.

## Keeping the local install current

Keep the short `~/.codex/AGENTS.md` pointer as the global bootstrap. Codex
reads that file at session start, then project `AGENTS.md` files in root-to-leaf
order; it does not automatically read changes made to those files mid-session.
https://learn.chatgpt.com/docs/agent-configuration/agents-md (checked
2026-09-30). Prefer a user-level `SessionStart` hook over a Codex plugin for a
future local updater: a hook can read the checked-out source at startup,
whereas a locally installed plugin uses a cached copy. A hook alone does not
fetch new commits or link new skill folders. Automatic updates need a guarded
fast-forward of the checkout, idempotent reconciliation of skill symlinks and
a recopy of changed role files, with a clear outcome when the checkout is
dirty or the fetch fails. That updater is
not installed yet; its trust setup, checkout safety, and failure handling
warrant a separate brief. Hook behavior and plugin caching:
https://learn.chatgpt.com/docs/hooks and
https://developers.openai.com/plugins/build/plugins (checked 2026-09-30).

## Codex usability notes for the neutral source

- Neutral roles and skills refer to `parent session`, `delegated agent`, and
  capability tiers. These map cleanly to Codex subagents and spawned-agent
  settings; terms such as “routine” and “routine entry” mean scheduled tasks
  and are not Codex configuration terms.
- `skills/docs-drift-check/SKILL.md`, `skills/triage/SKILL.md`,
  `skills/issue-review/SKILL.md` and `skills/project-setup/SKILL.md` (audit
  mode) describe recurring routines. Codex scheduled tasks can run these
  workflows, but setup of their schedule, project list, and notification behavior remains a
  manual task unless one is explicitly created.
- P6b can use a structured question tool when the active Codex surface exposes
  one. The app-server documents an experimental `tool/requestUserInput` prompt;
  a desktop session exposed structured question tools, with availability
  depending on mode (observed 2026-09-30). The desktop app documents separate question and
  turn-completion notification settings and an Activity view for chats waiting
  for a response. These are user-controlled settings, not a confirmed
  agent-callable notification for a specific closeout. Use the structured tool
  when available and the closeout or question in chat; whether the desktop's
  asynchronous question tool causes a waiting badge and notification at turn
  end is unverified. https://learn.chatgpt.com/docs/app-server and
  https://learn.chatgpt.com/docs/notifications (checked 2026-09-30).
- `policy/AGENTS.md` says in P15 that closeouts name agents and models. Codex
  can provide those names; this is an instruction convention, not a Codex
  feature or schema field.

## Not verified

- End-to-end approved-brief creation, follow-up action rendering and click
  behavior, and persistence of those actions across app surfaces. See
  [Proposing and starting sessions](#proposing-and-starting-sessions).
- Role files: copies were tried only from `codex exec` and in
  `~/.codex/agents`, symlinks only on CLI `0.155.0-alpha.2.6`. Copies in the
  desktop app or project-scoped `.codex/agents/`, and symlinks on later
  builds, are untested.
- Whether a desktop turn ending after an asynchronous structured question
  displays the waiting state and sends the question notification.
- Cloud availability of locally installed skills, role files, hooks, and
  plugins depends on the specific runtime and environment; do not assume a
  local installation is present in a cloud task.
