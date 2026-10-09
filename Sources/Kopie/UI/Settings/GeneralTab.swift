import SwiftUI
import AppKit
import ServiceManagement
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
            HStack {
                Text("Global shortcut")
                Spacer()
                HotKeyRecorder()
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
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            appearance = SettingsStore.shared.appearance
            axGranted = PasteDirectService.isPermissionGranted
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
}
