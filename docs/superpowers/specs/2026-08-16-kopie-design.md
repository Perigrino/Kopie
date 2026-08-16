# Kopie — Design Spec

**Native macOS clipboard manager. Menu-bar first. Local-only. Production quality.**

- Date: 2026-08-16
- Status: Approved (design) — pending written-spec review
- Product name: **Kopie**
- Tagline: *Everything you copy, available when you need it.*

---

## 1. Product Overview

Kopie is a privacy-first macOS clipboard history app. It runs quietly in the menu bar,
captures clipboard content (text and images) in the background, and keeps a fast,
searchable local history the user can restore to the clipboard with one keystroke
(`⌘⇧V` by default).

### Priorities (ranked)
1. Clipboard reliability (never miss a copy, never crash, never self-duplicate)
2. Fast retrieval (instant search, responsive popover)
3. Privacy (100% local, no upload/telemetry/analytics)
4. Native macOS experience
5. Low resource usage
6. Clean, restrained visual design (Mobile/iOS design discipline, implemented natively)
7. Reliable persistence across app + Mac restarts
8. Simple `.dmg` distribution

### Non-goals / Out of scope
- Any network/cloud sync, upload, telemetry, or analytics.
- Sharing/remote paste, paste-into-app automation across apps.
- Team/enterprise features.
- iOS/mobile deployment (a macOS app that borrows iOS/mobile design discipline).
- OCR of images.

---

## 2. Technology Stack (decision)

**Pure Swift + SwiftUI, zero external package dependencies.** Only Apple system
frameworks are used so the build is fully self-contained, reproducible offline, and
lightweight.

| Concern | Technology |
|---|---|
| UI | SwiftUI (`MenuBarExtra`, `Window`, `Settings` scenes), macOS 26 target |
| App lifecycle | Agent app (`LSUIElement`), accessory activation policy |
| Clipboard | `NSPasteboard` (change-count observation) |
| Storage: metadata | System **`libsqlite3`** (ships with macOS; `import SQLite3`) |
| Storage: images | PNG files on disk, referenced by path (no blob-in-row) |
| Hashing (dedup) | CommonCrypto `CC_SHA256` |
| Thumbnails | `NSImage` / `ImageIO` |
| Login item | `SMAppService` (Service Management, macOS 13+) |
| Global hotkey | Carbon `RegisterEventHotKey` |
| Notifications | `UNUserNotificationCenter` |
| Settings store | `UserDefaults` (non-sensitive settings only) |
| Packaging | `hdiutil` (built-in) + ad-hoc/Developer-ID `codesign` |

Minimum deployment target: **macOS 26** (build host). Primary architecture: arm64
(Apple Silicon); universal binary optional.

### Why zero-dep
Build reliability is a top priority. No SPM git/network fetches means the project
compiles anywhere Xcode is present, and every capability maps to a stable Apple API.

---

## 3. Architecture & Modules

Single SwiftUI agent executable. Each module has one purpose and a clear interface so
it can be built and unit-tested in isolation.

### 3.1 `ClipboardMonitor`
The only module touching `NSPasteboard`.
- Observes `NSPasteboard.general.changeCount` on a lightweight repeat timer (~400 ms).
- Idle cost is a single integer compare; the heavier read path runs only when
  `changeCount` actually changed.
- On change: debounce rapid bursts (coalesce multiple changes within a short window),
  produce a `CapturedClip`, and hand it to the `CapturePipeline`.
- Priority of content types read from the board: text (`.string`) first, then images
  (`.tiff` / `.png` / `NSImage`). Empty/unsupported content is ignored.
- Exposes a **suppression hook**: before any programmatic write-back, the app sets a
  flag so the next observed change (its own) is not captured. This is the mechanism
  that prevents self-created duplicates on restore.

`CapturedClip` (produced, not persisted yet): `rawType`, `text?`, `imageBytes?`
(source format), `sourceApp?` (frontmost app bundle id at capture time).

### 3.2 `CapturePipeline`
Pure-ish logic, fully unit-testable. Given a `CapturedClip` + current settings, decides:
1. **Paused?** → drop.
2. **Save-text/save-image toggles** → drop disallowed types.
3. **Excluded app?** (frontmost bundle id ∈ excluded set) → drop.
4. **Dedup:** compute `CC_SHA256` of the content bytes. If `ignoreDuplicates` and the
   hash equals the most recent stored item's hash → drop. Identical re-copies simply
   skip: no new row, no access bump.
5. **Build row:** insert into `ClipStore`. For images: write image file to
   `images/<sha>.png`, generate a thumbnail to `thumbs/<sha>.png`, record width/height
   and byte size.
