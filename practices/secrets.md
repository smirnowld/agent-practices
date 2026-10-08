# Secrets

Detail for P10.

## Checking a key

Check a key in the shell and print only a status code or a match count.

## Why env files stay out of file tools

The reason for P10's env-file rule: once an agent opens a file with its file
read, write or edit tools, the harness can echo later edits to that file,
secrets included, into the transcript (observed; unverified against a primary
source). The shell check above keeps the value out of the agent's context.

Cross-project lesson.

## Secrets from a password manager

How agents and I use secrets without pasting them or approving a prompt per
lookup. Built on 1Password service accounts and its CLI, `op`; checked
2026-10-05 against [service accounts](https://www.1password.dev/service-accounts/get-started.md)
and, on 2026-10-08, [rate limits](https://www.1password.dev/service-accounts/rate-limits).

### Vaults

| Vault | Holds | Who reads it |
|---|---|---|
| `agents-shared` | Keys several projects' agents use | Every project's service account |
| `agents-<project>` | Keys this project's agents use, and keys they generate | That project's service account |
| `<project>-ops` | Production, signing, backup and recovery keys | Only me, through the desktop app |

- One service account per project: read on its vault and `agents-shared`.
  Give it write on its own vault too if agents should later store keys they
  generate; no tool does that yet, so for now an agent asks me to. A
  service account's vaults and permissions can't be changed after it is
  created; to change them, create a new one and revoke the old.
- A service account can't use Personal or Private vaults.
- Each key lives in one vault. An operator template may point at an
  `agents-*` item rather than keep a copy.
- Agents archive items, never delete them. Deleting is mine.
- Never in an agent vault: production keys, signing keys, backup private
  keys, recovery codes, anything that can't be revoked on its own. Where a
  service can't scope a key (an account-wide API key), give agents their own
  key so it can be revoked without breaking mine.

### Token in the Keychain

On macOS the service account's token lives in the Keychain (on Linux, see
Token on Linux). `-T /usr/bin/security`
lets any of my processes read it without a prompt through that tool, agents
included; the vault scope, not the Keychain, is the boundary.

Copy the token with the 1Password app's copy button (it marks the copy as
concealed for clipboard managers and clears it later; a browser page does
neither), then store it from the clipboard and clear the clipboard. `-U`
replaces an existing item unconditionally, so the guard refuses a clipboard
that holds no token:

```sh
case "$(pbpaste)" in ops_*) security add-generic-password -U -s op-agent-<project> -a "$USER" -T /usr/bin/security -w "$(pbpaste)" && pbcopy </dev/null ;; *) echo "the clipboard holds no token" >&2 ;; esac
```

Not `-w` last: its prompt reads through `getpass(3)`, which keeps only the
first 128 characters, and a token is several times longer, so `op` later
fails to decode it. Check the stored length and prefix, never the value:

```sh
security find-generic-password -s op-agent-<project> -w | awk '{print length($0), substr($0,1,4)}'
```

The token is in argv for the moment `security` runs; on a single-user Mac
that is the accepted trade-off, since `-T /usr/bin/security` already lets
any of my processes read it. Rotate with Rotate Token on the service account
(1Password.com, Developer, Service accounts), letting the old token expire
now or after a grace period, and store the new one the same way. Revoke
Token there revokes the current token, so it is not part of a rotation.

### Token on Linux

The token lives in `~/.config/op/agent-<project>.token`, with `<project>`
derived as on macOS (`--project NAME` overrides). `with-secrets` refuses the
file unless it is a regular file (not a symlink), owned by the user running
it, mode 600 or 400, and not empty; a trailing newline is trimmed. As with the
Keychain, anyone running as that user can read it, so the vault scope is the
boundary.

Create it so the token never reaches argv or the screen. In bash or zsh
(`read -s` is not POSIX sh), paste at the prompt; the guard refuses a value
that is not a token:

```sh
mkdir -p -m 700 ~/.config/op && (umask 077; IFS= read -rs t && case $t in ops_*) printf '%s\n' "$t" > ~/.config/op/agent-<project>.token ;; *) echo "not a token" >&2 ;; esac; unset t)
```

Or pipe it from the Mac: copy with the 1Password app's copy button, run the
line below, then clear the clipboard (`pbcopy </dev/null`):

```sh
pbpaste | ssh HOST 'mkdir -p -m 700 ~/.config/op && umask 077 && cat > ~/.config/op/agent-<project>.token'
```

Check the length and prefix, and the owner and mode, never the value (GNU
`stat`):

```sh
awk '{print length($0), substr($0,1,4)}' ~/.config/op/agent-<project>.token
stat -c '%U %a' ~/.config/op/agent-<project>.token
```

Rotate as in the Keychain section, then rewrite the file the same way.

### Running with secrets

- `with-secrets -- CMD` (agent mode) reads the token (Keychain on macOS, token
  file on Linux) and
  runs `CMD` under `op run` with the template's `op://` references. The token
  is kept out of `CMD`'s environment (hygiene for logs, not a boundary).
  `op run` masks values in output. In both modes, `op://` references in the
  caller's environment are refused, since `op run` would resolve them too.
  `--template FILE` picks a template; a brief's `## Secrets` names it.
- `with-secrets --operator -- CMD` is the same for me, through the desktop
  app, any vault. Agents never run it.
- Templates are committed, hold one `NAME=op://VAULT/ITEM/FIELD` per line and
  nothing else; plain values are refused. In agent mode the vault must be an
  `agents-*` name or an ID; agent templates use IDs for vault and item (see
  Quotas).
- `push-secrets MANIFEST` copies values from 1Password into GitHub
  environment or repository secrets and Render environment groups. Values go
  through pipes, never argv or the screen. `--dry-run` lists what it would
  push, and the whole manifest is checked before the first push. Operator
  only. `gh` may trim a trailing newline from a value.
- Install both with `make install-bin` from this repository's main checkout
  (links from a worktree dangle once it is removed).

### Quotas

Per the [rate limits](https://www.1password.dev/service-accounts/rate-limits),
service-account requests per day for the whole account are capped at 1,000 on
Families, 5,000 on Teams and 50,000 on Business; reads per hour per token at
1,000 on Families and Teams and 10,000 on Business. Reading a reference by
name costs 3 requests; by vault and item ID, 1
([multiple requests](https://www.1password.dev/service-accounts/use-with-1password-cli.md)).
So agent templates use IDs. Desktop-app sign-in doesn't count against these quotas. Check usage with
`op service-account ratelimit`.

### Trade-offs

- An agent running with a template sees those values in its process. The
  brief's `## Secrets` limits which; the vault limits the worst case.
- Anyone using my unlocked Mac can use the token. Lock the screen; revoke the
  token if the Mac is lost.
- Desktop-app authorisation covers a terminal session and its sub-shells
  for 10 minutes after last use, up to 12 hours
  ([app integration security](https://www.1password.dev/cli/app-integration-security.md)).
  An agent started from a terminal where I just ran `op` could use my
  authorisation unprompted, so I run operator commands in a terminal no
  agent runs from.
- Which templates a brief allows is not enforced by a hook yet. The
  service account's vaults are the hard limit; the template and brief
  narrow use by convention.

Lesson from a product repo and a server-config repo.
