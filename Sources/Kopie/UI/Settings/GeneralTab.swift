import SwiftUI
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
                Text("With the popover open: ⌥↩ or ⌥-click copies an item and immediately pastes it into the app you were in (⌥1–9 quick-select). Needs Accessibility — Kopie will offer to open System Settings the first time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear { appearance = SettingsStore.shared.appearance }
        .onReceive(NotificationCenter.default.publisher(for: .kopieAppearanceChanged)) { _ in
            appearance = SettingsStore.shared.appearance
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