6. **Enforce max items** + retention (see 3.5): evict/trim to the configured cap
   (non-favorites first).
7. Emit an `@Observable` change so UI updates instantly.

### 3.3 `ClipStore` (SQLite via system `libsqlite3`)
Owns all persistence. Interface (all methods synchronous on a dedicated serial
queue; the DB is small and fast):
- `bootstrap()` — create dirs + `PRAGMA journal_mode=WAL;` + create tables.
- `insert(_ item) -> Bool` (returns `false` on dedup-skip).
- `query(filter: QueryFilter, limit) -> [ClipboardItem]` — supports search text
  (`LIKE`), type filter, and date grouping; most-recent-first ordering.
- `get(id)`, `setFavorite(id, flag)`, `bumpAccessed(id)`, `delete(ids)`, `clearAll()`.
- `stats() -> (count, bytesUsed)` — item count + sum of stored file sizes.
- `purgeOlder(olderThan: Date, deleteFavorites: Bool)` — retention.
- `trimToMax(_ max: Int)` — cap enforcement.
- Excluded-app list is persisted in `UserDefaults` (small), not the DB.

### 3.4 `HotKeyManager`
Carbon `RegisterEventHotKey`. Default `⌘⇧V`. Re-registers on change from Settings.
On fire: posts to the app to toggle the menu-bar popover (and, if the popover is
hidden, bring it up + focus search). Only one binding at a time.

### 3.5 `RetentionJob`
- **Catch-up purge on launch** (covers the "app was closed" window) using stored
  `created_at` timestamps.
- **Periodic timer while running** (hourly) while the app is alive.
- Deletes items older than the selected period. Favorites are protected unless the
  "Automatically delete favorites" setting = "Follow clipboard retention setting".
- Settings live in UserDefaults, so they persist; the Job reads them each run.

### 3.6 `AppExclusions`
UserDefaults-backed set of bundle identifiers. Monitor reads
`NSWorkspace.shared.frontmostApplication?.bundleIdentifier` at capture time as the
source heuristic. Users add/remove apps in Settings → Privacy.

### 3.7 `SettingsStore`
UserDefaults-backed, observed by UI. All settings in Section 15 below.

### 3.8 `Notifications`
`UNUserNotificationCenter`, permission requested lazily on first need. Fires only for
the three meaningful moments: monitoring paused, monitoring resumed, history cleared.
Never on individual copies.

### 3.9 `Onboarding`
First-run 5-step flow (Section 10). Gated by a `hasSeenOnboarding` UserDefaults flag.

### 3.10 UI layers
- **Menu-bar popover** (`MenuBarExtra`, `.window` style): search field, day-grouped
  recent list (text preview / image thumbnail), per-row quick actions, bottom action
  row (Open Kopi, Settings, Pause/Resume, Clear History, Quit).
- **Main `Window`**: Sidebar (All / Text / Images / Today / Favorites / Settings) ·
  center list · details panel (full content, preview, Copy, Delete, favorite,
  timestamp, type, size/dimensions).
- **`Settings` scene**: General / Clipboard / Automatic Cleanup / Privacy / Storage.
- **Onboarding flow**.
All UI follows the design system in Section 9; Light/Dark automatic; Retina-safe.

### Data flow (capture)
`NSPasteboard` change → `ClipboardMonitor` (debounce, read, suppression check) →
`CapturedClip` → `CapturePipeline` (pause/excluded/dedup/build) → `ClipStore.insert` +
file write → `@Observable` list update → popover/window refresh.

### Data flow (restore / copy-back)
User selects item → set suppression flag → write to `NSPasteboard` (text → `.string`;
image → PNG data + `.tiff` from disk) → clear flag on next monitor tick → transient
"Copied ✓" feedback. No new history row is created.

---

## 4. Data Model

SQLite table `clipboard_items`:

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `type` | TEXT | `text` \| `image` |
| `created_at` | INTEGER (unix ms) | time copied |
| `last_accessed_at` | INTEGER (unix ms) | time restored/viewed |
| `is_favorite` | INTEGER 0/1 | |
| `content_hash` | TEXT (hex) | SHA-256 of normalized content bytes |
| `text_content` | TEXT (nullable) | plain text for text items |
| `image_path` | TEXT (nullable) | relative path to `images/<sha>.png` |
| `thumb_path` | TEXT (nullable) | relative path to `thumbs/<sha>.png` |
| `file_size` | INTEGER | byte size of stored content |
| `width` | INTEGER (nullable) | image dimension |
| `height` | INTEGER (nullable) | image dimension |

