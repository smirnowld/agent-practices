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
# Fake uname: Darwin unless FAKE_UNAME says otherwise, so the Keychain cases
# run the same on a Linux CI runner. Fake id: FAKE_UID for -u when set,
# except once while the file FAKE_UID_SKIP names exists (it is removed).
real_uname=$(command -v uname) real_id=$(command -v id)
cat > "$dir/bin/uname" <<FAKE
#!/bin/sh
[ "\$1" = -s ] && { echo "\${FAKE_UNAME:-Darwin}"; exit 0; }
exec "$real_uname" "\$@"
FAKE
cat > "$dir/bin/id" <<FAKE
#!/bin/sh
if [ "\$1" = -u ] && [ -n "\${FAKE_UID:-}" ]; then
  if [ -n "\${FAKE_UID_SKIP:-}" ] && [ -e "\$FAKE_UID_SKIP" ]; then rm -f "\$FAKE_UID_SKIP"
  else echo "\$FAKE_UID"; exit 0; fi
fi
exec "$real_id" "\$@"
FAKE
# Fake stat: with FAKE_SWAP set, replaces that file just before it is
# inspected by path, as a race after the open would.
real_stat=$(command -v stat)
cat > "$dir/bin/stat" <<FAKE
#!/bin/sh
for a; do
  if [ -n "\${FAKE_SWAP:-}" ] && [ "\$a" = "\$FAKE_SWAP" ]; then
    rm -f "\$a"; printf 'tok-swapped\\n' > "\$a"; chmod 600 "\$a"
  fi
done
exec "$real_stat" "\$@"
FAKE
chmod +x "$dir/bin/op" "$dir/bin/security" "$dir/bin/uname" "$dir/bin/id" "$dir/bin/stat"
PATH="$dir/bin:$PATH"; export PATH
lacks() { [ -f "$2" ] || { echo "no $2"; exit 1; }; if grep -q "$1" "$2"; then echo "$2 holds $1"; exit 1; fi; }
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

# A reference in the environment would bypass the template: refused.
fails env X=op://agents-demo/other/field "$tool" --project demo --template "$dir/agent.tpl" -- true
grep -q 'environment holds op:// references (X)' "$dir/out"

# Full-access mode: any vault, and a token in the caller's shell is dropped.
# --operator is the old name and behaves the same.
for flag in --full-access --operator; do
  : > "$log"
  OP_SERVICE_ACCOUNT_TOKEN=stray "$tool" "$flag" --template "$dir/ops.tpl" -- true
  grep -qx 'op token=none' "$log"
  lacks security "$log"
done

# Full-access mode reports itself, and its default template is full-access.env.tpl,
# else operator.env.tpl; an explicit --template is used as given.
mkdir "$dir/dt"
(cd "$dir/dt" && "$tool" --full-access --dry-run -- true 2>&1 | grep -q 'no template full-access.env.tpl (or operator.env.tpl)')
(cd "$dir/dt" && ! "$tool" --full-access --dry-run -- true >/dev/null 2>&1)
cp "$dir/ops.tpl" "$dir/dt/operator.env.tpl"
(cd "$dir/dt" && "$tool" --full-access --dry-run -- true 2>&1 | grep -qx 'mode full-access, template operator.env.tpl')
(cd "$dir/dt" && "$tool" --operator --dry-run -- true 2>&1 | grep -qx 'mode full-access, template operator.env.tpl')
cp "$dir/ops.tpl" "$dir/dt/full-access.env.tpl"
(cd "$dir/dt" && "$tool" --full-access --dry-run -- true 2>&1 | grep -qx 'mode full-access, template full-access.env.tpl')
(cd "$dir/dt" && "$tool" --full-access --dry-run --template operator.env.tpl -- true 2>&1 | grep -qx 'mode full-access, template operator.env.tpl')
rm "$dir/dt/full-access.env.tpl" "$dir/dt/operator.env.tpl"
(cd "$dir/dt" && ! "$tool" --full-access --dry-run -- true >/dev/null 2>&1)
(cd "$dir/dt" && ! "$tool" --full-access --dry-run --template full-access.env.tpl -- true >/dev/null 2>&1)

