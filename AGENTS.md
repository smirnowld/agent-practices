# Working on this repository

Repo type: tooling (P19). Rules for agents editing agent-practices itself. The policy for other projects
is in [policy/AGENTS.md](policy/AGENTS.md).

- Place content by the table in [README.md](README.md#what-goes-where). One
  fact lives in one file; others link to it.
- Keep `policy/` short: every line costs every session. Move explanation into
  `practices/` and link.
- No agent-vendor names, file formats, model IDs or config keys outside
  `adapters/`. Exceptions: `.claude-plugin/`, which the vendor requires at the
  root, and `scripts/build-adapters.py`, which writes the adapters. Hosting
  and tooling services (GitHub, Dependabot) may be named in policy, practices
  and templates where the rule depends on them.
- A policy change is a pull request that states which sessions it affects and
  is reviewed before merge. On merge the `sync-policy` workflow opens or
  updates one sync PR per listed project (`scripts/push-policy-sync.sh`); if
  it failed, rerun it (`gh workflow run sync-policy`). After changing `roles/` or a `tiers.json`, run
  `python3 scripts/build-adapters.py`; never edit generated agents.
- Run `make check` before opening a pull request; CI runs the same target.
- Adapter facts cite the vendor doc URL and the date checked. Mark anything not
  confirmed against the official page as unverified.
- Practices record where a lesson came from by kind of project and date, not
  by name.

## Public and portable

This repository is public so anyone can borrow or fork it.

- Never name the author, their organisation or their projects, and never link
  their repositories, PRs or machines. Say "a product repo", "a server-config
  repo". First person ("I", "me") for the author is fine.
- The author's preferences stay in policy as written; a fork changes them.
- No ephemeral documents: analyses, trial logs, briefs and session notes live
  outside this repository (P17). Only their lasting conclusions land here,
  anonymised.
- Before merging, search the diff for names that break this rule.

## Diagrams

Mermaid blocks, including placeholders in templates, must parse: no `<...>`
inside diagrams (use CAPS placeholders). Check each changed block with the
Mermaid parser before merging.