Indexes: `created_at` (ordering), `type`, `content_hash`, `is_favorite`.
Text search uses `LIKE` on `text_content` (adequate for a local, bounded dataset).

Settings (UserDefaults) include: `retentionPeriod`, `autoDeleteFavorites`,
`excludedApps[]`, `saveText`, `saveImages`, `ignoreDuplicates`, `maxItems`,
`shortcut`, `monitorEnabled`, `launchAtLogin`, `showMenuBarIcon`, `startMonitoring`,
`hasSeenOnboarding`, per-setting defaults per Section 15.

---

## 5. Storage Layout

```
~/Library/Application Support/Kopie/
  kopie.db          # SQLite (WAL)
  kopie.db-wal / -shm
  images/<sha>.png  # full image data
  thumbs/<sha>.png  # thumbnails
```
Content hash is the filename, so identical copies never create extra files. The dir is
created at bootstrap; if it cannot be created/write, the app logs and degrades
gracefully (keeps running, surfaces a storage error in Settings → Storage).

---

## 6. Feature Specifications

### 6.1 Clipboard monitoring
- Continuous, automatic (no "Save" button).
- Saves text and images (PNG/JPEG/tiff accepted → stored as PNG).
- Duplicates skipped (same content re-copied → no new entry).
- Records copy time; preserves original data for exact restore.
- Survives app restart and Mac restart (SQLite + on-disk images + login item).

### 6.2 History
- Most-recent-first. Day grouping (Today / Yesterday / weekday / date).
- Text row: preview (truncated), type, timestamp, char count. Full text in details.
- Image row: thumbnail, dimensions, type, timestamp. Larger preview in details.
- Favorites surfaced in the Sidebar.

### 6.3 Search
- Instant; filters by text content (`LIKE`), content type (All/Text/Images), and date.
- Empty query shows recent items; no match shows "Nothing found — Try searching for
  something else."

### 6.4 Copy back
- Per-item **Copy** action places stored content on the system clipboard for pasting.
- Restoring does not create a duplicate history entry.
- Image restore writes the original image bytes.

### 6.5 Delete
- Delete one item; multi-select delete; **Clear All** with confirmation:
  > **Clear clipboard history?** This will permanently remove all saved clipboard
  > items. This action cannot be undone. — [Cancel] [Clear All]

### 6.6 Automatic cleanup
- Setting: Automatically clear clipboard history → Never / 1 / 3 / 7 / 14 / 30 / 90
  days. Default: 7 days.
- Runs in the background while running **and** catch-up on launch (so it also applies
  to items that went stale while the app was closed).

### 6.7 Privacy & Security
- Data stays on the user's Mac. No upload, cloud, network transmission, telemetry, or
  analytics. No clipboard content in any logs beyond local error diagnostics.
- Settings/About privacy statement:
  > **Your clipboard stays on your Mac. Kopie does not upload or share your clipboard
  > history.**

### 6.8 Sensitive content handling
- **Ignore sensitive applications** — exclusion list of apps (default none; user adds,
  e.g. 1Password, Bitwarden, Keychain Access). Copies originating (frontmost app) from
  an excluded app are not stored.
- **Pause Clipboard Monitoring** — temporary global stop; resuming restarts capture.

### 6.9 Menu-bar app
- Icon in the menu bar (hidden when "Show menu bar icon" is off).
- Click opens the history popover (Section 10 layout).

### 6.10 Main window
- Sidebar: All / Text / Images / Today / Favorites / Settings.
- Center: clean list/grid.
- Details panel: full content/preview, Copy, Delete, favorite toggle, timestamp, type,
  size/dimensions.

### 6.11 Favorites
- Toggle per item. Favorites excluded from retention unless the user opts in.

### 6.12 Keyboard shortcut
- Global `⌘⇧V` default; reassignable in Settings. Works while another app is active.
  Opens the popover and focuses search.

### 6.13 Selecting & pasting (the core loop)
Kopie restores the chosen item onto the **system clipboard**; the actual paste is the
user's normal **⌘V** in the target app. The core loop:
Copy → auto-store → `⌘⇧V` → select an item → placed on clipboard → `⌘V` in target.
This must feel instant.

**Keyboard (fastest path):**
1. Press `⌘⇧V` anywhere → popover opens, search field focused.
2. Type to filter, or press ↑/↓ to move the highlight between rows.
3. Press **Enter** → the highlighted item is written to the clipboard.
4. In the target app, press **⌘V** to paste.

**Mouse path:**
- Click a row in the popover (or select it in the main window), then click its
  **Copy** action (or double-click the row), then **⌘V** in the target app.