# Unknown flags print usage and exit 2.
usage2() {
  rc=0; "$tool" "$@" >"$dir/out" 2>&1 || rc=$?
  [ "$rc" = 2 ] || { echo "usage rc $rc for: $*"; exit 1; }
  grep -q 'usage: with-secrets \[--full-access\]' "$dir/out" || { echo "no usage line for: $*"; exit 1; }
}
usage2 --bogus -- true
# Partial flags and flags with a value are unknown, not the mode switch.
usage2 --full --dry-run --template "$dir/ops.tpl" -- true
usage2 --full-access=1 --dry-run --template "$dir/ops.tpl" -- true
usage2 --operator=1 --dry-run --template "$dir/ops.tpl" -- true

# Agent mode ignores the full-access templates.
mkdir "$dir/at"
cp "$dir/ops.tpl" "$dir/at/full-access.env.tpl"
cp "$dir/ops.tpl" "$dir/at/operator.env.tpl"
(cd "$dir/at" && ! "$tool" --project demo --dry-run -- true >"$dir/out" 2>&1)
grep -q 'no template agent.env.tpl' "$dir/out" || { echo "expected agent.env.tpl in: $(cat "$dir/out")"; exit 1; }

# Dry run lists names and vaults and calls nothing.
: > "$log"
"$tool" --project demo --dry-run --template "$dir/agent.tpl" > "$dir/out" 2>/dev/null
grep -qx "$(printf 'A\tagents-demo')" "$dir/out"
[ ! -s "$log" ]

# Linux: the token comes from ~/.config/op/agent-PROJECT.token, mode 600 or
# 400 and yours; the Keychain is never asked.
HOME="$dir/home"; export HOME
tokdir="$HOME/.config/op"; tok="$tokdir/agent-demo.token"
mkdir -p "$tokdir"; chmod 700 "$tokdir"
printf 'tok-file\n' > "$tok"; chmod 600 "$tok"
FAKE_UNAME=Linux; export FAKE_UNAME
: > "$log"
# Run with fd 3 closed here, so an open fd 3 in the command can only be the
# token file's descriptor leaking through op.
"$tool" --project demo --template "$dir/agent.tpl" -- \
  sh -c 'echo "$A $B" > "$0"; env > "$0.env"
    if [ -e /dev/fd/1 ]; then echo yes; else echo no; fi > "$0.devfd"
    if [ -e /dev/fd/3 ]; then echo open; else echo closed; fi > "$0.fd3"' \
  "$dir/child" 3<&-
[ "$(cat "$dir/child")" = "value-A value-B" ]
[ "$(cat "$dir/child.devfd")" = yes ] || { echo "no /dev/fd; the fd 3 check cannot run"; exit 1; }
[ "$(cat "$dir/child.fd3")" = closed ] || { echo "the command inherited fd 3"; exit 1; }
lacks OP_SERVICE_ACCOUNT_TOKEN "$dir/child.env"
grep -qx 'op token=tok-file' "$log"
lacks security "$log"

# The project name comes from the repository, as on macOS.
: > "$log"
(cd "$dir/demo" && "$tool" -- true)
grep -qx 'op token=tok-file' "$log"

chmod 400 "$tok"
"$tool" --project demo --template "$dir/agent.tpl" -- true

# Refused, naming the file and the practice, never showing the token.
printf 'tok-file-SECRET\n' > "$dir/valid"; chmod 600 "$dir/valid"
refused() {
  fails "$tool" --project demo --template "$dir/agent.tpl" -- true
  grep -q "$tok" "$dir/out" || { echo "no path in: $(cat "$dir/out")"; exit 1; }
  grep -q 'practices/secrets.md' "$dir/out" || { echo "no practice in: $(cat "$dir/out")"; exit 1; }
  grep -q "$1" "$dir/out" || { echo "expected '$1' in: $(cat "$dir/out")"; exit 1; }
  lacks tok-file "$dir/out"
}
for m in 644 640 660 700 604; do
  rm -f "$tok"; printf 'tok-file-SECRET\n' > "$tok"; chmod "$m" "$tok"
  refused "has mode"
