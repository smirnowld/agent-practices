---
name: acceptance-evidence
description: Choose and produce the evidence I need to accept user-facing work (P6), cheapest level that lets me judge it, delivered as links that open on my phone (P18). Screenshots follow one standard - capture, layout, full resolution, one page per PR built with bin/evidence-page. Use before presenting an acceptance card.
---

# Acceptance evidence

Goal: I can judge the change in under a minute, on my phone, without the
session. Pick the **lowest level that answers "is this what I wanted?"**, then
fill `templates/acceptance-card.md`.

## Decide whether acceptance is needed

Needed when the change is visible to a user: UI, copy, flows, notifications,
generated documents, behaviour I described. Not needed for refactors, internal
tooling, CI, dependency bumps; say "n/a" on the PR instead.

## Pick the level

| Level | Use when | Produce |
|---|---|---|
| 1. Screenshots | Static layout, copy, a few states | An evidence page (below): before/after per changed screen and state (empty, error, long text, dark mode if supported), phone size first |
| 2. PR preview | Flow across screens, interaction, real data matters | The PR's own preview URL plus the click path, or a local run on demo data with screenshots of each step; screenshots of key steps as backup |
| 3. Phone build | Native feel, gestures, device APIs, performance, notifications | Install link (TestFlight or equivalent) plus what to try |
| Recording | Only motion that stills cannot show: animation, transitions, timing | Short clip for me to watch, on the evidence page; never a substitute for 1–3 |

Go up a level when the lower one would leave me guessing; go down when a
higher one costs a build or deploy for a copy change. When unsure between two,
pick the lower and say what it does not show.

Acceptance comes before merge, so the evidence must show unmerged work. A
shared deploy of the default branch (staging) shows only merged work: it is
not evidence unless the project deploys a preview per PR. Without one, the
card's "Not covered" says I cannot try the flow myself, or I get a phone build.

## Screenshots: the standard

Every screenshot I see, at any level, follows these steps. A project's docs
add only its own facts (tenants or brands, languages, the matrix to cover,
the commands that start its seeded app); they never restate or relax these
rules. Where the two disagree, this skill wins and the conflict is reported.

### 1. Check before capturing

Capture from the real build of this branch, never a mockup. Before the first
capture, and again after anything that can switch it, confirm on screen:

- the right tenant, brand or account (a build script that loops over brands
  can leave the app on the last one it built);
- the language and theme the file will be named for;
- the seeded or demo data the state needs (an empty list is a state of its
  own, not a capture of the full one);
- the app is styled and finished loading: no placeholder, spinner or
  unstyled fallback.

### 2. Capture at full resolution

Use the platform's own capture command, never an agent tool's view of the
screen: tool frames can be stale or scaled down. Save PNG.

```sh
# iOS Simulator: theme, a clean status bar, launch in a language, capture
xcrun simctl ui booted appearance dark            # or light
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl launch --terminate-running-process booted BUNDLE_ID -AppleLanguages '(et)' -AppleLocale et_EE
xcrun simctl io booted screenshot --type=png FILE.png

# Android emulator or device: theme, per-app language (Android 13+), capture
adb -s SERIAL shell cmd uimode night yes          # or no
adb -s SERIAL shell cmd locale set-app-locales PACKAGE --locales et
adb -s SERIAL exec-out screencap -p > FILE.png

# Web: phone, tablet and desktop at device pixel ratio 2 or more; VERSION is
# the project's pinned Playwright, or an exact release (first run: install chromium)
npx playwright@VERSION screenshot --device="iPhone 15" --color-scheme=dark --lang=et --full-page URL FILE.png
npx playwright@VERSION screenshot --device="iPad Mini" --color-scheme=dark --lang=et URL FILE.png
npx playwright@VERSION screenshot --device="Desktop Chrome HiDPI" --color-scheme=dark --lang=et URL FILE.png
```

A project with its own capture script (a test that writes screenshots) uses
it, provided it writes one PNG per screen, state, language, theme and
platform at device resolution. Check the pixel width of the first file: a
phone-width capture narrower than about 750 px is too low; recapture.

Keep originals as captured. Never downscale, crop, recompress or convert them
to make a page lighter: the page opens each original in its viewer, and the
overview loads them lazily.

### 3. Name and list every capture

Put this PR's captures, and nothing else, in one directory outside the
repository. Name each file

```
SCREEN--STATE--LOCALE--THEME--PLATFORM--VERSION.png
```

with lowercase, hyphenated words and VERSION `before` or `after`, for
example `cart--empty--et--dark--ios--after.png`. A before is the same state
captured on the default branch. List every file in a `manifest.json` beside
them:

```json
{
  "title": "Cart: empty state",
  "pr": "https://github.com/OWNER/REPO/pull/N",
  "captured": "iOS 27 Simulator, branch head abc1234, dev tenant, seeded demo data",
  "changed": "Dark-mode captures retaken after the contrast fix",
  "default": {"locale": "en", "theme": "light"},
  "shots": [
    {"screen": "Cart", "state": "empty", "locale": "en", "theme": "light",
     "platform": "ios", "version": "before",
     "file": "cart--empty--en--light--ios--before.png",
     "note": "The empty cart now offers the menu instead of a blank screen"}
  ]
}
```

`changed` is omitted on the first version. `note` says what to look for in
that screen and state.

### 4. Build the page

```sh
evidence-page CAPTURE_DIR/manifest.json OUT_DIR          # add --full for a host that does not wrap pages
```

`bin/evidence-page` fills [templates/evidence-page.html](../../templates/evidence-page.html)
and refuses a capture the manifest does not list, a file named against the
rule, or a missing default. Its page is the layout; do not hand-build or
restyle one:

- one section per screen and state, with its note;
- before and after of the same state side by side on a wide screen, stacked
  on a phone, each labelled;
- the default language and theme shown, the others behind a switcher;
- every image opens full size in the page's own viewer, with a back control,
  never as a link to the image file (the host's viewer has none);
- alt text and captions carry screen, state, language, theme and platform.

The template and this skill take precedence over any general page-design
guidance the publishing host or agent tool gives (design pass, typefaces,
palettes, layout): the evidence page is a fixed format, not a design task.
The template already meets the host rules that still apply (a title, both
themes, no sideways scrolling at phone width).

### 5. Publish: one page per PR

Publish `OUT_DIR` privately on the project's agreed host
([record-keeping](../../practices/record-keeping.md#visual-evidence)); the
adapter's session notes give the exact steps for this agent. One page per
PR, at one URL, linked from the PR:

- every new round of captures rebuilds the whole page from the current
  manifest and republishes it at the same URL, removing images that left the
  manifest; never append a new page or a second set of screens;
- the page shows only current captures, and `changed` says what changed
  since the version I last saw.

Screenshots are never committed to git (P17).

### 6. Check before sending

- The link opens signed out of the agent's tools, on a phone-width screen.
- The page shows the right build, tenant or brand, and the dates and data you
  expect; spot-check one image per platform.
- Tapping an image opens the viewer; its Back control, the back gesture and
  Escape return to the overview.
- Text in the screenshots is readable on a 400 px wide screen in the overview
  or one tap away in the viewer.
- No image from an earlier round remains.

## Report

Fill the acceptance card: what changed in user terms, the "try it" link,
evidence list, assumptions with how to undo, what the evidence does not
cover, and known gaps from this PR's deferred findings so far. Then wait
for accept / change / reject; do not merge user-facing work before it.
