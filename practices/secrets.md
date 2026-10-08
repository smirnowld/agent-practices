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

## Secret items

How secrets are named and kept in any password manager or secret store.

- Name items in lowercase kebab-case, project first:
  `PROJECT-SERVICE-WHAT[-ENV]`, for example `PROJECT-stripe-api-key-staging`.
- A key issued separately for agents is its own key with its own name,
  suffixed `-agents` (`PROJECT-stripe-api-key-staging-agents`), not a copy
  of mine.
- One value, one item. A template points at the item; never paste a value
  into a second item.
- Every item has notes: what it is for, which repository and template use
  it, how to rotate or revoke it, who issued it, and when it expires.
- Tag items by project.
- When a tool syncs an item's fields elsewhere, the field names are a
  contract with whoever reads the result: rename one only together with its
  readers.
- Rename an item in the same change that repoints its references.

Lesson from a server-config repo and a product repo.

## Secrets from a password manager

How agents and I use secrets without pasting them or approving a prompt per
lookup. Built on 1Password service accounts and its CLI, `op`; checked
2026-10-05 against [service accounts](https://www.1password.dev/service-accounts/get-started.md)
and, on 2026-10-08, [rate limits](https://www.1password.dev/service-accounts/rate-limits).

### Vaults

A vault's name says who reads it, then its scope; longer descriptive names
are fine.

| Vault | Who reads it | Holds |
|---|---|---|
| `my-master-keys` | Only me, through the desktop app | Production, signing, backup and recovery keys no service account reads, and every service-account token, each tagged with its project |
| `operator-CLUSTER` | The 1Password Kubernetes Operator's service account in that cluster | Only what the cluster syncs that agents must not see |
| `agents-PROJECT` | That project's agent service account, and the Operator's in that project's cluster | Keys this project's agents use, and keys they generate |
| `agents-shared` | Every project's agent service account | Keys several projects' agents use |

- Each secret lives in the one vault with the fewest readers that still
  reaches everything that needs it. A key a cluster syncs goes in
  `operator-CLUSTER`, or in `agents-PROJECT` when that project's agents need
  it too.
- Each service account is named after its vault: `agents-PROJECT` reads its
  vault and `agents-shared`; `operator-CLUSTER` reads its vault and that
  project's `agents-PROJECT`. Give an agent account write on its own vault
  too if agents should later store keys they generate; no tool does that
  yet, so for now an agent asks me to. A service account's vaults and
  permissions can't be changed after it is created; to change them, create
  a new one and revoke the old.
- `my-master-keys` is one vault for every project and is never granted to a
  service account.
- Every vault's description says who reads it and what belongs in it.
- The Private vault holds only my personal logins: no project, agent or
  server keys. A service account can't use Personal or Private vaults.
- A full-access template may point at an `agents-*` item rather than keep
  a copy.
- Agents archive items, never delete them. Deleting is mine.
- Never in an agent vault: production keys, signing keys, backup private
  keys, recovery codes, anything that can't be revoked on its own. Where a
  service can't scope a key (an account-wide API key), give agents their own
  key so it can be revoked without breaking mine.

### Items in 1Password

How [Secret items](#secret-items) map onto 1Password's
[item categories](https://support.1password.com/item-categories) (checked
2026-10-08):

- API Credential for any API key or token: the value in `credential`, a key
  ID in `username`, an endpoint in `hostname`.
- Password for a passphrase with no username, in `password`.
- Login only for a real web sign-in, with its URL.
- SSH Key and Database for those.
- Never put the main value in `token` or another custom label.
- Extra fields are lowercase `snake_case` with no spaces. Identifiers that
  aren't secret are plain text fields.
- The expiry goes in an `expires` date field (`YYYY-MM-DD`). Whether API
  Credential has one built in is unverified; add it where it is missing.
- `op item list --tags PROJECT` lists a project's items; nothing filters by
  expiry.

Why lowercase with no spaces: [secret references](https://www.1password.dev/cli/secret-reference-syntax/)
are case-insensitive and take letters, digits, `-`, `_`, `.` and whitespace;
a reference with spaces must be quoted in a shell, and a name with other
characters must be referred to by ID (checked 2026-10-08). The [Kubernetes Operator](https://www.1password.dev/k8s/operator/)
syncs a whole item (`itemPath` is `vaults/V/items/I`, with no field
selection), and each field label becomes a Kubernetes Secret key. Its page
says labels are lowercased, but its
[source](https://github.com/1Password/onepassword-operator/blob/cd5f2df73134a28005ecd7a74c0147424b587f2e/pkg/kubernetessecrets/kubernetes_secrets_builder.go#L222-L260)
keeps a valid key as written; otherwise it drops invalid characters at the
ends, turns each run of them inside into one `-`, and skips a label left
empty. Only the Secret's own name is lowercased (checked 2026-10-08).

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
case "$(pbpaste)" in ops_*) security add-generic-password -U -s op-agent-PROJECT -a "$USER" -T /usr/bin/security -w "$(pbpaste)" && pbcopy </dev/null ;; *) echo "the clipboard holds no token" >&2 ;; esac
```

Not `-w` last: its prompt reads through `getpass(3)`, which keeps only the
first 128 characters, and a token is several times longer, so `op` later
fails to decode it. Check the stored length and prefix, never the value:

```sh
security find-generic-password -s op-agent-PROJECT -w | awk '{print length($0), substr($0,1,4)}'
```

The token is in argv for the moment `security` runs; on a single-user Mac
that is the accepted trade-off, since `-T /usr/bin/security` already lets
any of my processes read it. Rotate with Rotate Token on the service account
(1Password.com, Developer, Service accounts), letting the old token expire
now or after a grace period, and store the new one the same way. Revoke
Token there revokes the current token, so it is not part of a rotation.

### Token on Linux

The token lives in `~/.config/op/agent-PROJECT.token`, with `PROJECT`
derived as on macOS (`--project NAME` overrides). `with-secrets` refuses the
file unless it is a regular file (not a symlink), owned by the user running
it, mode 600 or 400 (no setuid, setgid or sticky bit), not empty and free of
carriage returns; a trailing newline is trimmed. It also refuses the
directory `~/.config/op` if it is a symlink, not owned by that user, or
writable by group or others. It checks the file it has opened and reads the
token from it, so a file swapped in after the checks is never read. As with
the Keychain, anyone running as that user can read it, so the vault scope is
the boundary. Keep the file out of any dotfiles setup or git checkout (a
stow-managed `~/.config`, for one), so it is never committed or linked.

Create it so the token never reaches argv or the screen. Both lines below set
the directory to 700 and remove an old file first, so an existing directory
or file can't keep a looser mode. In bash or zsh (`read -s` is not POSIX sh),
paste at the prompt; the guard refuses a value that is not a token:

```sh
mkdir -p ~/.config/op && chmod 700 ~/.config/op && (umask 077; IFS= read -rs t && case $t in ops_*) rm -f ~/.config/op/agent-PROJECT.token && printf '%s\n' "$t" > ~/.config/op/agent-PROJECT.token ;; *) echo "not a token" >&2 ;; esac; unset t)
```

Or pipe it from the Mac: copy with the 1Password app's copy button, run the
line below, then clear the clipboard (`pbcopy </dev/null`):

```sh
pbpaste | ssh HOST 'mkdir -p ~/.config/op && chmod 700 ~/.config/op && umask 077 && rm -f ~/.config/op/agent-PROJECT.token && cat > ~/.config/op/agent-PROJECT.token'
```

Check the length and prefix, and the owner and mode, never the value (GNU
`stat`):

```sh
awk '{print length($0), substr($0,1,4)}' ~/.config/op/agent-PROJECT.token
stat -c '%U %a' ~/.config/op/agent-PROJECT.token
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
- `with-secrets --full-access -- CMD` is the same for me: the desktop app
  authorises with my own account, so it reaches every vault I can see,
  `my-master-keys` included. Agents never run it. Its default template is
  `full-access.env.tpl`, or `operator.env.tpl` where that is missing; the
  old flag `--operator` stays as an alias until every project has switched.
- Templates are committed, hold one `NAME=op://VAULT/ITEM/FIELD` per line and
  nothing else; plain values are refused. In agent mode the vault must be an
  `agents-*` name or an ID; agent templates use IDs for vault and item (see
  Quotas).
- `push-secrets MANIFEST` copies values from 1Password into GitHub
  environment or repository secrets and Render environment groups. Values go
  through pipes, never argv or the screen. `--dry-run` lists what it would
  push, and the whole manifest is checked before the first push. Mine
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
  authorisation unprompted, so I run full-access commands in a terminal no
  agent runs from.
- Which templates a brief allows is not enforced by a hook yet. The
  service account's vaults are the hard limit; the template and brief
  narrow use by convention.

Lesson from a product repo and a server-config repo.