Behavior details:
- Selecting an item shows its quick actions (Copy / Favorite / Delete); **Copy** is
  the default activation for the highlighted row (Enter).
- Text and images both use the same flow — images restore original bytes,
  so **⌘V** pastes the image, not a reference.
- **No cross-app auto-paste:** Kopie deliberately does not inject a paste into the
  frontmost app itself (no UI automation). Every restore ends with the user's own
  **⌘V**. This keeps the behavior reliable and native.
- ⌘V works in the currently active app; if the user has already switched to the
  target before pressing Enter, the clipboard is simply ready for their paste.

### 6.14 Notifications
- Only: monitoring paused / resumed / history cleared. Nothing on individual copies.

### 6.15 Settings
- **General:** Launch at login; Show menu bar icon; Global shortcut; Start monitoring
  automatically.
- **Clipboard:** Monitor clipboard; Save text; Save images; Ignore duplicates; Max
  items stored (default 1000).
- **Automatic Cleanup:** radio (Never / 1 / 3 / 7 / 14 / 30 / 90 days).
- **Privacy:** Excluded apps (add/remove); Pause monitoring; Clear all (confirm);
  Privacy information text.
- **Storage:** item count; storage used (MB); **Clear Cache** and **Clear All Data**,
  both with confirmation.

---

## 7. Storage / Performance
- No busy polling; idle cost is an int compare on a ~400 ms cadence.
- Images stored as files (not DB blobs); DB rows stay small.
- Thumbnails generated once at capture and cached on disk.
- History loads lazily (paged query, `LIMIT`); images loaded lazily (`NSImage` from
  file, cached, decoded off the render path). The popover never loads every image.
- `WAL` journal + prepared statements; single serial DB queue.

---

## 8. Error Handling & Edge Cases

Handled gracefully (never crash; log locally):
- Clipboard read unavailable / format absence → skip.
- Storage dir not writable → keep running; show storage error in Settings → Storage.
- Corrupt clipboard data → skip the capture.
- Extremely large images → cap: if stored bytes exceed a size limit (default 20 MB),
  downscale to a max dimension (e.g. 4096 px) and re-encode; if still excessive, skip
  and notify once.
- DB errors → caught, logged, surfaced; app stays alive.
- Rapid clipboard churn → 400 ms debounce coalesces.
- Multi-format content → text preferred over image.
- Empty content → ignored.
- Re-copied identical text/image → deduped.
- App restart / Mac restart → state restored from disk; retention catch-up runs.
- Restore while paused → still allowed (explicit user action) and never auto-captured.
- Paused + resumed → no gap-fill; new copies captured after resume.

---

## 9. UI Design System (Mobile/iOS skill set → SwiftUI)

Native SwiftUI, restrained and premium. The Mobile/iOS skill's structural discipline
is applied; it is **not** a Tailwind/React port.

- **Spacing** — 8-pt grid only (8/12/16/24/32). Popover padding 16; card interior
  12–16; section gaps 24; detail panel padding 24.
- **Color (60/30/10)** — 60% adaptive system background (Light/Dark automatic);
  30% neutral text with an opacity hierarchy (primary 100%, secondary ~68%, tertiary
  ~55%); 10% system accent (`Color.accentColor`) for CTAs/selection; accent at low
  opacity for subtle highlights. **Soft tinted shadows only** (never pure black/gray);
  no gradients.
- **Typography** — SF Pro (system). ≤4 sizes, 2 weights. `.headline` titles,
  `.body` content, `.caption` (+ `.secondary`) for meta; `.monospacedDigit` for counts
  and timestamps.
- **Cards** — `RoundedRectangle(cornerRadius: 12)`, fill `.background.secondary`,
  1-pt `strokeBorder(.quaternary)`. Rounded, subtle, non-distracting.
- **Hierarchy** — via size + weight + opacity, not by heavy fills. Values > labels.
- **Primary actions / thumb zone** — per-row quick actions (Copy / Favorite / Delete)
  ≥ 44 pt targets; primary Copy/Delete in the details panel.
- **Search** — instant, F-pattern; never a blank screen (recent items on empty query;
  guidance on no match).
- **Empty states** — icon (SF Symbol) + title + helper + CTA.
  - No history: "Nothing copied yet — Copy some text or an image and it will appear here."
  - No results: "Nothing found — Try searching for something else."
  - Paused: "Clipboard monitoring is paused — Resume monitoring to start saving copied items again."
- **Peak-moment motion** (restrained per "quiet"): brief "Copied ✓" transient on
  successful copy-back; gentle spring on the onboarding final step. No gratuitous
  animation.
