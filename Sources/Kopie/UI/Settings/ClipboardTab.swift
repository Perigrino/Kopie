import SwiftUI
import KopieCore

struct SettingsClipboardTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsStore.Keys.saveText) private var saveText = true
    @AppStorage(SettingsStore.Keys.saveImages) private var saveImages = true
    @AppStorage(SettingsStore.Keys.saveFiles) private var saveFiles = true
    @AppStorage(SettingsStore.Keys.ignoreDuplicates) private var ignoreDuplicates = true
    @AppStorage(SettingsStore.Keys.ocrImages) private var ocrImages = true
    @AppStorage(SettingsStore.Keys.maxItems) private var maxItems = 1000

    var body: some View {
        Form {
            Section {
                Toggle("Monitor clipboard", isOn: Binding(
                    get: { !state.isPaused },
                    set: { on in on ? state.startMonitoring() : state.pauseMonitoring() }))
                Toggle("Save text", isOn: $saveText)
                Toggle("Save images", isOn: $saveImages)
                Toggle("Save copied files", isOn: $saveFiles)
            } header: {
                Text("What to capture")
            }
            Section {
                Toggle("Ignore duplicates", isOn: $ignoreDuplicates)
                Text("Re-copying the same content moves it to the top and bumps its copy count instead of saving a second entry.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Recognize text in images (searchable)", isOn: $ocrImages)
            Text("Runs entirely on your Mac. Screenshots become findable by the words inside them.")
                .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Smart capture")
            }
            Section {
                Stepper(value: $maxItems, in: 10...10000, step: 10) {
                    HStack {
                        Text("Max items stored")
                        Spacer()
                        Text("\(maxItems)").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("History size")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
