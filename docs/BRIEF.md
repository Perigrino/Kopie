# Kopie

One sentence: a 100%-local, keyboard-first macOS clipboard manager for privacy-conscious users, evolved in place to fix its weakest points (paste reliability, capture guarantee, searchable history) while keeping the Ember look.

## Replaces

macOS's default one-shot clipboard (and leaders: Paste/Maccy/Raycast) for people who never want clipboard data leaving the Mac.

## Main jobs

1. **Capture every copy, guaranteed** — rapid-succession copies all land; multi-copy grouping; macOS 15+/26 pasteboard-prompt awareness. (Priorities chosen by the user.)
2. **Paste reliably, first time** — anti-retry paste pipeline, Secure Input detection, graceful copy-to-clipboard fallback + toast (fixes the #1 complaint across all leaders: silent paste failure).
3. **Find and reuse history fast** — OCR text of images is now *searchable* (today it is browse-only; all three leaders index it), large-history stays fast (virtualized lists, capped preview bytes).

## Data

- `Clip`: rich formats preserved (text/code/types detected, images, files, colors HEX/RGB/HSL, rich text) — existing ClipStore model, extended with OCR text index
- `Pin/Favorite`: exempt from retention, always
- `RetentionPolicy`: time-based rules, unlimited option, favorites/pins exempt

## Shape

Menu-bar-first (NSStatusItem + popover), main browsing window with sidebar + detail pane, floating hover-preview bubble kept (user decision). macOS 13+. Direct-distribution, notarized — App Store is out (CGEvent/AX requirements). Local only. No accounts, no cloud, works offline.

## System hooks

Global hotkey (⌘⇧V, rebindable), menu bar, Shortcuts/App Intents, notifications. Direct paste (⌥↩) with Accessibility permission; secure-input aware.

## Reference

None installed locally; pattern sources: Paste (two-speed UI, graceful paste fallback), Maccy (type-to-search simplicity, ignore-lists), Raycast (⌘K action panel, paste-as, multi-copy grouping). Public help pages linked in `docs/research/`.

## Look

Keep the Ember theme (accent #E9622F, existing Theme.swift) — user confirmed evolve-in-place. Add: NSPanel with `.nonactivatingPanel` replacing NSPopover; ⌘K-style per-row action panel; rebindable shortcuts with a documented cheat sheet in Settings; day headers become an optional density preference.

## Robustness & security (2.6 spine)

- Anti-retry paste: on failure re-copy then re-send ⌘V; fallback to clipboard + visible toast; Secure Input detection warns before every synthetic paste
- Capture guarantee: every changeCount change lands; skipped items surfaced in UI; rapid-succession test in acceptance script
- Security UX: migrate CommonCrypto → CryptoKit AES.GCM + Keychain; surface at-rest encryption + sensitive masking + no-cloud in the UI; SQLite FULLMUTEX/WAL, blobs outside DB; NSBackgroundActivityScheduler for retention
- Large-history: stress-test at 50k items with MB-sized clips

## Accepted gaps (not in version one)

- AI integration, iOS companion, cloud sync, Setapp
- Ground-up rewrite
