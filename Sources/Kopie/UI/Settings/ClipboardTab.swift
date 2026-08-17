import SwiftUI

struct SettingsClipboardTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage("saveText") private var saveText = true
    @AppStorage("saveImages") private var saveImages = true
    @AppStorage("ignoreDuplicates") private var ignoreDuplicates = true
    @AppStorage("maxItems") private var maxItems = 1000

    var body: some View {
        Form {
            Toggle("Monitor clipboard", isOn: Binding(
                get: { !state.isPaused },
                set: { on in on ? state.startMonitoring() : state.pauseMonitoring() }))
            Toggle("Save text", isOn: $saveText)
            Toggle("Save images", isOn: $saveImages)
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
