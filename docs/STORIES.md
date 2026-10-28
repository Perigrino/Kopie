# Stories

Kopie 2.6 — evolve in place. Built from `docs/BRIEF.md` + `docs/research/*.md` (2026-10-28).
Acceptance tags: `[snap]` snapshot, `[self]` in-app SelfTest/acceptance script, `[unit]` KopieCoreTests, `[manual]` a person must try it.
Statuses: todo (2.6 back-office). done = the automated ([unit]/[self]/[snap]) bits are covered; [manual] bits stay open until a human runs them. 2.5.0 core behavior is the baseline; these stories change/extend it.

## M1 Paste reliability

### S-001 Warn instead of failing when Secure Input is active (paste reliability)
As the user, when Secure Input is active (login field focused), I press ⌥↩ and Kopie skips the synthetic paste and shows a one-line hint instead of silently failing.
Screens: popover.png, toast.png
Status: done — [manual] login-window/password-field bit open
Acceptance:
- [self] With a secure-text field focused (known target in SelfTest), direct paste is aborted, no synthetic event is posted, hint is shown.
- [unit] `CGEventSource.secureInputEnabled()` result gates the paste path deterministically in PasteDirectService.
- [manual] On the macOS login window and a password field, no event leaks; hint appears after returning to doc apps.
UX:
- Flow: ⌥↩ with Secure Input active → paste stops before the event is posted → toast explains + says the clip is on the clipboard → fades after 6 s; Escape dismisses; pasteboard unchanged
- Surface: toast at the popover edge (information needing no action — never an alert)
- States: path only fires on failure (normal paste has no toast); toast words stand by even if the popover is closed, shown on next open
- Words: toast "Kopie can't paste while a password field is active. The clip is on your clipboard."; VoiceOver reads the toast verbatim
- Access: Escape dismisses; text ≥ 10 pt; meaning carried by words, not color

### S-002 Anti-retry paste survives hostile targets (paste reliability)
As the user, pasting into apps that reject or swallow synthetic events (Electron, terminal, VM) still pastes: Kopie retries once (re-copy + re-send ⌘V), then falls back.
Screens: main.png, toast.png
Depends: S-001
Status: done — paste matrix + [manual] VM bit open
Acceptance:
- [self] Acceptance paste matrix against Electron app, Terminal, Parallels VM target, TextEdit: each ends pasted or visibly faded-back within a time budget (no silent failure).
- [unit] Retry state machine: exactly one retry per paste op; post-retry failure escalates to fallback (S-003), logs captured.
- [manual] Paste into Java app in a VM looks correct.

### S-003 Graceful fallback to clipboard + toast, never silent (paste reliability)
As the user, when direct paste is impossible (Accessibility revoked, target refused twice), the item lands on the pasteboard and a toast explains what happened.
Screens: toast.png, settings-privacy.png
Depends: S-002
Status: done — [snap] toast visual unchecked
Acceptance:
- [snap] Toast copy shows target-app name and what happened (no internal jargon).
- [self] With Accessibility off, ⌥↩ results in clipboard set + toast shown, no crash, no dialog spam (toast once per session per reason).
- [unit] Fallback decision function covers: ax-missing, target-refused, secure-input; each maps to a distinct toast copy.
UX:
- Flow: ⌥↩ fails → one Retry (S-002) fails → clip copied to clipboard → toast "Unable to paste into Safari. The clip is on your clipboard." with buttons "Open Settings…" and "Dismiss" → fades after 8 s; Escape dismisses
- Surface: toast (inline, non-modal)
- States: one toast per session per reason (no spam); retry takes < 400 ms so no loading state; done feedback = the toast itself
- Words: "Open Settings…", "Dismiss"; the error names the app and what happened, no blame; buttons Title case, messages Sentence case
- Access: VoiceOver announces the toast; Return opens Settings, Escape dismisses

