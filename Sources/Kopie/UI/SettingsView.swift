import SwiftUI
import KopieCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            SettingsGeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            SettingsClipboardTab()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            SettingsCleanupTab()
                .tabItem { Label("Cleanup", systemImage: "trash") }
            SettingsPrivacyTab()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            SettingsStorageTab()
                .tabItem { Label("Storage", systemImage: "externaldrive") }
            SettingsSecurityTab()
                .tabItem { Label("Encryption", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 420)
    }
}
