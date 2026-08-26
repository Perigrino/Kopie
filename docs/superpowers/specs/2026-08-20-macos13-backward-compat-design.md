# Kopie — macOS 13 (Ventura) Backward Compatibility

**Strategy for supporting macOS 13 Ventura and newer.**

- Date: 2026-08-20
- Status: Implemented (2026-08-20)
- Minimum target: **macOS 13 (Ventura)** — October 2022
- Previous target: macOS 26 (Tahoe)

---

## 1. Motivation

macOS 14 (Sonoma) was the implicit API floor due to usage of three SwiftUI APIs
introduced in that release. However, a significant number of Intel Macs cannot
upgrade past Ventura, and even some Apple Silicon users remain on macOS 13 for
compatibility reasons. Lowering the floor to Ventura expands the potential user
base by approximately one year of hardware.

The effort is modest: the three macOS 14+ APIs account for 10 call sites across
4 files, plus a handful of secondary incompatibilities discovered during the build.

---

## 2. APIs Replaced

### 2.1 `ContentUnavailableView` (macOS 14+)

**3 call sites** across `MainView.swift` and `DetailsPanel.swift`.

`ContentUnavailableView` is a convenience wrapper that displays an icon, title,
and description for empty states. Kopie already had an equivalent component —
`EmptyStateView` in `Components.swift` — making this a direct substitution with
no behavioral change.

| File | Context |
|---|---|
| `MainView.swift` (detail placeholder) | "Select an item" |
| `MainView.swift` (empty list) | "Nothing copied yet" / "Nothing found" |
| `DetailsPanel.swift` (image load failure) | "Image unavailable" |

**Replacement:** `EmptyStateView(symbol:title:message:)` — existing component.

### 2.2 `SettingsLink` (macOS 14+)

**2 call sites** across `Sidebar.swift` and `PopoverView.swift`.

`SettingsLink` is a declarative SwiftUI view that opens the Settings scene.
The macOS 13 equivalent is an imperative `Button` that sends the
`showSettingsWindow:` action via `NSApp.sendAction`.

| File | Context |
|---|---|
| `Sidebar.swift` (sidebar section) | "Settings…" |
| `PopoverView.swift` (bottom bar) | "Settings…" |

**Replacement:**
```swift
Button("Settings…") {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

### 2.3 `@Environment(\.openSettings)` (macOS 14+)

**1 call site** in `KopieApp.swift` — the `SettingsBridge` helper view that
captures the SwiftUI `openSettings` environment action and exposes it to AppKit.

**Replacement:** Remove the environment dependency entirely. `SettingsBridge` now
directly calls `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)`
in its `.onAppear`, matching the pattern used in the two `SettingsLink` replacements.

### 2.4 `onKeyPress` modifier (macOS 14+)

**5 call sites** in `PopoverView.swift` — keyboard navigation (arrow keys, Enter,
Escape, Delete).

This was the most involved replacement. The declarative `.onKeyPress` modifier was
replaced with an imperative `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`
installed in `.onAppear` and removed in `.onDisappear`.

| Key | Action |
|---|---|
| Up arrow (keyCode 126) | Move highlight up |
| Down arrow (keyCode 125) | Move highlight down |
| Return (keyCode 36) | Copy highlighted item |
| Escape (keyCode 53) | Clear search or close popover |
| Delete (keyCode 51) | Remove highlighted item |

**Implementation pattern:**
```swift
@State private var keyMonitor: Any?

private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        switch event.keyCode {
        case 126: moveHighlight(-1); return nil   // consume
        case 125: moveHighlight(1); return nil
        case 36:  copyHighlighted(); return nil
        case 53:  handleEscape(); return nil
        case 51:  handleDelete(); return event     // pass through if nothing to delete
        default:  return event
        }
    }
}

