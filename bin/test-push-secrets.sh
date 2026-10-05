#!/bin/sh
# Self-test for push-secrets against fake op, gh and curl; touches no service.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/push-secrets"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/bin" "$dir/got"
argv="$dir/argv"
: > "$argv"
# Fake op read -n op://V/ITEM/F prints secret-ITEM; item "pem" ends in a
# newline, "empty" is empty, "broken" fails.
cat > "$dir/bin/op" <<FAKE
#!/bin/sh
echo "op \$*" >> "$argv"
[ "\$1 \$2" = "read -n" ] || exit 9
[ -z "\${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || exit 8
item=\${3#op://*/}; item=\${item%%/*}
case \$item in
  pem) printf 'secret-pem\n' ;;
  empty) ;;
  broken) exit 1 ;;
  *) printf 'secret-%s' "\$item" ;;
esac
FAKE
# Fake gh secret set NAME [--env E] [--repo R]: stores stdin per name.
cat > "$dir/bin/gh" <<FAKE
#!/bin/sh
echo "gh \$*" >> "$argv"
[ "\$1 \$2" = "secret set" ] || exit 9
cat > "$dir/got/gh-\$3"
FAKE
# Fake curl: stores the fd 3 header and the body; answers \$FAKE_STATUS.
cat > "$dir/bin/curl" <<FAKE
#!/bin/sh
echo "curl \$*" >> "$argv"
cat <&3 > "$dir/got/curl-header"
cat > "$dir/got/curl-body"
printf '%s' "\${FAKE_STATUS:-200}"
FAKE
chmod +x "$dir/bin/op" "$dir/bin/gh" "$dir/bin/curl"
PATH="$dir/bin:$PATH"; export PATH
lacks() { if grep -q "$1" "$2"; then echo "$2 holds $1"; exit 1; fi; }
fails() { if "$@" >"$dir/out" 2>&1; then echo "expected failure: $*"; exit 1; fi; }
t=$(printf '\t')

cat > "$dir/m.tsv" <<EOF
# comment
render-key${t}op://ops/renderkey/credential
gh-env:staging${t}API_KEY${t}op://ops/apikey/credential
gh-repo${t}P8${t}op://ops/pem/notes plain
render-group:evg-123${t}SMTP_URL${t}op://ops/smtp item/credential
EOF

# Dry run lists destinations and names and reads nothing.
sh "$tool" --dry-run "$dir/m.tsv" > "$dir/out"
grep -qx "gh-env:staging${t}API_KEY" "$dir/out"
grep -qx "render-group:evg-123${t}SMTP_URL" "$dir/out"
[ ! -s "$argv" ]

# Real run: values go through stdin and fd 3 only, exact bytes.
OP_SERVICE_ACCOUNT_TOKEN=stray sh "$tool" --repo o/r "$dir/m.tsv" > "$dir/out" 2>&1
[ "$(cat "$dir/got/gh-API_KEY")" = secret-apikey ]
printf 'secret-pem\n' | cmp - "$dir/got/gh-P8"
[ "$(cat "$dir/got/curl-body")" = '{"value":"secret-smtp item"}' ]
grep -qx 'Authorization: Bearer secret-renderkey' "$dir/got/curl-header"
grep -q 'gh secret set API_KEY --env staging --repo o/r' "$argv"
grep -q 'env-groups/evg-123/env-vars/SMTP_URL' "$argv"
lacks secret- "$argv"
lacks secret- "$dir/out"
grep -q '3 pushed' "$dir/out"

# Filters.
rm -f "$dir/got/"*
sh "$tool" --only P8 "$dir/m.tsv" 2>/dev/null
[ -f "$dir/got/gh-P8" ] && [ ! -f "$dir/got/gh-API_KEY" ] && [ ! -f "$dir/got/curl-body" ]
rm -f "$dir/got/"*
sh "$tool" --destination gh-env:staging "$dir/m.tsv" 2>/dev/null
[ -f "$dir/got/gh-API_KEY" ] && [ ! -f "$dir/got/gh-P8" ]

# Refusals: an empty or unreadable value pushes nothing; Render errors fail.
rm -f "$dir/got/"*
printf 'gh-repo\tX\top://ops/empty/credential\n' > "$dir/bad.tsv"
fails sh "$tool" "$dir/bad.tsv"
[ ! -f "$dir/got/gh-X" ]
printf 'gh-repo\tX\top://ops/broken/credential\n' > "$dir/bad.tsv"
fails sh "$tool" "$dir/bad.tsv"
[ ! -f "$dir/got/gh-X" ]
printf 'render-group:evg-1\tX\top://ops/a/credential\n' > "$dir/bad.tsv"
fails sh "$tool" "$dir/bad.tsv"
grep -q 'needs a render-key' "$dir/out"
printf 'gh-repo X op://ops/a/credential\n' > "$dir/bad.tsv"
fails sh "$tool" "$dir/bad.tsv"
FAKE_STATUS=401 fails sh "$tool" --destination render-group:evg-123 "$dir/m.tsv"
grep -q 'Render answered 401 for SMTP_URL' "$dir/out"
lacks secret- "$dir/out"
echo "push-secrets self-test passed"
