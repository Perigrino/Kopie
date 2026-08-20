import SwiftUI
import ServiceManagement
import KopieCore

struct SettingsGeneralTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsStore.Keys.launchAtLogin) private var launchAtLogin = false
    @AppStorage(SettingsStore.Keys.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsStore.Keys.startMonitoring) private var startMonitoring = true

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    applyLaunchAtLogin(on)
                }
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            Toggle("Start monitoring automatically", isOn: $startMonitoring)
            HStack {
                Text("Global shortcut")
                Spacer()
                HotKeyRecorder()
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
