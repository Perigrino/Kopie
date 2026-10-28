# Platform

Research for Kopie. Done 2026-10-28.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Research question: which macOS APIs, permissions, and limits does each planned feature need, and where are the sharp edges (robustness)?
Decision it informs: architecture and API choices for Kopie's 2.6 rearchitecture (min macOS 13, Swift 6, SwiftUI + AppKit).

## Findings

1. **Capture monitoring.** `NSPasteboard.changeCount` increments on each ownership change; still the only public general macOS API — no Darwin-notification/KVO-style clipboard API through macOS 26. Polling at 0.5–1s via `DispatchSourceTimer` is standard. Pitfalls: `changeCount` can jump >1; a huge image read can block; filter by comparing the count *and* your own last written count to avoid paste/write-back loops. [V](https://developer.apple.com/documentation/appkit/nspasteboard/changecount) + [K]
2. **macOS Sequoia pasteboard prompt.** macOS 15 added periodic pasteboard-read prompts for apps reading without direct user intent. Clipboard managers must tie reads to hotkey/activation, or use the "allow" whitelisting state; this changes polling design. [K][U → test on Sequoia/macOS 26]
3. **Paste-back.** Requires TCC Accessibility permission. Pattern: `NSPasteboard` write → restore count detection → `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `.post(tap: .cgSessionEventTap)` for ⌘V. Sharp edges: Secure Input silently swallows synthetic events (detect via `CGEventSource.secureInputEnabled()`); Xcode/VM/terminal apps eat events; App Store review rejects CGEvent keyboard synthesis, so direct/notarized distribution is the only path. [K][U → accept runtime detection tests]
4. **Global hotkeys.** `RegisterEventHotKey` (Carbon) remains reliable, works unsandboxed and sandboxed; `NSEvent.addGlobalMonitorForEvents` cannot consume keystrokes; `CGEventTap` is the powerful (swallowing) option, requires Accessibility. [K]
5. **Popover vs panel.** `NSPopover` from a status item can fail to become key, closes on click-away, and can't outlive its positioning view. The standard for launcher UIs is `NSPanel` with `styleMask: [.borderless, .nonactivatingPanel]`, `level = .statusBar`, `hidesOnDeactivate`, `becomesKeyOnlyIfNeeded = true`, plus explicit `makeKeyAndOrderFront` and `NSApp.activate(ignoringOtherApps:)`. [V](https://developer.apple.com/documentation/appkit/nspanel) + [K]. SwiftUI content in a nonactivating panel needs manual key-window handling for text fields [K]. macOS 26 Liquid Glass changes panel chrome — test visuals [U].
6. **Sandbox/App Store.** Sandboxing allows Carbon hotkeys but blocks AX/CGEvent taps (temporary exceptions now rejected by review) — Kopie must stay direct-distribution, hardened-runtime, notarized. `NSBackgroundActivityScheduler` is the documented correct mechanism for retention/cleanup work. [K]
7. **OCR.** Headless OCR: Vision `VNRecognizeTextRequest` (accurate mode on M-series: ~200–500ms per screenshot) at `.userInitiated` QoS on a serial queue, image downscaled ≤2×. VisionKit `ImageAnalyzer` is UI-coupled; use Vision for background indexing. macOS 26 Vision has Swift 6 annotations, no behavior break. [K][U → measure on this Mac]
8. **Screen-capture privacy.** `NSWindow.sharingType = .none` maps to `kCGWindowSharingNone` — the mechanism ScreenCaptureKit/CGWindowList respect; combine with `collectionBehavior` for Stage Manager. [K]
9. **Storage.** SQLite C API: `sqlite3_open_v2(SQLITE_OPEN_FULLMUTEX)`; `PRAGMA journal_mode=WAL` needs exclusive access; `PRAGMA synchronous=NORMAL` in WAL is the right durability tradeoff on APFS; store large image blobs outside the DB or via `sqlite3_blob_open`. Encryption: prefer CryptoKit `AES.GCM` (authenticated, Swift-native) over CommonCrypto; keys in Keychain `kSecClassGenericPassword` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. [K]
10. **Shortcuts/App Intents.** `AppIntent` is the only supported path; works in-process, works non-sandboxed; clipboard reads from an intent trigger the macOS 15 pasteboard prompt like manual reads. First-run `requestUserConfirmation` pattern pre-creates consent. [K][U]

## Decisions for 2.6 rearchitecture

1. **Stay direct-distribution, not App Store** — CGEvent paste-back + AX tap + non-sandboxed SQLite/ScreenShield are incompatible with App Store rules; encode as a hard constraint in the brief. [K]
2. **Replace NSPopover windows with NSPanel (.nonactivatingPanel)** for the toolbar UI; keep NSStatusItem. Fixes focus fragility (Maccy-style large-history popup issues) and gives correct hiding. Test on macOS 26 Liquid Glass chrome. [V API existence] [U → visual test]
3. **Keep changeCount polling** (no newer API), but add Sequoia/macOS 26 prompt-awareness and self-write filtering; rapid-copy capture test wired into the acceptance script. [V] [U → test]
4. **Migrate encryption from CommonCrypto to CryptoKit AES.GCM + Keychain**, keeping SQLite WAL with explicit FULLMUTEX open and blob-outside-DB storage. [K]
5. **Use NSBackgroundActivityScheduler** for retention/cleanup instead of ad-hoc timers. [K]
6. **Secure Input detection** before every synthetic paste; show a UI hint when active (resolves "silent paste failure" complaints). [K] [U → test]

## Open questions
- [U] Instead of Carbon — whether CGEventTap with a swallow option lets us move hotkey prefixes; keep Carbon for 2.6 (works, deprecated-ness unconfirmed on macOS 26).
- [U] Sequoia permission prompts changing per-session state; add periodic integration tests on macOS 15/26.