### S-004 Rebindable modifiers + hotspot conflict detection (paste reliability)
As the user, I rebind every paste modifier (paste / paste-as-plain / direct paste) and the global hotkey, and Kopie detects conflicts with known system/app shortcuts before saving.
Screens: settings-hotkeys.png, cheat-sheet.png
Status: open — [unit] done; [self] round-trip needs a human; [snap] cheat sheet deferred to S-053
Acceptance:
- [self] Recorder round-trip: record new binding → saved → fires → restored default works.
- [unit] Conflict check rejects bindings already taken by a registered binding (no silent override).
- [snap] Cheat sheet page lists all shortcuts (regenerated at runtime, not hardcoded).
UX:
- Flow: Settings > Hotkeys → click binding row → press new combo → conflict check → "Set Shortcut" saves or inline error → "Revert" restores; Cheat sheet tab → "Export…" writes Markdown
- Surface: Settings sidebar page (a place people return to); conflict is an inline error, never an alert
- States: error "This shortcut is already used by Paste as plain." under the row; empty recorder state "Press a key combination"; no loading state (instant)
- Words: "Set Shortcut", "Revert", "Export…"; Escape cancels recording, ⌘Z reverts a save
- Access: recorder reachable by keyboard; VoiceOver "Record shortcut for Direct paste"

## M2 Capture guarantee

### S-010 Rapid-succession copies all land (capture guarantee)
As the user, I copy 10 items 300 ms apart; every one appears in history in order.
Screens: popover.png
Status: todo
Acceptance:
- [unit] Synthetic poll harness (sub-second intervals, byte-heavy clips) captures all, order preserved.
- [self] acceptance.sh rapid-capture scenario: 50 copies ≤500 ms apart, 100% landed.
- [unit] changeCount jumps (>1 delta) don't silently drop intermediate items or spam reads.

### S-011 Own writes filtered (capture guarantee)
As the user, items Kopie itself writes during paste-back are never re-captured as new history.
Screens: popover.png
Depends: S-010
Status: todo
Acceptance:
- [unit] Paste-back write → poll returns no new capture (own last-written count honored).
- [self] Full capture⇨paste⇨capture cycle leaves history count unchanged for the same content.

### S-012 Skipped/odd capture is surfaced, never swallowed (capture guarantee)
As the user, if a poll tick reads an unusable changeCount delta, history shows a small "missed copies" badge, and reopening the popover reconciles it.
Screens: popover.png, main.png
Depends: S-010
Status: todo
Acceptance:
- [self] Force an injected read failure: badge appears, no historical data lost after reconcile.
- [snap] Badge row visual on popover.
- [unit] Reconcile function repairs the state from the actual pasteboard on next poll, tests cover reconcile-after-skip.

### S-013 macOS 15+/26 pasteboard-prompt awareness (capture guarantee)
As the user, on macOS 15+/26 I am never surprised by periodic "app read the clipboard" prompts: reads are tied to hotkey/popover activation and user-consistent state.
Screens: settings-privacy.png
Status: todo
Acceptance:
- [manual] On a macOS 15+/26 machine, run an hour of normal use with a logged prompt-counter: 0 unexpected prompts.
- [self] Under high-activity simulation, read cadence honors the activation-tied design (documented rule encoded in tests).
- [unit] Poll loop never reads unless a session interaction occurred within the last N seconds, or the user opted the app in.

### S-014 Multi-copy grouping (capture guarantee + differentiator)
As the user, rapid multi-copies group into one entry with sub-items, expandable in the detail pane; default off in settings, until proven useful.
Screens: main.png, action-panel.png
Depends: S-010
Status: todo
Acceptance:
- [snap] Grouped row renders with count badge and subgroup child rows.
- [unit] Grouping rule (time window, same-source app) merges/factors correctly, including pinned exemption.
- [self] Toggle grouping on/off in settings, history renders both ways with no data loss.

## M3 OCR-as-search

### S-020 OCR text indexed on capture
As the user, text in images I copy is searchable from the search fields immediately after capture.
Screens: main.png, popover.png
Status: todo
Acceptance:
- [unit] Known-text image captured → search term returns item; missed indexing impossible (OCR synchronous enough or queued with integration completeness check).
- [self] 20-image fixture batch: index ≥19 with accurate text within a bounded total time.
- [self] OCR runs at .userInitiated on a serial queue, never backpressure on the poll loop (measured in SelfTest).

