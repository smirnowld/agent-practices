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

# Fake gh: the open sync PR number lives in $t/pr (empty: none open); auto-merge
# fails while $t/no-auto-merge exists.
cat > "$t/bin/gh" <<'GH'
#!/bin/sh
echo "$*" >> "$T/gh.log"
case "$1 $2" in
  "pr list") cat "$T/pr" 2>/dev/null || true ;;
  "pr create") echo 7 > "$T/pr"; echo "https://github.com/o/p/pull/7" ;;
  "pr close") : > "$T/pr" ;;
  "pr edit") ;;
  "pr merge") [ ! -e "$T/no-auto-merge" ] ;;
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

touch "$t/no-auto-merge"
run > "$t/out" 2>&1                                      # stale: opens a PR
grep -q '^o/p: opened #7' "$t/out"
grep -q 'auto-merge not enabled on #7' "$t/out"
git -C "$t/remotes/o/p.git" rev-parse --verify --quiet agent-practices/policy-sync >/dev/null
rm "$t/no-auto-merge"
run | grep -q '^o/p: #7 already carries'                 # same copy: no push,
[ "$(grep -c '^pr create' "$t/gh.log")" = 1 ]
[ "$(grep -c '^pr merge 7 .*--auto' "$t/gh.log")" = 2 ]  # auto-merge retried

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

# A missing repository fails without stopping the others.
if sh "$root/scripts/push-policy-sync.sh" o/missing o/p > "$t/out" 2>&1; then
  echo "missing repository accepted"; exit 1
fi
grep -q '^o/p: current$' "$t/out"
echo "push-policy-sync self-test passed"
