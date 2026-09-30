import SwiftUI
import AppKit
import KopieCore

struct SettingsPrivacyTab: View {
    @EnvironmentObject var state: AppState
    @State private var showAddSheet = false
    @State private var showClearAllConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Ignored apps")
                    .font(.headline)
                Text("Copies made while one of these apps is frontmost are never stored.")
                    .font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(state.excludedApps) { app in
                        HStack {
                            Text(app.name.isEmpty ? app.id : app.name)
                            Text(app.id).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                state.removeExcludedApp(id: app.id)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 120)
                HStack {
                    Button("Add Ignored App…") { showAddSheet = true }
                    Spacer()
                }
                Divider()
                Text("Sensitive data sentinel")
                    .font(.headline)
                Text("Detects passwords, API keys, and tokens in what you copy. Masked items are stored but hidden until you reveal them in the details panel.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("When a secret is copied", selection: Binding(
                    get: { SettingsStore.shared.sensitiveDataPolicy },
                    set: { SettingsStore.shared.sensitiveDataPolicy = $0 })) {
                    ForEach(SensitiveDataPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Detection rules")
                        .font(.subheadline.weight(.medium))
                    ForEach(SensitiveDataDetector.allRules) { rule in
                        Toggle(rule.label, isOn: Binding(
                            get: { !SettingsStore.shared.sensitiveDisabledRules.contains(rule.id) },
                            set: { on in
                                var disabled = SettingsStore.shared.sensitiveDisabledRules
                                if on { disabled.remove(rule.id) } else { disabled.insert(rule.id) }
                                SettingsStore.shared.sensitiveDisabledRules = disabled
                            }))
                            .font(.caption)
                    }
                }
                Toggle("Auto-delete one-time codes after pasting", isOn: Binding(
                    get: { SettingsStore.shared.autoExpireOneTimeSecrets },
                    set: { SettingsStore.shared.autoExpireOneTimeSecrets = $0 }))
                    .font(.caption)
                    .help("Recognized OTPs and magic-link URLs are removed from history when you paste them")
                Divider()
                Text("Screen share shield")
                    .font(.headline)
                Text("Shielded windows cannot appear in any screenshot, recording, or screen share — including your own.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Hide Kopie from screen capture", selection: Binding(
                    get: { SettingsStore.shared.screenShieldMode },
                    set: { newMode in
                        SettingsStore.shared.screenShieldMode = newMode
                        NotificationCenter.default.post(name: .kopieScreenShieldChanged, object: nil)
                    })) {
                    ForEach(ScreenShieldMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                Divider()
                Toggle("Pause monitoring", isOn: Binding(
                    get: { state.isPaused },
                    set: { on in on ? state.pauseMonitoring() : state.startMonitoring() }))
                Toggle("Track source application", isOn: Binding(
                    get: { SettingsStore.shared.trackSourceApp },
                    set: { SettingsStore.shared.trackSourceApp = $0 }))
                    .help("Record which app copied each item")
                Button("Clear All Data…", role: .destructive) { showClearAllConfirm = true }
                Divider()
                Text("Your clipboard stays on your Mac. Kopie does not upload or share your clipboard history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddSheet) {
            AddExcludedAppSheet { bundleID, name in
                state.addExcludedApp(bundleID: bundleID, name: name)
            }
        }
        .sheet(isPresented: $showClearAllConfirm) {
            ConfirmDialog(
                title: "Clear all data?",
                message: "This permanently removes every saved clipboard item and stored image. This action cannot be undone.",
                confirmTitle: "Clear All", destructive: true,
                onConfirm: { state.clearAllData(); showClearAllConfirm = false },
                onCancel: { showClearAllConfirm = false })
        }
    }
}

private struct AddExcludedAppSheet: View {
    let onAdd: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualName = ""
    @State private var manualBundleID = ""
    @State private var picked: NSRunningApplication?

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Ignored App").font(.headline)
            Picker("Running app", selection: $picked) {
                Text("Choose…").tag(NSRunningApplication?.none)
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Text(app.localizedName ?? app.bundleIdentifier ?? "?").tag(NSRunningApplication?.some(app))
                }
            }
            .onChange(of: picked) { app in
                if let app {
                    manualName = app.localizedName ?? ""
                    manualBundleID = app.bundleIdentifier ?? ""
                }
            }
            TextField("App name", text: $manualName)
            TextField("Bundle identifier", text: $manualBundleID)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(manualBundleID, manualName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(manualBundleID.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
