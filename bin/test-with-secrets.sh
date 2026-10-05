#!/bin/sh
# Self-test for with-secrets against fake op and security; touches no vault.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/with-secrets"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin"
log="$dir/log"
# Fake op run: records whether it got a token, sets NAME=value-NAME for each
# template line, then runs the command.
cat > "$dir/bin/op" <<FAKE
#!/bin/sh
echo "op \$*" >> "$log"
[ "\$1" = run ] && [ "\$2" = --env-file ] || exit 9
echo "op token=\${OP_SERVICE_ACCOUNT_TOKEN:-none}" >> "$log"
tpl=\$3; shift 4
while IFS= read -r l; do
  case \$l in ''|'#'*) continue ;; esac
  export "\${l%%=*}=value-\${l%%=*}"
done < "\$tpl"
exec "\$@"
FAKE
cat > "$dir/bin/security" <<FAKE
#!/bin/sh
echo "security \$*" >> "$log"
[ "\$3" = op-agent-demo ] || exit 44
echo tok-demo
FAKE
chmod +x "$dir/bin/op" "$dir/bin/security"
PATH="$dir/bin:$PATH"; export PATH
lacks() { if grep -q "$1" "$2"; then echo "$2 holds $1"; exit 1; fi; }
fails() { if "$@" >"$dir/out" 2>&1; then echo "expected failure: $*"; exit 1; fi; }

printf '# agent\nA=op://agents-demo/item/field\nB=op://abcdefghijklmnopqrstuvwxyz/item with spaces/field\n' > "$dir/agent.tpl"
printf 'A=op://demo-ops/item/field\n' > "$dir/ops.tpl"
printf 'A=hunter2plain\n' > "$dir/plain.tpl"
printf 'hunter2plain\n' > "$dir/bare.tpl"

# Agent mode: the command gets the values; only op gets the token.
"$tool" --project demo --template "$dir/agent.tpl" -- \
  sh -c 'echo "$A $B" > "$0"; env > "$0.env"' "$dir/child"
[ "$(cat "$dir/child")" = "value-A value-B" ]
lacks OP_SERVICE_ACCOUNT_TOKEN "$dir/child.env"
grep -qx 'op token=tok-demo' "$log"

# Agent mode finds the project from the repository's main checkout.
mkdir "$dir/demo" && git -C "$dir/demo" init -q
(cd "$dir/demo" && cp "$dir/agent.tpl" agent.env.tpl && "$tool" -- true)

# Agent mode refuses a vault outside agents-*, a plain value and a bare line,
# without printing the value.
fails "$tool" --project demo --template "$dir/ops.tpl" -- true
grep -q 'agents-\* vaults only' "$dir/out"
fails "$tool" --project demo --template "$dir/plain.tpl" -- true
lacks hunter2plain "$dir/out"
fails "$tool" --project demo --template "$dir/bare.tpl" -- true
lacks hunter2plain "$dir/out"
fails "$tool" --project demo --template "$dir/missing.tpl" -- true
fails "$tool" --project other --template "$dir/agent.tpl" -- true
grep -q 'no Keychain item op-agent-other' "$dir/out"

# Operator mode: any vault, and a token in the caller's shell is dropped.
: > "$log"
OP_SERVICE_ACCOUNT_TOKEN=stray "$tool" --operator --template "$dir/ops.tpl" -- true
grep -qx 'op token=none' "$log"
lacks security "$log"

# Dry run lists names and vaults and calls nothing.
: > "$log"
"$tool" --project demo --dry-run --template "$dir/agent.tpl" > "$dir/out" 2>/dev/null
grep -qx "$(printf 'A\tagents-demo')" "$dir/out"
[ ! -s "$log" ]
echo "with-secrets self-test passed"
