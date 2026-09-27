#!/bin/sh
# Copy policy/AGENTS.md into each project's AGENTS.md between sync markers.
# Adds the block at the end the first time; replaces it afterwards. Leaves the
# rest of the file untouched. Commit the result in each project through a PR.
#
#   scripts/sync-policy.sh PROJECT_DIR...
#   scripts/sync-policy.sh --check PROJECT_DIR...   # exit 1 if any copy is stale
#
# The synced copy differs from policy/AGENTS.md so that it reads correctly
# inside a project: headings move down one level, and backticked paths into
# this repository (roles/, templates/, ...) become links to this repository's
# origin at the synced revision. Without an origin remote they stay as text.
#
# A file whose markers are malformed (missing, duplicated or out of order) is
# reported and never modified. Files with CRLF line endings are handled: lines
# are compared without the trailing CR, and a file whose first line ends in CRLF
# is written back with CRLF on every line (mixed endings become CRLF).
#
# Exit status: 0 all fine, 1 a file is stale (--check) or could not be synced,
# 2 usage error or the policy cannot be synced from this checkout.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd -P)
check=0
[ "${1:-}" = "--check" ] && { check=1; shift; }
[ $# -gt 0 ] || { echo "usage: $0 [--check] PROJECT_DIR..." >&2; exit 2; }

begin='<!-- agent-practices:policy:begin'
end='<!-- agent-practices:policy:end -->'
policy="$root/policy/AGENTS.md"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/sync-policy.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if grep -qF -e "$begin" -e "$end" "$policy"; then
  echo "error: $policy contains a sync marker; remove it before syncing" >&2
  exit 2
fi

# Git state: only when this checkout is its own repository (not a parent's).
has_git=0
top=$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$top" ] && [ "$(cd "$top" && pwd -P)" = "$root" ]; then
  has_git=1
fi

rev=uncommitted
url=
if [ $has_git = 1 ]; then
  rev=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo uncommitted)
  # Refuse to stamp a revision whose policy differs from what is synced.
  if [ $check = 0 ]; then
    if [ "$rev" = uncommitted ]; then
      echo "error: $root has no commit yet; commit policy/ before syncing" >&2
      exit 2
    fi
    if ! git -C "$root" diff --quiet HEAD -- policy/ ||
       [ -n "$(git -C "$root" ls-files --others --exclude-standard -- policy/)" ]; then
      echo "error: policy/ has uncommitted changes; commit them first so the" >&2
      echo "       synced copy matches revision $rev" >&2
      exit 2
    fi
  fi
  # https URL of origin, so forks link to themselves. Userinfo (which may hold
  # a token), port and a trailing .git are always dropped.
  origin=$(git -C "$root" remote get-url origin 2>/dev/null || true)
  case "$(printf '%s' "$origin" | tr 'A-Z' 'a-z')" in
    http://* | https://* | ssh://* | git://*)
      url=$(printf '%s\n' "$origin" |
        sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^/]*@##' -e 's#^\([^/:]*\):[0-9]*/#\1/#') ;;
    *@*:* | [a-zA-Z0-9]*.*:*)
      # scp-like: [user@]host:path
      url=$(printf '%s\n' "$origin" | sed -e 's#^[^@/]*@##' -e 's#:#/#') ;;
  esac
  if [ -n "$url" ]; then
    url="https://$(printf '%s\n' "$url" | sed -e 's#/*$##' -e 's#\.git$##')"
  fi
fi

block="$tmp/block"
{
  echo "$begin $rev -->"
  if [ -n "$url" ]; then
    echo "<!-- Synced from $url/blob/$rev/policy/AGENTS.md. Do not edit here; project rules go outside this block. -->"
  else
    echo "<!-- Synced from agent-practices at $rev. Do not edit here; project rules go outside this block. -->"
  fi
  echo
  # Outside fenced code: push headings down one level and link repo paths.
  awk -v url="$url" -v rev="$rev" '
    /^(```|~~~)/ { fence = !fence; print; next }
    fence { print; next }
    {
      sub(/^#/, "##")
      if (url != "") {
        out = ""; s = $0
        while (match(s, /`(roles|templates|practices|skills|policy|adapters|scripts)\/[A-Za-z0-9._\/-]*`/)) {
          path = substr(s, RSTART + 1, RLENGTH - 2)
          pre = substr(s, 1, RSTART - 1)
          kind = (path ~ /\/$/) ? "tree" : "blob"
          if (pre ~ /\[$/) out = out pre "`" path "`"          # already link text
          else out = out pre "[`" path "`](" url "/" kind "/" rev "/" path ")"
          s = substr(s, RSTART + RLENGTH)
        }
        $0 = out s
      }
      print
    }' "$policy"
  echo
  echo "$end"
} > "$block"

# Normalise for comparison: drop the stamp lines and the revision in links, so
# --check and the up-to-date test flag content drift only.
norm() {
  sed -e "/^$begin/d" -e '/^<!-- Synced from /d' \
      -e 's#/blob/[0-9a-f]\{4,\}/#/blob/REV/#g' -e 's#/tree/[0-9a-f]\{4,\}/#/tree/REV/#g' "$1"
}

status=0
for dir in "$@"; do
  if [ ! -d "$dir" ]; then
    echo "error: not a directory: $dir" >&2; status=1; continue
  fi
  file="$dir/AGENTS.md"
  cur="$tmp/cur"; new="$tmp/new"
  crlf=0
  if [ -f "$file" ]; then
    # LF copy of the file; CRLF if the first line ends in CR.
    awk 'NR == 1 && /\r$/ { print "crlf" > "/dev/stderr" } { sub(/\r$/, ""); print }' \
      "$file" > "$cur" 2> "$tmp/eol"
    [ -s "$tmp/eol" ] && crlf=1
  else
    : > "$cur"
  fi

  # Validate markers: exactly one begin line, one end line, begin before end.
  verdict=$(awk -v b="$begin" -v e="$end" '
    index($0, b) { nb++; bl = NR; if (index($0, b) != 1) bad = 1 }
    index($0, e) { ne++; el = NR; if ($0 != e) bad = 1 }
    END {
      if (nb == 0 && ne == 0) print "insert"
      else if (nb == 1 && ne == 1 && bl < el && !bad) print "replace"
      else printf "begin markers: %d, end markers: %d%s\n", nb, ne, \
        (nb == 1 && ne == 1 ? ", out of order or not on their own line" : "")
    }' "$cur")
  case "$verdict" in
    insert)
      { [ -s "$cur" ] && { cat "$cur"; echo; }; cat "$block"; } > "$new" ;;
    replace)
      awk -v b="$begin" -v e="$end" -v blk="$block" '
        index($0, b) == 1 { while ((getline l < blk) > 0) print l; skip = 1; next }
        skip && $0 == e { skip = 0; next }
        !skip' "$cur" > "$new" ;;
    *)
      echo "error: $file: malformed sync markers ($verdict); not modified" >&2
      status=1; continue ;;
  esac

  if [ -f "$file" ] && norm "$cur" > "$tmp/a" && norm "$new" > "$tmp/b" && cmp -s "$tmp/a" "$tmp/b"; then
    echo "up to date: $file"
  elif [ $check = 1 ]; then
    echo "stale: $file"; status=1
  else
    if [ $crlf = 1 ]; then
      awk '{ printf "%s\r\n", $0 }' "$new" > "$tmp/out"
    else
      cp "$new" "$tmp/out"
    fi
    cat "$tmp/out" > "$file"   # keep the file's inode and permissions
    echo "synced: $file"
  fi
done
exit $status