- **Icons** — SF Symbols: `doc.text`, `photo`, `star.fill`, `trash`, `pause.circle` /
  `play.circle`, `magnifyingglass`, `clock`, `pin.fill`, `gearshape`, `scissors`.
- **Accessibility** — ≥ 44 pt tap targets; contrast-checked; Dynamic Type for system
  text; VoiceOver labels on rows and actions.

---

## 10. Popover Layout (menu bar)

```
        Menu Bar
────────────────────────────────────
   [Kopie icon]
┌─────────────────────────────────────┐
│  🔎 Searchclipboard...              │
├─────────────────────────────────────┤
│  Today                              │
│  ┌───────────────────────────────┐  │
│  │ Hello, this is copied text... │  │
│  │ Text · 8:42 PM · 128 chars       │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │      [ Image Thumbnail ]      │  │
│  │ Image · 8:39 PM · 1920×1080    │  │
│  └───────────────────────────────┘  │
├─────────────────────────────────────┤
│  Open Kopi · Settings · Pause ·     │
│  Clear History · Quit               │
└─────────────────────────────────────┘
```
Hovering/focusing a row reveals quick actions (Copy/Favorite/Delete). Enter copies the
selected row.

---

## 11. First-Run Onboarding
Gated by `hasSeenOnboarding`.
1. **Meet Kopie** — "Your clipboard history, always within reach."
2. **Everything you copy, organized** — "Kopie can save text and images copied on your Mac."
3. **Private by design** — "Your clipboard history stays on your Mac."
4. **Choose your retention period** — segmented control, **default 7 days**.
5. **You're ready** — "Copy something to get started." (gentle spring)

---

## 12. Packaging & Distribution

`package.json` scripts wrap build scripts:
- `npm run dev` — debug build → assemble `Kopie.app` → launch.
- `npm run build` — release build.
- `npm run package` — assemble `Kopie.app` (Info.plist + entitlements),
  `codesign` (Developer ID if available, else ad-hoc), `hdiutil` →
  `dist/Kopie.dmg` containing `Kopie.app` with a drag-to-`/Applications` alias.

```
Kopie.dmg
  └── Kopie.app
```
Info.plist: app name "Kopie", bundle id `com.kopie.app`, `LSUIElement = true`,
`CFBundleIconFile`, `NSAppleEventsUsageDescription` not required; no network
entitlements.

---

## 13. Testing Strategy
Unit tests (XCTest, separate test target) target where bugs actually live:
- **ClipStore** — bootstrap, insert, dedup, CRUD, search filters (text/type/date),
  multi-delete, clear-all, stats, `purgeOlder`, `trimToMax` — against a temp DB.
- **CapturePipeline** — pause, excluded app, dedup, max/retention trimming, image
  write + thumbnail + dimension recording (using small in-memory images).
- **RetentionJob** — period selection + favorites policy (protected vs deleted).
- **Dedup/hashing** — stability and collision behavior of SHA-256 normalization.

UI (popover/window) is verified by a clean release build + manual acceptance; full
GUI E2E is not run headless in this environment (documented limitation).

---

## 14. Milestones & Checkins
1. **Foundation** — scaffolding, `ClipStore` (+tests), `CapturePipeline` (+tests),
   `ClipboardMonitor`, menu-bar icon + minimal popover showing captured text.
2. **History & copy-back** — list w/ day grouping, text + image previews/thumbnails,
   search, copy-back (no dup), delete single/multi, clear-all confirm, favorites.
3. **Main window + settings** — sidebar/list/details, empty states, all Settings tabs,
   excluded apps, pause, shortcut reassignment, storage stats.
4. **Onboarding, notifications, retention job, login-at-login** + polish.
5. **Packaging + full acceptance pass** — `Kopie.dmg`; verify
   Copy→Save→Search→Select→Restore→Paste→Retain→AutoDelete for text **and** images.

---

## 15. Acceptance Criteria
The app is complete when:
- [ ] runs as a macOS app; [ ] runs from the menu bar
- auto-detects copied text and images
- history persists across app and macOS restarts
- user can search; copy items back; delete individually; clear all
- automatic deletion configured AND works without manually opening the app
- favorites; pause monitoring; exclude apps; configurable global shortcut
- Light + Dark mode; data stays local; large items handled gracefully
- packages into `Kopie.dmg`; the dmg installs a working `Kopie.app`

Full workflow to test at the end (text **and** images):
**Copy → Save → Search → Select → Restore → Paste → Retain → Auto Delete.**
