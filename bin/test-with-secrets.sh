#!/bin/sh
# Self-test for with-secrets against fake op and security; touches no vault.
set -eu
# The WSL route needs WSL_DISTRO_NAME; only the WSL cases set it, with fake
# op.exe and wsl.exe, so no case reaches the real ones.
unset WSL_DISTRO_NAME WSLENV
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

# WSL: full-access goes through the Windows op.exe, which starts the command
# back in this distro with wsl.exe. Fake wslpath prefixes WIN:, fake op.exe
# strips it. Fake wsl.exe models the boundary: the command gets only HOME, a
# default PATH and the variables WSLENV names (last entry wins, /w skipped),
# and a missing --cd directory falls back to /. Fake cmd.exe prints the
# Windows environment from FAKE_WINENV plus what WSLENV forwards, with CRLF.
cat > "$dir/bin/wslpath" <<'FAKE'
#!/bin/sh
echo "wslpath $*" >> "$FAKE_LOG"
[ "$1" = -w ] || exit 9
[ -z "${FAKE_WSLPATH_FAIL:-}" ] || exit 1
echo "WIN:$2"
FAKE
cat > "$dir/bin/op.exe" <<'FAKE'
#!/bin/sh
echo "op.exe $*" >> "$FAKE_LOG"
[ "$1" = run ] && [ "$2" = --env-file ] && [ "$4" = -- ] || exit 9
case $3 in WIN:*) ;; *) exit 9 ;; esac
case $5 in WIN:*) ;; *) exit 9 ;; esac
echo "op.exe token=${OP_SERVICE_ACCOUNT_TOKEN:-none}" >> "$FAKE_LOG"
[ -z "${FAKE_OPEXE_FAIL:-}" ] || exit 3
if [ -n "${FAKE_OPEXE_SLEEP:-}" ]; then echo $$ > "$FAKE_OPEXE_SLEEP"; exec sleep 5; fi
[ -z "${FAKE_RMDIR:-}" ] || rmdir "$FAKE_RMDIR"
tpl=${3#WIN:} cmd=${5#WIN:}; shift 5
while IFS= read -r l; do
  case $l in ''|'#'*) continue ;; esac
  export "${l%%=*}=value-${l%%=*}"
done < "$tpl"
exec "$cmd" "$@"
FAKE
cat > "$dir/bin/wsl.exe" <<'FAKE'
#!/bin/sh
echo "wsl.exe $*" >> "$FAKE_LOG"
[ "$1" = -d ] && [ "$2" = "$WSL_DISTRO_NAME" ] && [ "$3" = -u ] && [ "$4" = "$(id -un)" ] \
  && [ "$5" = --cd ] && [ "$7" = --exec ] || exit 9
echo "wslenv=${WSLENV-unset}" >> "$FAKE_LOG"
[ "${11}" = with-secrets ] || exit 9
dump=${12}
echo "dumpmode=$(stat -c %a "$dump")" >> "$FAKE_LOG"
cd "$6" 2>/dev/null || { echo "wsl.exe in /" >> "$FAKE_LOG"; cd /; }
shift 7
names=$(printf '%s' "${WSLENV-}" | awk -v RS=: '{ n = $0; f = ""; i = index(n, "/")
  if (i) { f = substr(n, i + 1); n = substr(n, 1, i - 1) }
  if (n != "") last[n] = f } END { for (n in last) if (last[n] !~ /w/) print n }')
for n in $names; do
  if v=$(printenv "$n"); then set -- "$n=$v" "$@"; fi
