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
- Favorites, single/multi delete, Clear All with confirmation
- Retention cleanup (default 7 days; favorites protected unless you opt in) — runs on
  launch and hourly
- 5-step first-run onboarding, pause/resume/cleared notifications
- Settings: General, Clipboard, Automatic Cleanup, Privacy (ignored apps), Storage
- Main window with sidebar filters (All / Text / Images / Today / Favorites)
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
