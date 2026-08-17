import SwiftUI
import KopieCore

struct SettingsCleanupTab: View {
    @AppStorage(SettingsStore.Keys.retentionPeriod) private var retentionPeriod = RetentionPeriod.daySeven.rawValue
    @AppStorage(SettingsStore.Keys.autoDeleteFavorites) private var autoDeleteFavorites = false

    var body: some View {
        Form {
            Picker("Keep items for", selection: $retentionPeriod) {
                ForEach(RetentionPeriod.allCases) { p in
                    Text(p.label).tag(p.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            Picker("Favorites", selection: $autoDeleteFavorites) {
                Text("Never delete").tag(false)
                Text("Follow retention").tag(true)
            }
            .pickerStyle(.radioGroup)
            Text("Retention runs on launch and hourly while Kopie is open.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

extension RetentionPeriod: Identifiable { public var id: Int { rawValue } }