done
[ -z "${WSLENV+x}" ] || set -- "WSLENV=$WSLENV" "$@"
rc=0; env -i PATH=/usr/bin:/bin HOME="$HOME" WSL_INTEROP=/run/WSL/new "$@" || rc=$?
[ -e "$dump" ] && echo "dump left by the inner shell" >> "$FAKE_LOG"
exit "$rc"
FAKE
cat > "$dir/bin/cmd.exe" <<'FAKE'
#!/bin/sh
echo "cmd.exe $*" >> "$FAKE_LOG"
[ "$*" = "/d /c set" ] || exit 9
# Interop hands the Windows process our stdin; drain it as that would.
cat >/dev/null
{ cat "$FAKE_WINENV"
  old_ifs=$IFS; IFS=:
  for e in ${WSLENV-}; do n=${e%%/*}; v=$(printenv "$n") && echo "$n=$v"; done
  IFS=$old_ifs
} | sed 's/$/\r/'
FAKE
chmod +x "$dir/bin/wslpath" "$dir/bin/op.exe" "$dir/bin/wsl.exe" "$dir/bin/cmd.exe"
printf 'Path=C:\\Windows\nUSERPROFILE=C:\\Users\\demo\n=C:=C:\\\n' > "$dir/winenv"
mkdir -m 700 "$dir/rt"
FAKE_LOG=$log WSL_DISTRO_NAME=Ubuntu-test FAKE_WINENV=$dir/winenv XDG_RUNTIME_DIR=$dir/rt
export FAKE_LOG WSL_DISTRO_NAME FAKE_WINENV XDG_RUNTIME_DIR
for c in op.exe wsl.exe wslpath cmd.exe; do
  [ "$(command -v "$c")" = "$dir/bin/$c" ] || { echo "$c is not the fake: $(command -v "$c")"; exit 1; }
done
printf '# full access\nA=op://demo-ops/item/field\nB=op://Private/other item/field\n' > "$dir/wsl.tpl"
nolinuxop() { if grep -q '^op ' "$log"; then echo "the Linux op ran"; exit 1; fi; }
rtempty() { [ -z "$(ls -A "$dir/rt")" ] || { echo "environment file left: $(ls -A "$dir/rt")"; exit 1; }; }
me=$(id -un)

# Values, arguments, stdin, exit code and directory all cross; WSLENV unset
# becomes A:B with no leading colon, and the command sees no WSLENV; a stray
# token never reaches op.exe; the environment file is 600 and then gone.
mkdir "$dir/wd"; wd=$(cd "$dir/wd" && pwd)
: > "$log"; rc=0
(cd "$wd" && printf 'yes\n' | OP_SERVICE_ACCOUNT_TOKEN=stray "$tool" --full-access --template "$dir/wsl.tpl" -- \
  sh -c 'out=$1; shift; read -r in; pwd > "$out"; env > "$out.env"
    printf "%s|" "$A" "$B" "$in" "$#" "$@" > "$out.vals"; exit 7' \
  x "$dir/wchild" 'a b' '$HOME' "it's" 'q"uo"te' '' 'back\slash' ';echo pwn') || rc=$?
[ "$rc" = 7 ] || { echo "exit code $rc, expected 7"; exit 1; }
printf '%s|' value-A value-B yes 7 'a b' '$HOME' "it's" 'q"uo"te' '' 'back\slash' ';echo pwn' > "$dir/wexpect"
cmp -s "$dir/wexpect" "$dir/wchild.vals" || { echo "got: $(cat "$dir/wchild.vals")"; exit 1; }
[ "$(cat "$dir/wchild")" = "$wd" ]
grep -qx "op.exe run --env-file WIN:$dir/wsl.tpl -- WIN:$dir/bin/wsl.exe -d Ubuntu-test -u $me --cd $wd --exec /bin/sh -c .*" "$log"
grep -qx 'op.exe token=none' "$log"
grep -qx 'wslenv=A:B' "$log"
grep -qx 'dumpmode=600' "$log"
grep -qx 'cmd.exe /d /c set' "$log"
lacks OP_SERVICE_ACCOUNT_TOKEN "$dir/wchild.env"
lacks '^WSLENV=' "$dir/wchild.env"
lacks "^A=op:" "$dir/wchild.env"
lacks 'dump left' "$log"; nolinuxop; rtempty

# The caller's variables and PATH reach the command; a plain value of a
# template name loses to the secret; existing WSLENV entries for template
# names are dropped (the last entry would win) and the rest stay first; the
# command sees the caller's own WSLENV but the new session's WSL_INTEROP.
# --operator is the same.
mkdir "$dir/callerbin"; printf '#!/bin/sh\necho hi\n' > "$dir/callerbin/hello-caller"
chmod +x "$dir/callerbin/hello-caller"
tricky=$(printf "it's \$HOME \"q\" \\\\ \nline2")
for flag in --full-access --operator; do
  : > "$log"
  A=plain AWS_PROFILE=staging WSLENV=USERPROFILE/p:A:A/p PATH="$dir/callerbin:$PATH" \
    WSL_INTEROP=/run/WSL/caller TRICKY="$tricky" "$tool" "$flag" --template "$dir/wsl.tpl" -- \
    sh -c 'printf "%s\n" "$A $B" "$AWS_PROFILE" "$WSLENV" "$(command -v hello-caller)" \
      "$WSL_INTEROP" "$TRICKY" > "$0"' "$dir/wchild"
  printf '%s\n' "value-A value-B" staging USERPROFILE/p:A:A/p "$dir/callerbin/hello-caller" \
    /run/WSL/new "$tricky" > "$dir/wexpect"
  cmp -s "$dir/wexpect" "$dir/wchild" || { echo "got: $(cat "$dir/wchild")"; exit 1; }
  grep -qx 'wslenv=USERPROFILE/p:A:B' "$log"
  nolinuxop; rtempty
done

# A large input reaches the command whole.
: > "$log"
seq 1 20000 | "$tool" --full-access --template "$dir/wsl.tpl" -- sh -c 'wc -c > "$0"' "$dir/wchild"
[ "$(tr -d ' ' < "$dir/wchild")" = "$(seq 1 20000 | wc -c | tr -d ' ')" ] \
  || { echo "stdin cut to $(cat "$dir/wchild") bytes"; exit 1; }

# A relative template path starting with - is made absolute for wslpath.
cp "$dir/wsl.tpl" "$wd/-t.tpl"
: > "$log"
(cd "$wd" && "$tool" --full-access --template -t.tpl -- sh -c 'echo "$A" > "$0"' "$dir/wchild")
[ "$(cat "$dir/wchild")" = value-A ]
grep -qx "wslpath -w $wd/-t.tpl" "$log"

# The environment file is gone when op.exe fails before running anything.
: > "$log"; rc=0
FAKE_OPEXE_FAIL=1; export FAKE_OPEXE_FAIL
"$tool" --full-access --template "$dir/wsl.tpl" -- true || rc=$?
unset FAKE_OPEXE_FAIL
[ "$rc" = 3 ] || { echo "exit code $rc, expected 3"; exit 1; }
lacks "^wsl.exe" "$log"; rtempty

# TERM goes on to op.exe; once it has ended the file is removed and the exit
# status is 143.
: > "$log"; rm -f "$dir/op.pid"
FAKE_OPEXE_SLEEP=$dir/op.pid; export FAKE_OPEXE_SLEEP
"$tool" --full-access --template "$dir/wsl.tpl" -- true &
wpid=$!
unset FAKE_OPEXE_SLEEP
i=0; while [ ! -s "$dir/op.pid" ] && [ "$i" -lt 40 ]; do sleep 0.05; i=$((i + 1)); done
[ -s "$dir/op.pid" ] || { echo "fake op.exe did not start"; exit 1; }
kill -TERM "$wpid"
# The fake sleeps 5 s: still running after 1 s means TERM was not passed on.
i=0; while kill -0 "$wpid" 2>/dev/null && [ "$i" -lt 20 ]; do sleep 0.05; i=$((i + 1)); done
if kill -0 "$wpid" 2>/dev/null; then echo "TERM was not passed on to op.exe"; kill -KILL "$wpid"; exit 1; fi
rc=0; wait "$wpid" || rc=$?
[ "$rc" = 143 ] || { echo "exit code $rc after TERM, expected 143"; exit 1; }
if kill -0 "$(cat "$dir/op.pid")" 2>/dev/null; then echo "op.exe outlived with-secrets"; exit 1; fi
rtempty

# The environment file needs XDG_RUNTIME_DIR, a directory; no /tmp fallback.
: > "$log"
(unset XDG_RUNTIME_DIR; fails "$tool" --full-access --template "$dir/wsl.tpl" -- true)
grep -q 'XDG_RUNTIME_DIR is unset or not a directory' "$dir/out"
(XDG_RUNTIME_DIR=$dir/winenv; fails "$tool" --full-access --template "$dir/wsl.tpl" -- true)
grep -q 'XDG_RUNTIME_DIR is unset or not a directory' "$dir/out"
lacks '^op.exe' "$log"; lacks '^cmd.exe' "$log"

# A directory the new session cannot enter fails closed: wsl.exe falls back
# to /, and the inner shell refuses to run the command there. A current
# directory that is already gone is refused before op.exe.
mkdir "$dir/gone"; : > "$log"; rc=0
FAKE_RMDIR=$dir/gone; export FAKE_RMDIR
(cd "$dir/gone" && "$tool" --full-access --template "$dir/wsl.tpl" -- \
  sh -c ': > "$0"' "$dir/ran") 2>"$dir/out" || rc=$?
unset FAKE_RMDIR
[ "$rc" = 126 ] || { echo "exit code $rc, expected 126"; exit 1; }
[ ! -e "$dir/ran" ] || { echo "the command ran in /"; exit 1; }
grep -qx 'wsl.exe in /' "$log"
rtempty
mkdir "$dir/gone"; : > "$log"; rc=0
(cd "$dir/gone" && rmdir "$dir/gone" && "$tool" --full-access --template "$dir/wsl.tpl" -- \
  sh -c ': > "$0"' "$dir/ran") 2>"$dir/out" || rc=$?
[ "$rc" = 1 ] && grep -q 'cannot tell the current directory' "$dir/out" \
  || { echo "rc $rc: $(cat "$dir/out")"; exit 1; }
[ ! -e "$dir/ran" ]; lacks '^op.exe' "$log"; rtempty

# Dry run in WSL names the route and calls no .exe or wslpath.
: > "$log"
"$tool" --full-access --dry-run --template "$dir/wsl.tpl" 2>"$dir/out" >/dev/null
grep -qx "mode full-access (Windows op.exe), template $dir/wsl.tpl" "$dir/out"
[ ! -s "$log" ]

# A reference in the WSL environment is still refused, before any .exe.
: > "$log"
fails env X=op://demo-ops/other/field "$tool" --full-access --template "$dir/wsl.tpl" -- true
grep -q 'environment holds op:// references (X)' "$dir/out"
[ ! -s "$log" ]

# The Windows environment: op:// values and service tokens refused by name,
# values never shown, op.exe never run.
winrefused() {
  : > "$log"
  fails "$tool" --full-access --template "$dir/wsl.tpl" -- true
  grep -q "$1" "$dir/out" || { echo "expected '$1' in: $(cat "$dir/out")"; exit 1; }
  lacks dummysecret "$dir/out"; lacks '^op.exe' "$log"; rtempty
}
cp "$dir/winenv" "$dir/winenv.ok"
printf 'XREF=op://Private/item/dummysecret\n' >> "$dir/winenv"
winrefused 'Windows environment holds op:// references (XREF)'
cp "$dir/winenv.ok" "$dir/winenv"; printf 'OP_SERVICE_ACCOUNT_TOKEN=dummysecret\n' >> "$dir/winenv"
winrefused 'Windows environment sets OP_SERVICE_ACCOUNT_TOKEN'
cp "$dir/winenv.ok" "$dir/winenv"; printf 'op_connect_token=dummysecret\n' >> "$dir/winenv"
winrefused 'Windows environment sets OP_CONNECT_TOKEN'
cp "$dir/winenv.ok" "$dir/winenv"

# Names that collide in Windows, which ignores case, are refused.
printf 'A=op://demo-ops/item/field\na=op://demo-ops/item/other\n' > "$dir/case.tpl"
: > "$log"
fails "$tool" --full-access --template "$dir/case.tpl" -- true
grep -q 'differ only in case (A)' "$dir/out"; [ ! -s "$log" ]
printf 'path=op://demo-ops/item/field\n' > "$dir/case.tpl"
fails "$tool" --full-access --template "$dir/case.tpl" -- true
grep -q 'template name PATH (in any case) is not allowed' "$dir/out"
printf 'userprofile=op://demo-ops/item/field\n' > "$dir/case.tpl"
: > "$log"
fails "$tool" --full-access --template "$dir/case.tpl" -- true
grep -q 'match Windows variables, ignoring case: userprofile' "$dir/out"
lacks '^op.exe' "$log"; rtempty

# wslpath failing stops the run before op.exe.
: > "$log"
FAKE_WSLPATH_FAIL=1; export FAKE_WSLPATH_FAIL
fails "$tool" --full-access --template "$dir/wsl.tpl" -- true
unset FAKE_WSLPATH_FAIL
grep -q 'wslpath cannot convert' "$dir/out"
lacks op.exe "$log"

# Without cmd.exe the Windows environment cannot be checked: refused.
mkdir "$dir/nocmd"
for c in op.exe wsl.exe wslpath; do ln -s "$dir/bin/$c" "$dir/nocmd/$c"; done
: > "$log"
(PATH="$dir/nocmd:/usr/bin:/bin"
  fails "$tool" --full-access --template "$dir/wsl.tpl" -- true)
grep -q 'no cmd.exe on PATH' "$dir/out"
lacks op.exe "$log"

# Agent mode in WSL is unchanged: the Linux op, never an .exe.
: > "$log"
"$tool" --project demo --template "$dir/agent.tpl" -- true
grep -qx 'op token=tok-demo' "$log"
lacks '\.exe' "$log"; lacks wslpath "$log"

# Without op.exe on PATH, full-access uses the Linux op.
mkdir "$dir/linbin"; cp "$dir/bin/op" "$dir/linbin/op"
: > "$log"
(PATH="$dir/linbin:/usr/bin:/bin"
  ! command -v op.exe >/dev/null 2>&1 || { echo "op.exe still on PATH"; exit 1; }
  "$tool" --full-access --template "$dir/wsl.tpl" -- true)
grep -qx 'op token=none' "$log"
lacks '\.exe' "$log"

rm "$dir/bin/wslpath" "$dir/bin/op.exe" "$dir/bin/wsl.exe" "$dir/bin/cmd.exe"
unset WSL_DISTRO_NAME FAKE_LOG FAKE_WINENV XDG_RUNTIME_DIR

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