private func removeKeyMonitor() {
    if let monitor = keyMonitor {
        NSEvent.removeMonitor(monitor)
        keyMonitor = nil
    }
}
```

Lifecycle: `installKeyMonitor()` in `.onAppear`, `removeKeyMonitor()` in `.onDisappear`.

### 2.5 `.onChange(of:)` new signature (macOS 14+)

**5 call sites** across `PopoverView.swift`, `GeneralTab.swift`,
`PrivacyTab.swift`, and `StorageTab.swift`.

macOS 14 introduced `.onChange(of:) { }` (no parameters) and
`.onChange(of:) { old, new in }`. The macOS 12/13 compatible signature is
`.onChange(of:perform:) { newValue in }`.

| File | Line | Was | Now |
|---|---|---|---|
| `PopoverView.swift` | `state.searchText` | `{ }` | `{ _ in }` |
| `PopoverView.swift` | `highlightedIndex` | `{ }` | `{ _ in }` |
| `GeneralTab.swift` | `launchAtLogin` | `{ _, on in }` | `{ on in }` |
| `PrivacyTab.swift` | `picked` | `{ _, app in }` | `{ app in }` |
| `StorageTab.swift` | `state.items.count` | `{ }` | `{ _ in }` |

### 2.6 `.quaternarySystemFill` (macOS 14+)

**2 call sites** in `DetailsPanel.swift` and `PopoverView.swift`.

`.quaternarySystemFill` is a system semantic color introduced in macOS 14 for
subtle background fills.

**Replacement:** `.controlBackgroundColor` — available since macOS 10.15, provides
a similar neutral background for controls and content areas.

---

## 3. APIs That Required No Changes

These APIs were verified compatible with macOS 13:

| API | Minimum | Used in |
|---|---|---|
| `NavigationSplitView` | macOS 13 | `MainView.swift` |
| `LazyVStack` | macOS 11 | `PopoverView.swift` |
| `@FocusState` | macOS 12 | `PopoverView.swift` |
| `.searchable` | macOS 12 | `MainView.swift` |
| `.textSelection(.enabled)` | macOS 12 | `DetailsPanel.swift` |
| `@Environment(\.dismiss)` | macOS 12 | `OnboardingView.swift` |
| `@Environment(\.accessibilityReduceMotion)` | macOS 12 | `OnboardingView.swift` |
| `.regularMaterial` | macOS 12 | `PopoverView.swift`, `CopiedToast.swift` |
| `Grid` / `GridRow` | macOS 13 | `DetailsPanel.swift` |
| `SMAppService` (login item) | macOS 13 | `GeneralTab.swift` |
| `MenuBarExtra` (menu-bar scene) | macOS 13 | `AppDelegate.swift` |

All KopieCore code uses only Foundation and AppKit (SQLite3, CommonCrypto,
Security framework) with no macOS version constraints beyond 12+.

---

## 4. Package.swift Change

```swift
// Before
platforms: [.macOS(.v26)]

// After
platforms: [.macOS(.v13)]
```

The `swift-tools-version:6.2` declaration was left unchanged — Swift 6.2 supports
compiling for macOS 13 targets regardless of the tools version.

---

## 5. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| NSEvent lifecycle mismanagement | Medium | Monitor installed in `.onAppear`, removed in `.onDisappear`; `@State` ensures single registration |
| `.controlBackgroundColor` visual difference | Low | Matches `.quaternarySystemFill` closely in both Light and Dark mode |
| `NSApp.sendAction("showSettingsWindow:")` fragility | Low | Selector string is stable across macOS 13–14+; same pattern used by third-party apps for years |
| Ventura-specific bugs undiscovered | Low | All 97 unit tests pass; smoke test recommended on Ventura VM |
| Future SwiftUI APIs used without availability checks | Medium | Build targeting macOS 13 will catch new API usage at compile time |

---

## 6. Files Changed

| File | Changes |
|---|---|
| `Package.swift` | Platform target `.v26` → `.v13` |
| `Sources/Kopie/UI/MainView.swift` | `ContentUnavailableView` → `EmptyStateView` |
| `Sources/Kopie/UI/DetailsPanel.swift` | `ContentUnavailableView` → `EmptyStateView`, `.quaternarySystemFill` → `.controlBackgroundColor` |
| `Sources/Kopie/UI/PopoverView.swift` | `SettingsLink` → `Button`, `onKeyPress` → `NSEvent` monitor, `.onChange` signature, `.quaternarySystemFill` → `.controlBackgroundColor` |
| `Sources/Kopie/UI/Sidebar.swift` | `SettingsLink` → `Button` |
| `Sources/Kopie/UI/Settings/GeneralTab.swift` | `.onChange` signature |
| `Sources/Kopie/UI/Settings/PrivacyTab.swift` | `.onChange` signature |
| `Sources/Kopie/UI/Settings/StorageTab.swift` | `.onChange` signature |
| `Sources/Kopie/KopieApp.swift` | `@Environment(\.openSettings)` → `NSApp.sendAction` |

---

## 7. Future Guidelines

To prevent accidental regression to macOS 14+ APIs:

1. **Compiler enforcement:** The `platforms: [.macOS(.v13)]` declaration causes
   the Swift compiler to reject any API usage without an `if #available` check.
   This is the primary safety net.

2. **Code review checklist:** When adding new SwiftUI views, verify the API
   availability of any modifier or initializer not already used in the codebase.

3. **Known API gates:** Before using a new SwiftUI API, check:
   - `ContentUnavailableView` → macOS 14+ (use `EmptyStateView`)
   - `SettingsLink` → macOS 14+ (use `Button` + `NSApp.sendAction`)
   - `.onKeyPress` → macOS 14+ (use `NSEvent.addLocalMonitorForEvents`)
   - `.onChange(of:) { }` / `.onChange(of:) { old, new in }` → macOS 14+ (use `.onChange(of:) { new in }`)
   - `.quaternarySystemFill` → macOS 14+ (use `.controlBackgroundColor`)

4. **Raising the floor:** When macOS 13 support is no longer needed, the
   reverse migration is straightforward — restore the original APIs from this
   document. The `EmptyStateView` and NSEvent monitor can be removed, and
   `ContentUnavailableView`, `SettingsLink`, and `.onKeyPress` restored.