done
rm -f "$tok"; refused "is missing"
: > "$tok"; chmod 600 "$tok"; refused "is empty"
printf '\n' > "$tok"; refused "is empty"
rm -f "$tok"; ln -s "$dir/valid" "$tok"; refused "is a symlink"
rm -f "$tok"; mkdir "$tok"; refused "is not a regular file"
rmdir "$tok"; printf 'tok-file-SECRET\n' > "$tok"
# Mode 200 is not readable by its owner, so the file cannot be opened and the
# tool refuses it before reading; root opens it anyway.
if [ "$(id -u)" = 0 ]; then
  echo "note: skipped unreadable token file (running as root)"
else
  chmod 200 "$tok"; refused "cannot be read"
fi
chmod 600 "$tok"
FAKE_UID=4242 FAKE_UID_SKIP="$dir/skip"; export FAKE_UID FAKE_UID_SKIP
: > "$FAKE_UID_SKIP"; refused "is not owned by you"
unset FAKE_UID FAKE_UID_SKIP
"$tool" --project demo --template "$dir/agent.tpl" -- true

# A file replaced between the open and the checks is not read.
FAKE_SWAP=$tok; export FAKE_SWAP
refused "changed while it was checked"
unset FAKE_SWAP
rm -f "$tok"; printf 'tok-file\n' > "$tok"; chmod 600 "$tok"

# A carriage return (CRLF line ending) is refused, not sent to op.
printf 'tok-file-SECRET\r\n' > "$tok"; refused "contains a carriage return"
printf 'tok-file\n' > "$tok"

# Setuid and setgid token files are refused. Skipped, with a note, where the
# system drops the bit (setgid outside your groups, for one).
fmode() { stat -c '%a' -- "$1" 2>/dev/null || stat -f '%Mp%Lp' -- "$1"; }
for m in 4600 2600 1600; do
  rm -f "$tok"; printf 'tok-file-SECRET\n' > "$tok"
  if chmod "$m" "$tok" 2>/dev/null && [ "$(fmode "$tok")" = "$m" ]; then
    refused "has mode $m"
  else
    echo "note: skipped mode $m (chmod did not set it here)"
  fi
done
rm -f "$tok"; printf 'tok-file\n' > "$tok"; chmod 600 "$tok"

# The directory: yours, not a symlink, not writable by group or others.
refused_dir() {
  fails "$tool" --project demo --template "$dir/agent.tpl" -- true
  grep -q "token directory $tokdir $1" "$dir/out" || { echo "expected '$1' in: $(cat "$dir/out")"; exit 1; }
  grep -q 'practices/secrets.md' "$dir/out" || { echo "no practice in: $(cat "$dir/out")"; exit 1; }
  lacks tok-file "$dir/out"
}
for m in 777 775 757 720; do chmod "$m" "$tokdir"; refused_dir "has mode"; done
for m in 755 700 750; do chmod "$m" "$tokdir"; "$tool" --project demo --template "$dir/agent.tpl" -- true; done
FAKE_UID=4242; export FAKE_UID
refused_dir "is not owned by you"
unset FAKE_UID
mv "$tokdir" "$HOME/.config/op-real"; ln -s op-real "$tokdir"
refused_dir "is a symlink"
rm "$tokdir"; mv "$HOME/.config/op-real" "$tokdir"
chmod 700 "$tokdir"
"$tool" --project demo --template "$dir/agent.tpl" -- true

# A project name that could leave the directory is refused on Linux.
for p in ../demo .demo -demo 'de/mo'; do
  fails "$tool" --project "$p" --template "$dir/agent.tpl" -- true
  grep -q 'project name must match' "$dir/out"
  lacks 'de/mo' "$dir/out"; lacks '\.\./demo' "$dir/out"; lacks ' -demo' "$dir/out"
done
fails "$tool" --project "$(printf 'demo\n../x')" --template "$dir/agent.tpl" -- true
grep -q 'project name' "$dir/out"

# Other systems are refused.
FAKE_UNAME=FreeBSD
fails "$tool" --project demo --template "$dir/agent.tpl" -- true
grep -q 'macOS (Keychain) and Linux (token file) only' "$dir/out"

# macOS ignores the token file and asks the Keychain.
FAKE_UNAME=Darwin
: > "$log"
"$tool" --project demo --template "$dir/agent.tpl" -- true
grep -qx 'op token=tok-demo' "$log"
grep -q '^security ' "$log"
echo "with-secrets self-test passed"
