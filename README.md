# Kopie

Native macOS clipboard manager — menu-bar first, fast, **local-only**.
Everything you copy, available when you need it.

Spec: `docs/superpowers/specs/2026-08-16-kopie-design.md`
Plan: `docs/superpowers/plans/2026-08-16-kopie.md`

## Requirements
- **macOS 13 Ventura** or later

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
