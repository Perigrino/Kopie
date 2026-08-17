import SwiftUI
import KopieCore

struct SettingsClipboardTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(SettingsStore.Keys.saveText) private var saveText = true
    @AppStorage(SettingsStore.Keys.saveImages) private var saveImages = true
    @AppStorage(SettingsStore.Keys.saveFiles) private var saveFiles = true
    @AppStorage(SettingsStore.Keys.ignoreDuplicates) private var ignoreDuplicates = true
    @AppStorage(SettingsStore.Keys.maxItems) private var maxItems = 1000

    var body: some View {
        Form {
            Toggle("Monitor clipboard", isOn: Binding(
                get: { !state.isPaused },
                set: { on in on ? state.startMonitoring() : state.pauseMonitoring() }))
            Toggle("Save text", isOn: $saveText)
            Toggle("Save images", isOn: $saveImages)
            Toggle("Save copied files", isOn: $saveFiles)
            Toggle("Ignore duplicates", isOn: $ignoreDuplicates)
            Stepper(value: $maxItems, in: 10...10000, step: 10) {
                HStack {
                    Text("Max items stored")
                    Spacer()
                    Text("\(maxItems)").monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