### S-021 OCR backfill for existing history
As the user, existing image history items become searchable after a one-time background backfill I can watch progress for.
Screens: main.png, settings-storage.png
Depends: S-020
Status: todo
Acceptance:
- [self] 1,000-image synthetic corpus backfills on a background scheduler, progress indicator reflects real count.
- [unit] Backfill is idempotent and resumable after app restart.
- [manual] Real screenshot repo completes under 10 minutes with UI responsive.

### S-022 Copy OCR text as an action
As the user, I copy exactly the recognized text of an image from the detail or action panel without opening the image first.
Screens: action-panel.png, main-detail.png
Depends: S-020
Status: todo
Acceptance:
- [snap] Action row "Copy Text" present for image items with non-empty OCR index.
- [self] Copy-OCR from the action panel places image's OCR text on the pasteboard.
- [manual] Non-English screenshot (e.g., Chinese) pastes correctly from OCR copy.

## M4 Security UX

### S-030 At-rest encryption migrates to CryptoKit AES.GCM + Keychain
As the user, my local history file benefits from authenticated-encryption, and the common-crypto legacy DB migrates untouched on the first 2.6 launch.
Screens: settings-security.png, settings-storage.png
Status: todo
Acceptance:
- [unit] Migration function moves a fixture legacy DB → new AES.GCM store and reads back exact original rows (round-trip, no data loss).
- [unit] Key is stored Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never in DB or defaults.
- [self] First-launch migration runs once (idempotent on relaunch); log-free of plaintext payloads.

### S-031 Storage stores engine-correct SQLite (FULLMUTEX, WAL, blobs outside DB)
As the user, the DB stays consistent under concurrent UI+polling access and keeps large image blobs out of the page cache.
Screens: settings-storage.png
Depends: S-030
Status: todo
Acceptance:
- [unit] `sqlite3_open_v2(SQLITE_OPEN_FULLMUTEX)` + `PRAGMA journal_mode=WAL` set at open; verify both flags in test.
- [unit] Blob-over-threshold rows are written outside the DB; placeholder reads resolve round-trip.
- [self] Concurrent multi-writer stress (3 threads) finishes with DB readable and consistent.

### S-032 Security surface visible in UI
As the user, the Settings Security page states plainly: encryption enabled or not, sensitive mask count, retention heartbeat, and no cloud — I never wonder where the data is.
Screens: settings-security.png
Depends: S-030, S-031
Status: todo
Acceptance:
- [snap] Settings Security page shows: encryption row, masked-item count, retention status, "no cloud storage" fact.
- [unit] Counts pulled from live state (encryption state, masked count), not static labels.
- [manual] Privacy reviewer can point to where data lives from the UI alone.

### S-033 Retention via NSBackgroundActivityScheduler; pins/favorites exempt
As the user, retention expiry happens through the correct system scheduler, and favorites/pinned items never expire.
Screens: settings-cleanup.png
Depends: S-031
Status: todo
Acceptance:
- [unit] Retention job scheduled via NSBackgroundActivityScheduler (no ad-hoc timers); cleanup respects favorite/pin exemption rules.
- [self] Force retention early: old items removed, favorites/pins survive, count metadata refreshed.
- [manual] Watch a session where retention runs while the Mac is busy: no foreground hitch, no pop-in deletion of favorites.

## M5 Large-history speed

### S-040 50k-item stress stays responsive
As the user, a history of 50k items (covering MB-sized images and text) opens and scrolls without freezing; previews lazy-load; search results stay instant.
Screens: popover.png, main.png
Status: todo
Acceptance:
- [self] Fixture: 50k synthetic items, ≥12 MB total; open main window under an agreed latency budget, scroll 5 screens without stalls; monitor RSS stays under 1.5 GB.
- [unit] Preview bytes capped at a constant; result fetch uses paged queries (no full-table load).
- [self] SelfTest reports the timings as pass/regression.

### S-041 Popover instant (⌘⇧V → visible under 120 ms)
As the user, the popover with a 10–50k history opens before my finger leaves the hotkey.
Screens: popover.png
Depends: S-040
Status: todo
Acceptance:
- [self] Hotkey⇨visible time measured across 20 repeats ≤120 ms median, ≤180 ms p95.
- [unit] List loads first screen of results only; further paging is lazy.
- [manual] On the tester's real archive, popover never "blinks" or waits visible blank.

