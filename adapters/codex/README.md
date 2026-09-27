# Codex adapter

Checked 2026-09-27 against the official OpenAI Codex documentation.

## What works

- **Policy:** Codex reads `AGENTS.md`. Install this repository's policy at
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
  `.codex/agents/` for project-scoped agents. Each file requires `name`,
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
  can load policy context instead of manually maintaining a user-level
  `AGENTS.md`; project hook files live alongside trusted project config.
  https://developers.openai.com/codex/hooks.
- **Plugins:** Codex plugins can bundle skills and lifecycle hooks. This could
  distribute this repository's skills and session-start policy loader as one
  installable package; hook scripts must be available in the execution
  environment and users must review/trust hook definitions.
  https://developers.openai.com/plugins/concepts/plugins
  https://developers.openai.com/plugins/build/plugins.
- **Scheduled tasks:** Codex desktop scheduled tasks can replace manually
  started recurring routines. Local project tasks require the computer to
  remain on with the app running; CLI and IDE do not provide the scheduling
  interface. https://developers.openai.com/codex/app/automations.

## Models

The tier map uses the documented model IDs: `gpt-6-luna` (fast), `gpt-6-sol`
(standard and strong), and `gpt-6-astra` (strongest). The GPT-6 model guidance
documents all three names and describes their relative capabilities:
https://developers.openai.com/api/docs/guides/latest-model (checked
2026-09-27).

No Codex `auto latest` setting or moving GPT-6 alias is documented in the
Codex config reference or GPT-6 model guidance checked on 2026-09-27. The
adapter therefore pins explicit model IDs and should be rechecked as OpenAI
releases models. Codex accepts model names in its `model` setting:
https://learn.chatgpt.com/docs/config-file/config-reference (checked
2026-09-27).

## Codex usability notes for the neutral source

- Neutral roles and skills refer to `parent session`, `delegated agent`, and
  capability tiers. These map cleanly to Codex subagents and spawned-agent
  settings; terms such as “routine” and “routine entry” mean scheduled tasks
  and are not Codex configuration terms.
- `skills/docs-drift-check/SKILL.md` and `skills/triage/SKILL.md` describe
  recurring routines. Codex scheduled tasks can run these workflows, but
  setup of their schedule, project list, and notification behavior remains a
  manual task unless one is explicitly created.
- `policy/AGENTS.md` says in P15 that closeouts name agents and models. Codex
  can provide those names; this is an instruction convention, not a Codex
  feature or schema field.

## Not verified

- This documentation review verifies documented locations and format, but
  does not launch Codex to confirm these generated agent files are discovered
  in a live user or project installation.
- Cloud availability of locally installed skills, role files, hooks, and
  plugins depends on the specific runtime and environment; do not assume a
  local installation is present in a cloud task.
