#!/bin/sh
# Self-test for evidence-page with tiny PNG fixtures; touches no repository.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/evidence-page"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

# png FILE W H: write a valid W x H grey PNG.
png() {
  python3 - "$1" "$2" "$3" <<'PY'
import struct, sys, zlib
path, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
raw = b"".join(b"\x00" + b"\x80" * w for _ in range(h))
with open(path, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

# Fixture: Menu/empty cart before+after in en and de (light), Checkout after only.
mkdir "$dir/case"
png "$dir/case/menu--empty-cart--en--light--ios--before.png" 30 60
png "$dir/case/menu--empty-cart--en--light--ios--after.png" 30 60
png "$dir/case/menu--empty-cart--de--light--ios--after.png" 30 60
png "$dir/case/checkout--paid--en--light--ios--after.png" 40 20
manifest() {
  cat > "$dir/case/manifest.json" <<JSON
{"title": "Cart <fix>", "captured": "debug build, make shots", "changed": "button colour",
 "pr": "https://example.org/pr/1", "default": {"locale": "en", "theme": "light"},
 "shots": [
  {"screen": "Menu", "state": "empty cart", "locale": "en", "theme": "light", "platform": "ios", "version": "before", "file": "menu--empty-cart--en--light--ios--before.png", "note": "The button is blue"},
  {"screen": "Menu", "state": "empty cart", "locale": "en", "theme": "light", "platform": "ios", "file": "menu--empty-cart--en--light--ios--after.png"},
  {"screen": "Menu", "state": "empty cart", "locale": "de", "theme": "light", "platform": "ios", "file": "menu--empty-cart--de--light--ios--after.png"}
  $1
 ]}
JSON
}
checkout=', {"screen": "Checkout", "state": "paid", "locale": "en", "theme": "light", "platform": "ios", "file": "checkout--paid--en--light--ios--after.png"}'
manifest "$checkout"

out="$dir/out"
"$tool" "$dir/case/manifest.json" "$out" > "$dir/log"
grep -q '^2 sections, 4 images' "$dir/log" || fail "summary: $(cat "$dir/log")"
[ -f "$out/index.html" ] && [ -f "$out/files.json" ] || fail "outputs missing"
ok "builds index.html and files.json"
if grep -qiE '<!doctype|<html[ >]|<head[ >]|<body[ >]' "$out/index.html"; then fail "fragment has document wrappers"; fi
head -n 1 "$out/index.html" | grep -q '^<title>Cart &lt;fix&gt;</title>$' || fail "fragment does not start with an escaped <title>"
grep -q '{{' "$out/index.html" && fail "placeholder left in output"
ok "default output is a fragment starting with <title>"
for f in "$dir"/case/*.png; do cmp -s "$f" "$out/img/$(basename "$f")" || fail "not byte-identical: $f"; done
ok "images copied byte for byte"
grep -q 'class="variant pair two" data-locale="en" data-theme="light">' "$out/index.html" || fail "no visible en before/after pair"
grep -q 'class="label before">Before<' "$out/index.html" && grep -q 'class="label after">After<' "$out/index.html" \
  || fail "before/after labels missing"
ok "before/after pair present and labelled"
grep -q 'data-locale="de" data-theme="light" hidden>' "$out/index.html" || fail "de variant not hidden"
grep -q '<select name="locale">' "$out/index.html" || fail "no locale switcher"
grep -q '<select name="theme">' "$out/index.html" && fail "theme switcher with one theme"
ok "non-default locale hidden, switcher only for locale"
grep -q 'src="img/checkout--paid--en--light--ios--after.png" alt="[^"]*" loading="lazy" decoding="async" width="40" height="20"' \
  "$out/index.html" || fail "width/height missing"
grep -q '<figure class="before portrait">' "$out/index.html" || fail "portrait class missing"
ok "width and height from the PNG header"
for f in "$dir"/case/*.png; do
  b=$(basename "$f"); grep -q "\"img/$b\": \"img/$b\"" "$out/files.json" || fail "files.json lacks $b"
done
[ "$(grep -c '"img/' "$out/files.json")" -eq 4 ] || fail "files.json count"
ok "files.json lists every image"

"$tool" "$dir/case/manifest.json" "$dir/full" --full > /dev/null
head -n 1 "$dir/full/index.html" | grep -q '^<!doctype html>$' || fail "--full lacks doctype"
grep -q '<html lang="en">' "$dir/full/index.html" && grep -q '<head>' "$dir/full/index.html" \
  && grep -q 'viewport-fit=cover' "$dir/full/index.html" && grep -q '<body>' "$dir/full/index.html" || fail "--full wrappers"
ok "--full writes a standalone page"

# Re-run after removing a shot: its copy disappears.
rm "$dir/case/checkout--paid--en--light--ios--after.png"
manifest ""
"$tool" "$dir/case/manifest.json" "$out" > /dev/null
[ ! -e "$out/img/checkout--paid--en--light--ios--after.png" ] || fail "removed shot still in img/"
grep -q checkout "$out/files.json" "$out/index.html" && fail "removed shot still listed"
ok "re-run replaces the previous output"

# A foreign file in OUTDIR is refused.
touch "$out/notes.txt"
if "$tool" "$dir/case/manifest.json" "$out" 2>/dev/null >&2; then fail "accepted a non-empty OUTDIR"; fi
ok "refuses an OUTDIR with other files"

# Missing variant: Settings exists only in de, so en (the default pair) is a visible placeholder.
png "$dir/case/checkout--paid--en--light--ios--after.png" 40 20
png "$dir/case/settings--main--de--light--ios--after.png" 20 20
manifest "$checkout"', {"screen": "Settings", "state": "main", "locale": "de", "theme": "light", "platform": "ios", "file": "settings--main--de--light--ios--after.png"}'
"$tool" "$dir/case/manifest.json" "$dir/miss" > /dev/null
grep -q 'class="variant" data-locale="en" data-theme="light"><p class="muted variant-missing">Not captured in en, light.</p>' "$dir/miss/index.html" \
  || fail "default-pair placeholder missing or hidden"
grep -q 'class="variant" data-locale="de" data-theme="light" hidden><p class="muted variant-missing">' "$dir/miss/index.html" \
  || fail "hidden placeholder for the checkout de row missing"
ok "missing variants get a placeholder; default pair is visible"
rm "$dir/case/settings--main--de--light--ios--after.png" "$dir/case/checkout--paid--en--light--ios--after.png"

# Placeholder text in the manifest is not expanded.
manifest ""
sed 's/"changed": "button colour"/"changed": "{{INTRO}} {{SECTIONS}}"/' "$dir/case/manifest.json" > "$dir/m" && mv "$dir/m" "$dir/case/manifest.json"
"$tool" "$dir/case/manifest.json" "$dir/once" > /dev/null
[ "$(grep -c '{{INTRO}}' "$dir/once/index.html")" -eq 1 ] || fail "manifest text was expanded"
ok "placeholders substituted in one pass"

# A truncated JPEG builds, with no width/height.
printf '\377\330\377\300\000\021\010' > "$dir/case/menu--empty-cart--en--light--ios--after.png"
"$tool" "$dir/case/manifest.json" "$dir/trunc" > /dev/null || fail "truncated image raised"
png "$dir/case/menu--empty-cart--en--light--ios--after.png" 30 60
ok "truncated image does not crash"

# Removing a shot lists its path in removed.json; a first run lists none.
[ "$(tr -d ' \n' < "$dir/once/removed.json")" = "[]" ] || fail "first run removed.json not empty"
png "$dir/case/gone--x--en--light--ios--after.png" 10 10
manifest ', {"screen": "Gone", "state": "x", "locale": "en", "theme": "light", "platform": "ios", "file": "gone--x--en--light--ios--after.png"}'
"$tool" "$dir/case/manifest.json" "$dir/rm" > /dev/null
rm "$dir/case/gone--x--en--light--ios--after.png"
manifest ""
"$tool" "$dir/case/manifest.json" "$dir/rm" > "$dir/log"
grep -q '^removed: 1$' "$dir/log" || fail "removed count not printed"
grep -q '"img/gone--x--en--light--ios--after.png"' "$dir/rm/removed.json" || fail "removed.json lacks the dropped shot"
ok "removed.json lists dropped shots"

# expect_fail MESSAGE: the run exits 2 and stderr contains MESSAGE.
expect_fail() {
  rm -rf "$dir/bad"
  set +e; "$tool" "$dir/case/manifest.json" "$dir/bad" >/dev/null 2>"$dir/err"; got=$?; set -e
  [ "$got" -eq 2 ] || fail "exit $got, want 2 for: $1"
  grep -qF "$1" "$dir/err" || fail "want '$1', got: $(cat "$dir/err")"
  [ ! -e "$dir/bad" ] || fail "output written on failure: $1"
  ok "fails: $1"
}
png "$dir/case/menu--wrong--en--light--ios--after.png" 10 10
manifest ', {"screen": "Menu", "state": "empty cart", "locale": "en", "theme": "light", "platform": "android", "file": "menu--wrong--en--light--ios--after.png"}'
expect_fail 'file name must be menu--empty-cart--en--light--android--after'
manifest ""
expect_fail 'stale or unlisted capture: menu--wrong--en--light--ios--after.png'
rm "$dir/case/menu--wrong--en--light--ios--after.png"
manifest "$checkout"
expect_fail 'missing file'
manifest ', {"screen": "Menu", "state": "empty cart", "locale": "en", "theme": "light", "platform": "ios", "file": "menu--empty-cart--en--light--ios--after.png"}'
expect_fail 'duplicate of an earlier shot'
manifest ""
sed 's#"https://example.org/pr/1"#"javascript:alert(1)"#' "$dir/case/manifest.json" > "$dir/m" && mv "$dir/m" "$dir/case/manifest.json"
expect_fail 'pr must be a URL starting with http'
png "$dir/case/---mn--en--light--ios--after.png" 10 10
manifest ', {"screen": "Меню", "state": "x", "locale": "en", "theme": "light", "platform": "ios", "file": "---mn--en--light--ios--after.png"}'
expect_fail 'use Latin letters or digits in screen and state'
rm "$dir/case/---mn--en--light--ios--after.png"
manifest ""
sed 's/"locale": "en", "theme": "light"}/"locale": "fr", "theme": "light"}/' "$dir/case/manifest.json" > "$dir/m" && mv "$dir/m" "$dir/case/manifest.json"
expect_fail "default locale 'fr' is not in any shot"
echo "PASS evidence-page self-test"