### S-042 Search tested under stress
As the user, search with accents, CJK, fuzzy-like fragments, and OCR-indexed text under a big archive returns results within budgets.
Screens: main.png
Depends: S-020, S-040
Status: todo
Acceptance:
- [self] Search across 50k items stays inside the latency budget in 95% of 50 queries.
- [unit] CJK and accented queries hit expected fixtures (Maccy/Accra validation from research).
- [manual] Roman fottest: search "receipt" finds a screenshot whose pixels render that word.

## M6 UI polish

### S-050 Popover base becomes NSPanel (nonactivating) — keep hover bubble
As the user, typing into the popover never loses focus, hover bubble remains (kept by user decision), and panel chrome works on Liquid Glass,
Screens: popover.png, hover-bubble.png
Status: todo
Acceptance:
- [self] SelfTest --smoke-windows passes: popover + hover bubble + preview bubble all focusable/searchable.
- [snap] Popover page visual on light and dark, macOS 26 included as test matrix [manual sight].
- [unit] `.nonactivatingPanel`, `level = .statusBar`, `becomesKeyOnlyIfNeeded` verified by inspecting panel config in tests.

### S-051 ⌘K action panel
As the user, pressing ⌘K (per-row) gives an action sheet: pin/unpin, favorite, edit, delete, copy OCR text, save-as-snippet; keyboard only.
Screens: action-panel.png, main-detail.png
Depends: S-022
Status: todo
Acceptance:
- [snap] Action panel keyed correctly with live row context.
- [self] Keyboard-only flow: focus row → ⌘K → arrow to action → Return applies and panel dismisses.
- [unit] Each action routes to the exact underlying AppState call; no duplicates or dead entries.

### S-052 Day headers become an optional density preference
As the user, I can turn day grouping on or off; both layouts are first-class.
Screens: main.png, popover.png
Status: todo
Acceptance:
- [snap] Sidebar main and popover both render clean without day headers by default.
- [self] Density pref toggles day headers on and off; both layouts persist across restart.
- [unit] Grouping renderer handles calendar boundary items consistently in both modes.

### S-053 Shortcut cheat sheet lives in Settings
As the user, Settings exposes a live-generated, complete list of current shortcuts (mirrors S-004 rebindings), with a reproducible export to Markdown.
Screens: cheat-sheet.png
Depends: S-004
Status: todo
Acceptance:
- [snap] Cheat sheet page renders every binding (no omission versus runtime registry).
- [self] Export button writes a Markdown file with all bindings; content matches runtime bindings.
- [unit] Registry is the single source of truth; cheat sheet reads from it (no second list to maintain).

### S-054 Pause capture always one interaction away
As the user, I can pause/resume capture from the menu bar popover footer (and ⌥-click the status item), with the paused state obvious everywhere.
Screens: popover.png
Status: todo
Acceptance:
- [self] Pause from popover footer → no captures land → resume → captures resume; state shown on popover footer and status item glyph.
- [snap] Paused state visual on popover footer.
- [unit] Paused state check gates the poll loop before any pasteboard read.

### S-055 Ignore list reaches every leader's baseline
As the user, I ignore whole apps, single copies ("ignore next copy"), and pasteboard types (transient, concealed, password-manager flags), and sensitive items are masked regardless.
Screens: settings-privacy.png, popover.png
Depends: S-054
Status: todo
Acceptance:
- [unit] Ignore rules for transient/concealed/password-manager pasteboard types evaluated at capture time, before storage.
- [self] Copy from an ignored app, use "ignore next copy", and copy a 1Password-type item: none appear in history.
- [snap] Ignore list editor in Settings shows rules with remove buttons.

## Dropped

- AI integration (not in 2.6; accepted gap)
- iOS companion (accepted gap)
- Cloud sync (accepted gap — local-only, trust-first)
- Setapp distribution (accepted gap)
- Ground-up rewrite (rejected; evolve in place)
- Dropping the hover-preview bubble (kept by user decision)

## Later

- [U] Multi-device sync of favorites only, if iCloud Keychain-style opt-in proves safe
- [U] QR/OCR decode actions beyond image search
- [U] Shared/community pinboards
