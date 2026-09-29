#!/bin/sh
# Self-test for push-policy-sync.sh: a local bare repository stands in for
# GitHub (git url rewriting) and a fake gh records pull request calls.
set -eu
root=$(pwd)
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/remotes/o"
export GIT_CONFIG_GLOBAL="$t/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global url."file://$t/remotes/".insteadOf https://github.com/
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# Fake gh: the open sync PR number lives in $t/pr (empty: none open) and a
# fork's PR from a branch of the same name in $t/fork; pr list emits both as
# JSON and applies the caller's --jq when jq is available. Auto-merge fails
# while $t/no-auto-merge exists.
cat > "$t/bin/gh" <<'GH'
#!/bin/sh
echo "$*" >> "$T/gh.log"
case "$1 $2" in
  "pr list")
    json='['
    [ -s "$T/fork" ] && json="$json{\"number\":$(cat "$T/fork"),\"isCrossRepository\":true},"
    [ -s "$T/pr" ] && json="$json{\"number\":$(cat "$T/pr"),\"isCrossRepository\":false},"
    json="${json%,}]"
    if command -v jq >/dev/null; then
      while [ $# -gt 0 ]; do [ "$1" = --jq ] && filter=$2; shift; done
      printf '%s\n' "$json" | jq -r "$filter"
    else
      cat "$T/pr" 2>/dev/null || true
    fi ;;
  "pr create") echo 7 > "$T/pr"; echo "https://github.com/o/p/pull/7" ;;
  "pr close") : > "$T/pr" ;;
  "pr edit") ;;
  "pr merge")
    case "$*" in *--disable-auto*) exit 0 ;; esac
    [ ! -e "$T/no-auto-merge" ] ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 1 ;;
esac
GH
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH" T="$t"

git init --quiet --bare "$t/remotes/o/p.git"
git clone --quiet "$t/remotes/o/p.git" "$t/work" 2>/dev/null
printf '# Project\n' > "$t/work/AGENTS.md"
git -C "$t/work" add AGENTS.md
git -C "$t/work" commit --quiet -m init
git -C "$t/work" push --quiet origin HEAD:main

run() { sh "$root/scripts/push-policy-sync.sh" o/p; }
bare=$t/remotes/o/p.git
sync_tip() { git -C "$bare" rev-parse agent-practices/policy-sync; }
# Rewrite the sync branch as someone else would: $1 is a shell command run in
# a clone of it, amended onto its one commit.
tamper() {
  rm -rf "$t/tamper"
  git clone --quiet --branch agent-practices/policy-sync "$bare" "$t/tamper" 2>/dev/null
  (cd "$t/tamper" && eval "$1" && git add -A && git commit --quiet --amend --no-edit)
  git -C "$t/tamper" push --quiet --force origin agent-practices/policy-sync
}

# A fork's PR from a branch of the same name is not ours: a new PR is opened.
echo 9 > "$t/fork"
touch "$t/no-auto-merge"
run > "$t/out" 2>&1                                      # stale: opens a PR
grep -q '^o/p: opened #7' "$t/out"
grep -q 'auto-merge not enabled on #7' "$t/out"
if grep -q '^pr [a-z]* 9 ' "$t/gh.log"; then echo "acted on the fork's PR"; exit 1; fi
grep -q '^pr list --repo o/p --base main --head agent-practices/policy-sync .*isCrossRepository' "$t/gh.log"
command -v jq >/dev/null || echo "note: jq not found; fork filter checked by its arguments only"
: > "$t/fork"
rm "$t/no-auto-merge"
first=$(sync_tip)
run | grep -q '^o/p: #7 already carries'                 # same copy: no push,
[ "$(sync_tip)" = "$first" ]
[ "$(grep -c '^pr create' "$t/gh.log")" = 1 ]
[ "$(grep -c '^pr merge 7 .*--auto' "$t/gh.log")" = 2 ]  # auto-merge retried,
grep -q "^pr merge 7 --repo o/p --auto --squash --match-head-commit $first\$" "$t/gh.log"

# Only the revision stamps differ: no push, auto-merge pinned to that commit.
tamper "sed -i.bak -e 's/begin [0-9a-f]* -->/begin 0000000 -->/' \
  -e 's#/blob/[0-9a-f]*/#/blob/0000000/#g' AGENTS.md && rm AGENTS.md.bak"
stamped=$(sync_tip)
[ "$stamped" != "$first" ]
run | grep -q '^o/p: #7 already carries'
[ "$(sync_tip)" = "$stamped" ]
grep -q "^pr merge 7 --repo o/p --auto --squash --match-head-commit $stamped\$" "$t/gh.log"

# Someone else's file on the sync branch: the branch is rebuilt without it.
tamper "echo x > extra"
run | grep -q '^o/p: updated #7'
git -C "$bare" show "$(sync_tip)" --stat --format= | grep -q AGENTS.md
if git -C "$bare" cat-file -e "$(sync_tip):extra" 2>/dev/null; then
  echo "foreign file kept on the sync branch"; exit 1
fi
[ "$(git -C "$bare" rev-parse "$(sync_tip)^")" = "$(git -C "$bare" rev-parse main)" ]
grep -q "^pr merge 7 --repo o/p --auto --squash --match-head-commit $(sync_tip)\$" "$t/gh.log"

