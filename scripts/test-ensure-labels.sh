#!/bin/sh
# Self-test for ensure-labels.sh against a fake gh; touches no real repository.
set -eu
dir=$(mktemp -d)
mkdir "$dir/bin"
state="$dir/labels"
: > "$state"
# Fake gh: keeps "name|colour|description" lines in $state, ignores the repo.
cat > "$dir/bin/gh" <<FAKE
#!/bin/sh
case "\$1 \$2" in
  "label list") cat "$state" ;;
  "label create")
    name=\$3; shift 3
    while [ \$# -gt 0 ]; do
      case \$1 in --color) c=\$2; shift ;; --description) d=\$2; shift ;; esac
      shift
    done
    grep -v "^\$name|" "$state" > "$state.new" || true
    echo "\$name|\$c|\$d" >> "$state.new"
    mv "$state.new" "$state" ;;
  *) echo "fake gh: unexpected \$*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$dir/bin/gh"
PATH="$dir/bin:$PATH"; export PATH
if sh scripts/ensure-labels.sh --check o/r >/dev/null; then echo "check passed with no labels"; exit 1; fi
[ ! -s "$state" ]                                # --check wrote nothing
echo 'p1|000000|stale' > "$state"   # one label drifted
echo 'bug|d73a4a|Something is broken' >> "$state"     # unrelated label kept
sh scripts/ensure-labels.sh o/r >/dev/null        # create and update
grep -qxF 'p1|b60205|Blocks planned work, or risks users or data' "$state"
grep -qxF 'bug|d73a4a|Something is broken' "$state"
[ "$(wc -l < "$state")" -eq 5 ]
cp "$state" "$dir/first"
sh scripts/ensure-labels.sh o/r >/dev/null        # rerun is idempotent
cmp "$state" "$dir/first"
sh scripts/ensure-labels.sh --check o/r a/b >/dev/null
echo "ensure-labels self-test passed"
