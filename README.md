# Kopie

Native macOS clipboard manager — menu-bar first, fast, **local-only**.
Everything you copy, available when you need it.

Spec: `docs/superpowers/specs/2026-08-16-kopie-design.md`
Plan: `docs/superpowers/plans/2026-08-16-kopie.md`

## Requirements
- **macOS 13 Ventura** or later

## What's new in 2.2

Everything below shipped in the 2.2.0 release. All existing behaviour is unchanged; every
new feature is off-path unless you use it.

**Capture & search**

1. **OCR image search** — text inside copied images/screenshots is recognized at capture
   time with Apple's Vision framework, stored in a new `ocr_text` column (with automatic
   migration of existing databases), and folded into the encrypted search index. Typing a
   word now finds the screenshot that contains it. On-device only; toggle in
   Settings → Clipboard.
2. **Search matches OCR text** — short queries (under 3 characters, where the trigram
   index doesn't apply) also fall back to matching the recognized image text directly.

**Pasting**

3. **Direct paste** — with the popover open, `⌥↩` or `⌥-click` a row copies it and
   simulates `⌘V` in the app you came from; `⌥1`–`⌥9` quick-select and paste the nth
   item. Uses one Accessibility permission, requested with a prompt that opens System
   Settings; without it, copies stage on the clipboard exactly as before.
4. **Paste as plain text** — hold `⌃` while copying (any popover copy path) to strip
   RTF/HTML and stage only unstyled text; right-click → "Copy as Plain Text" does the
   same one item at a time; a Settings → General toggle makes plain-text the default for
   every copy.
5. **Sequential paste queue** — right-click items → "Add to Paste Queue", then paste them
   one-by-one in order via the status menu's "Paste Next (N queued)" or the
   "Paste Next From Queue" intent. The queue persists across relaunches, skips items
   deleted meanwhile, caps at 50, and can be cleared from the status menu.

**Shortcuts & automation**

6. **App Intents** — "Get Latest Clipboard Item" (returns newest item text),
   "Search Clipboard History" (query + limit parameters, uses the encrypted search index)
   and "Paste Next From Queue" are callable from the Shortcuts app, Spotlight and Siri
   phrases. App Intents metadata is compiled into the bundle at build time.

**Interface**

7. **Side preview panel** — hovering (or arrow-keying to) an image or rich-text row opens
   a full-height panel docked to the left of the popover, completely outside the list:
   full-resolution image or rendered rich text, scrollable while you keep the cursor on
   it; the popover widens to fit and narrows when it closes.
8. **Dark code-block viewer** — the Formatted tab now renders as a GitHub-style dark code
   card in both appearances: near-black surface, dim line-number gutter, Dark+ syntax
   colours, language glyph badge, line count and a Copy button.
9. **Rich text fixed everywhere** — rich items render their real formatting under both
   the Plain and Formatted tabs (previously they could appear blank); a plain-text
   fallback with a visible notice replaces any payload that fails to parse. Rich files
   are stored encrypted as before.
10. **Popover search field redesigned** — fixed-height field with the placeholder
    correctly centred against the magnifier icon, accent focus ring, hover-clear button.
11. **Menu-bar quick actions** — right-clicking the status icon offers Pause/Resume
    Monitoring and Clear History… (with the typed-confirmation dialog) in addition to
    Open/Settings/Appearance/Quit.
12. **Inline editing** — the details panel has an Edit action (⌘E): fix a typo and save;
    the item re-hashes (re-copying the edited text dedupes instead of duplicating) and
    its search index is rebuilt. Rich items keep their RTF/HTML while you edit the plain
    text.
13. **Drag & drop out of Kopie** — drag any row out of the popover or main window: text
    drags as text, images as a bitmap, file references as paths.
14. **No stray windows at launch** — a launch-time bug that presented an empty
    "Kopie Settings" window on every startup was fixed, and a permanent smoke probe
    (`--smoke-windows`, wired into `scripts/acceptance.sh`) now fails acceptance if any
    unexpected window is visible at launch.

**Under the hood**

15. Settings keys gained type-healing and the queue/plain-text keys; the headless smoke
    suite covers the rich-text round-trip, side preview renders, window launch hygiene
    and the OCR pipeline (142 unit tests, up from 130 at 2.1.1).

## Features
- Captures text and images copied anywhere on your Mac (menu-bar icon, `doc.on.clipboard`)
- Live search + day-grouped history (Today / Yesterday / Older) with image thumbnails
- Copy-back to the clipboard (`⌘⇧V` global hotkey by default, reassignable in Settings)
- **Direct paste** — with the popover open, `⌥↩` or `⌥-click` copies an item and immediately
  pastes it into the app you were in; `⌥1`–`⌥9` quick-select the nth item. Needs the macOS
  Accessibility permission (Kopie offers to open System Settings the first time; without it,
  items are staged on the clipboard as usual)
- **OCR search** — text in captured images is recognized entirely on-device (Vision), so
  screenshots are findable by the words inside them (toggle in Settings → Clipboard)
- **Paste as plain text** — hold `⌃` while copying in the popover (or the context-menu
  "Copy as Plain Text" action) to stage the text without its rich formatting; a Settings
  → General toggle makes this the default for every copy
- **Drag & drop out of Kopie** — drag text, images (bitmap), or file references straight
  from the history into any app
- Favorites, single/multi delete, Clear All with confirmation
- Retention cleanup (default 7 days; favorites protected unless you opt in) — runs on
  launch and hourly
- 5-step first-run onboarding, pause/resume/cleared notifications
- Settings: General, Clipboard, Automatic Cleanup, Privacy (ignored apps), Storage
- Main window with sidebar filters (All / Text / Images / Today / Favorites); status-menu
  quick actions (Pause/Resume, Clear History…)
- **Formatted viewer** — the "Formatted" tab auto-detects the language of any copied text
  (JSON, HTML, SQL, Swift, Python, etc.), safely pretty-prints JSON, applies syntax
  highlighting that adapts to light/dark mode, and renders a developer card with a
  language badge, line numbers, a copy button, and wrapping that stays responsive to
  the panel width
- **Rich text support** — HTML/RTF content (bold, italic, colour, links) is captured and
  rendered readably, with colours normalised for legibility
- **Inline editing** — fix a typo in the details panel (⌘E); edits re-save the item and
  re-index it, and re-copying the edited text never creates a duplicate
- **Paste queue** — right-click items → "Add to Paste Queue", then paste them one-by-one
  in order (status menu "Paste Next", or Shortcuts); the queue survives relaunches
- **Shortcuts & Siri** — App Intents: "Get Latest Clipboard Item", "Search Clipboard
  History" (query + limit parameters), and "Paste Next From Queue" work in the Shortcuts
  app, Spotlight, and Siri phrases
- **Your clipboard stays on your Mac. Kopie does not upload or share your clipboard history.**

## Commands
```bash
swift test        # core engine unit tests (or: npm test)
npm run dev       # debug build + assemble + open Kopie.app
npm run build     # release build (dist/Kopie.app)
npm run package   # release build + dist/Kopie.dmg
bash scripts/acceptance.sh   # headless full workflow (text + image)
```

## Headless smoke / engine checks
```bash
export KOPIE_STORAGE_DIR="$(mktemp -d)"
K=./dist/Kopie.app/Contents/MacOS/Kopie
$K --smoke-capture "hello"     # -> ID <n>
$K --smoke-list
$K --smoke-restore 1
$K --smoke-readboard
$K --smoke-purge 7
$K --smoke-count
unset KOPIE_STORAGE_DIR
```

## Signing / distribution
Ad-hoc signed by default. To Developer-ID sign, set `KOPIE_SIGN_IDENTITY`
(e.g. "Developer ID Application: You (TEAMID)") before `npm run package`.

> **Your clipboard stays on your Mac. Kopie does not upload or share your clipboard history.**
