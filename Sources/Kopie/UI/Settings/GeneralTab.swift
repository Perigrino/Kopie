import SwiftUI
import AppKit
import ServiceManagement
import Carbon.HIToolbox
import KopieCore

struct SettingsGeneralTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsStore.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsStore.Keys.showMenuBarIcon) private var showMenuBarIcon = true
    /// Mirrors SettingsStore.appearance so the picker reflects live changes
    /// made from the status menu too.
    @State private var appearance: SettingsStore.AppAppearance = SettingsStore.shared.appearance
    @AppStorage(SettingsStore.Keys.pasteDirect) private var pasteDirect = true
    @AppStorage(SettingsStore.Keys.pasteAsPlainText) private var pasteAsPlainText = false
    @AppStorage(SettingsStore.Keys.showMenuBarPreview) private var showMenuBarPreview = true
    /// Live state of the Accessibility grant. Re-checked whenever the app comes
    /// back to the foreground, because granting it in System Settings is the
    /// one action that changes it — and that always means leaving this app.
    @State private var axGranted = PasteDirectService.isPermissionGranted
    /// Mirrors SettingsStore.pasteBindings so the rows and the picker reflect
    /// saved edits without polling UserDefaults.
    @State private var pasteBindings: PasteBindings = SettingsStore.shared.pasteBindings
    @State private var plainModifier: UInt32 = SettingsStore.shared.pasteBindings.plainModifier
    /// Inline conflict errors keyed by role (S-004: inline, never an alert).
    @State private var conflictError: [PasteBindings.Role: String] = [:]
    /// Mirrors Sparkle's `automaticallyChecksForUpdates` and its last-check
    /// stamp; both live behind `UpdaterCoordinator` so this view never imports
    /// Sparkle or reaches into its scheduler.
    @State private var autoCheckUpdates = UpdaterCoordinator.shared.automaticallyChecksForUpdates
    @State private var lastUpdateCheck: Date? = UpdaterCoordinator.shared.lastUpdateCheckDate

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    applyLaunchAtLogin(on)
                }
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            Picker("Appearance", selection: $appearance) {
                ForEach(SettingsStore.AppAppearance.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .onChange(of: appearance) { _ in
                // AppDelegate listens and re-applies NSApp.appearance.
                NotificationCenter.default.post(name: .kopieAppearanceChanged, object: nil)
            }
            Section("Paste Keys") {
                pasteKeyRow("Global shortcut", role: .globalHotkey)
                pasteKeyRow("Direct paste", role: .directPaste)
                HStack {
                    Picker("Paste as plain", selection: $plainModifier) {
                        Text("⌃ Control").tag(UInt32(controlKey))
                        Text("⌥ Option").tag(UInt32(optionKey))
                    }
                    if pasteBindings.plainModifier != PasteBindings.default.plainModifier {
                        Button("Revert") { revert(.plainModifier) }
                            .font(.caption)
                    }
                }
                .onChange(of: plainModifier) { newValue in
                    applyPlainModifierSelection(newValue)
                }
                if let err = conflictError[.plainModifier] ?? plainConflict {
                    // Inline conflict error under the row — never an alert
                    // (ux-design surface table).
                    Text(err).font(.footnote).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Toggle("Paste directly into apps", isOn: $pasteDirect)
                    .onChange(of: pasteDirect) { on in
                        // Turning the feature on is the moment to ask for the access it
                        // needs — asking later, when a click has already done nothing,
                        // reads as a bug rather than a missing grant.
                        axGranted = PasteDirectService.isPermissionGranted
                        if on && !axGranted { PasteDirectService.requestPermission() }
                    }
                Text("A click in the shortcut popover copies the item and pastes it straight into the app you were in. ⌥↩, ⌥-click and ⌥1–9 quick-select work in either popover. Needs Accessibility.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if pasteDirect && !axGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility access is off, so items can't be pasted into other apps yet.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Open Settings") { PasteDirectService.openAccessibilitySettings() }
                            .font(.caption)
                    }
                }
                Toggle("Paste as plain text", isOn: $pasteAsPlainText)
                Text("Strips rich formatting when copying items back, so target apps receive unstyled text. Hold ⌃ while copying in the popover to do it once without changing this setting.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Direct paste")
            }
            Section {
                Picker("Ambient background",
                       selection: Binding(get: { state.ambientSpeed },
                                          set: { state.setAmbientSpeed($0) })) {
                    ForEach(SettingsStore.AmbientSpeed.allCases) { speed in
                        Text(speed.label).tag(speed)
                    }
                }
            } header: {
                Text("Landing page")
            }
            Section {
                Toggle("Show hover preview", isOn: $showMenuBarPreview)
                Text("Displays a floating preview bubble beside the list when you hover or arrow-key through items in the menu bar popover.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Menu bar list")
            }
            Section {
                Toggle("Check for updates automatically", isOn: $autoCheckUpdates)
                    .onChange(of: autoCheckUpdates) { on in
                        UpdaterCoordinator.shared.setAutomaticallyChecksForUpdates(on)
                    }
                HStack {
                    Button("Check for Updates…") {
                        UpdaterCoordinator.shared.checkForUpdates()
                        refreshUpdateInfo()
                    }
                    .disabled(!UpdaterCoordinator.shared.isSupported)
                    Spacer()
                    if let lastUpdateCheck {
                        Text("Last checked \(lastUpdateCheck.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kopie \(AppVersion.short) (build \(AppVersion.build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Updates are checked at most once a day. Downloads are EdDSA-signed and verified before they replace the app; you can skip a version or be reminded later.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Software Update")
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            appearance = SettingsStore.shared.appearance
            axGranted = PasteDirectService.isPermissionGranted
            seedLegacyHotkeyIntoPasteBindings()
            refreshBindings()
            refreshUpdateInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kopieAppearanceChanged)) { _ in
            appearance = SettingsStore.shared.appearance
        }
        // Granting Accessibility always means leaving this window for System
        // Settings; re-read the grant the moment the app is clicked back in so
        // the warning clears without the user reopening Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            axGranted = PasteDirectService.isPermissionGranted
        }
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Surface silently; system may deny without entitlement.
            NSLog("launch at login toggle failed: \(error)")
        }
    }

    // MARK: - Paste Keys (S-004)

    /// The saved bindings — always read fresh from the store so validation
    /// sees the value that is actually persisted.
    private var bindings: PasteBindings { SettingsStore.shared.pasteBindings }

    /// One editable paste-binding row (S-004 flow: click binding row → press
    /// new combo → conflict check → save or inline error → Revert restores).
    private func pasteKeyRow(_ title: String, role: PasteBindings.Role) -> some View {
        HStack(alignment: .top) {
            Text(title).padding(.top, 4)
            Spacer()
            HotKeyRecorder(commit: { spec in save(spec, as: role) },
                           displayLabel: label(for: role))
            if isCustom(role) {
                Button("Revert") { revert(role) }
                    .font(.caption)
            }
        }
    }

    /// The human-readable combo currently saved for a role, e.g. "⌥↩".
    private func label(for role: PasteBindings.Role) -> String {
        switch role {
        case .globalHotkey: return bindings.globalHotkey.label
        case .directPaste: return bindings.directPaste.label
        case .plainModifier: return HotKeySpec(keyCode: 0, modifiers: bindings.plainModifier).label
        }
    }

    /// True while a role deviates from its default — the moment a Revert
    /// button becomes meaningful.
    private func isCustom(_ role: PasteBindings.Role) -> Bool {
        let d = PasteBindings.default
        switch role {
        case .globalHotkey: return pasteBindings.globalHotkey != d.globalHotkey
        case .directPaste: return pasteBindings.directPaste != d.directPaste
        case .plainModifier: return pasteBindings.plainModifier != d.plainModifier
        }
    }

    /// Inline conflict error text (never an alert — ux-design surface table).
    private func validate(_ candidate: HotKeySpec, as role: PasteBindings.Role) -> String? {
        for other in PasteBindings.Role.allCases where other != role {
            let clash: Bool
            switch other {
            case .plainModifier:
                clash = ShortcutConflict.plainModifierConflict(plainModifier: bindings.plainModifier, combo: candidate)
            default:
                clash = ShortcutConflict.conflict(candidate: candidate, against: other, bindings: bindings) != nil
            }
            if clash { return "This shortcut is already used by \(other.label)." }
        }
        return nil
    }

    /// "Set Shortcut" persistence path. Saves through
    /// `SettingsStore.pasteBindings` only when no other paste role already
    /// holds the combo; returns the inline error text on conflict.
    private func save(_ candidate: HotKeySpec, as role: PasteBindings.Role) -> String? {
        if let err = validate(candidate, as: role) { return err }
        var b = bindings
        switch role {
        case .globalHotkey:
            // Trial-register so combos the system or another app already owns
            // fail loudly instead of saving a dead shortcut (same contract the
            // standalone hotkey row always had).
            guard HotKeyManager.register(keyCode: candidate.keyCode,
                                         modifiers: candidate.modifiers,
                                         handler: {}) else {
                return "That combination is already in use by the system or another app."
            }
            b.globalHotkey = candidate
            SettingsStore.shared.hotkey = candidate
            NotificationCenter.default.post(name: .kopieHotKeyChanged, object: nil)
        case .directPaste:
            b.directPaste = candidate
        case .plainModifier:
            break
        }
        SettingsStore.shared.pasteBindings = b
        refreshBindings()
        return nil
    }

    /// S-004 "Revert": restores the default for that row's role.
    private func revert(_ role: PasteBindings.Role) {
        var b = bindings
        switch role {
        case .globalHotkey:
            b.globalHotkey = .default
            SettingsStore.shared.hotkey = b.globalHotkey
            NotificationCenter.default.post(name: .kopieHotKeyChanged, object: nil)
        case .directPaste:
            b.directPaste = .defaultDirectPaste
        case .plainModifier:
            b.plainModifier = PasteBindings.default.plainModifier
            conflictError[.plainModifier] = nil
        }
        SettingsStore.shared.pasteBindings = b
        refreshBindings()
    }

    /// A held plain modifier can't shadow an existing paste combo (S-004).
    private func plainConflictText(for modifier: UInt32) -> String? {
        for role in PasteBindings.Role.allCases {
            let combo: HotKeySpec
            switch role {
            case .globalHotkey: combo = bindings.globalHotkey
            case .directPaste: combo = bindings.directPaste
            case .plainModifier: continue
            }
            if ShortcutConflict.plainModifierConflict(plainModifier: modifier, combo: combo) {
                return "This shortcut is already used by \(role.label)."
            }
        }
        return nil
    }

    /// Live check against the saved bindings, shown under the picker.
    private var plainConflict: String? { plainConflictText(for: bindings.plainModifier) }

    /// Picker change handler: a conflicting plain modifier is rejected (no
    /// silent override) with the inline error; selection snaps back instead
    /// of saving a shadowed modifier.
    private func applyPlainModifierSelection(_ newValue: UInt32) {
        let stored = bindings.plainModifier
        guard newValue != stored else { return }
        if let err = plainConflictText(for: newValue) {
            conflictError[.plainModifier] = err
            plainModifier = stored
        } else {
            conflictError[.plainModifier] = nil
            var b = bindings
            b.plainModifier = newValue
            SettingsStore.shared.pasteBindings = b
            refreshBindings()
        }
    }

    /// The paste-binding struct starts as `.default`; users who customized the
    /// legacy global hotkey before S-004 land get that value carried into the
    /// bindings once, so conflict checks compare against the real hotkey.
    private func seedLegacyHotkeyIntoPasteBindings() {
        let legacy = SettingsStore.shared.hotkey
        guard bindings == .default, legacy != HotKeySpec.default else { return }
        var b = bindings
        b.globalHotkey = legacy
        SettingsStore.shared.pasteBindings = b
    }

    /// Pull the mirror states back in line with the persisted values.
    private func refreshBindings() {
        pasteBindings = SettingsStore.shared.pasteBindings
        plainModifier = pasteBindings.plainModifier
    }

    /// Mirrors Sparkle's persisted updater settings into view state.
    private func refreshUpdateInfo() {
        autoCheckUpdates = UpdaterCoordinator.shared.automaticallyChecksForUpdates
        lastUpdateCheck = UpdaterCoordinator.shared.lastUpdateCheckDate
    }
}