# Someone else's empty commit on top (same tree): replaced by the one sync commit.
git -C "$t/tamper" fetch --quiet origin agent-practices/policy-sync
git -C "$t/tamper" reset --quiet --hard FETCH_HEAD
git -C "$t/tamper" commit --quiet --allow-empty -m foreign
git -C "$t/tamper" push --quiet origin agent-practices/policy-sync
run | grep -q '^o/p: updated #7'
[ "$(git -C "$bare" rev-parse "$(sync_tip)^")" = "$(git -C "$bare" rev-parse main)" ]

# An edit outside the block on the sync branch: rebuilt, not skipped.
tamper "printf 'Sneaky.\n' >> AGENTS.md"
run | grep -q '^o/p: updated #7'
if git -C "$bare" show "$(sync_tip):AGENTS.md" | grep -q Sneaky; then
  echo "edit outside the block kept"; exit 1
fi

# Main moves on: the PR branch is rebuilt on it and the open PR reused.
printf 'Own rules.\n' >> "$t/work/AGENTS.md"
git -C "$t/work" commit --quiet -am more
git -C "$t/work" push --quiet origin HEAD:main
run | grep -q '^o/p: updated #7'
[ "$(grep -c '^pr create' "$t/gh.log")" = 1 ]
git -C "$t/remotes/o/p.git" show agent-practices/policy-sync:AGENTS.md | grep -q '^Own rules\.$'

# Main catches up another way: the PR is closed.
git -C "$t/work" fetch --quiet origin agent-practices/policy-sync
git -C "$t/work" merge --quiet --ff-only FETCH_HEAD
git -C "$t/work" push --quiet origin HEAD:main
run | grep -q '^o/p: current; closed #7'
run | grep -q '^o/p: current$'

# No AGENTS.md and a default branch other than main: the file is created and
# the PR targets that branch.
git init --quiet --bare --initial-branch=trunk "$t/remotes/o/q.git"
git clone --quiet "$t/remotes/o/q.git" "$t/q" 2>/dev/null
echo x > "$t/q/README"
git -C "$t/q" add README
git -C "$t/q" commit --quiet -m init
git -C "$t/q" push --quiet origin HEAD:trunk
: > "$t/pr"
sh "$root/scripts/push-policy-sync.sh" o/q | grep -q '^o/q: opened #7'
grep -q '^pr create --repo o/q --base trunk ' "$t/gh.log"
git -C "$t/remotes/o/q.git" show agent-practices/policy-sync:AGENTS.md |
  grep -q '^<!-- agent-practices:policy:begin'
: > "$t/pr"

# A sync that changes AGENTS.md outside the block (a sync-policy.sh stand-in
# appends a line to a current copy, then also breaks the end marker): the PR is left open and auto-merge switched off.
fake=$t/fakeroot
mkdir -p "$fake/scripts"
cp "$root/scripts/push-policy-sync.sh" "$fake/scripts/"
cat > "$fake/scripts/sync-policy.sh" <<SP
#!/bin/sh
sh "$root/scripts/sync-policy.sh" "\$1" > /dev/null
if [ -e "$t/unclose" ]; then   # hide the addition inside an unclosed block
  sed -i.bak 's/policy:end -->\$/policy:end -->x/' "\$1/AGENTS.md"
  rm "\$1/AGENTS.md.bak"
fi
printf 'Sneaky.\n' >> "\$1/AGENTS.md"
echo "synced: \$1/AGENTS.md"
SP
git -C "$fake" init --quiet
git -C "$fake" add -A
git -C "$fake" commit --quiet -m fake
: > "$t/gh.log"
sh "$fake/scripts/push-policy-sync.sh" o/p > "$t/out" 2>&1
grep -q 'left open without auto-merge: the sync commit changes AGENTS.md outside the policy block' "$t/out"
grep -q '^pr merge 7 --repo o/p --disable-auto$' "$t/gh.log"
if grep -q -- '--auto --squash' "$t/gh.log"; then echo "auto-merge enabled on an unsafe sync"; exit 1; fi
touch "$t/unclose"
sh "$fake/scripts/push-policy-sync.sh" o/p > "$t/out" 2>&1
grep -q 'left open without auto-merge: the sync commit leaves AGENTS.md without exactly one closed policy block' "$t/out"
if grep -q -- '--auto --squash' "$t/gh.log"; then echo "auto-merge enabled on an unsafe sync"; exit 1; fi
sh "$root/scripts/push-policy-sync.sh" o/p | grep -q '^o/p: current; closed #7'

# Mixed line endings in the project's file survive the sync, so the guard passes.
printf '# Project\r\nLF line\n' > "$t/work/AGENTS.md"
git -C "$t/work" commit --quiet -am mixed
git -C "$t/work" push --quiet origin HEAD:main
: > "$t/gh.log"
run | grep -q '^o/p: opened #7'
grep -q -- "--auto --squash --match-head-commit $(sync_tip)\$" "$t/gh.log"
[ "$(git -C "$bare" show "$(sync_tip):AGENTS.md" | head -n 2 | od -An -c | tr -d ' \n')" = \
  '#Project\r\nLFline\n' ]
git -C "$t/work" fetch --quiet origin agent-practices/policy-sync   # merge it
git -C "$t/work" merge --quiet --ff-only FETCH_HEAD
git -C "$t/work" push --quiet origin HEAD:main

# A missing repository fails without stopping the others.
if sh "$root/scripts/push-policy-sync.sh" o/missing o/p > "$t/out" 2>&1; then
  echo "missing repository accepted"; exit 1
fi
grep -q '^o/p: current; closed #7$' "$t/out"
echo "push-policy-sync self-test passed"
