import SwiftUI
import KopieCore

struct KopieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(appDelegate.state)
        }
    }
}

/// Cross-cutting actions the popover can trigger (opening windows/settings).
@MainActor
enum GlobalActions {
    static var openMain: (() -> Void)?
    static var openSettings: (@MainActor () -> Void)?
    static var openOnboarding: (() -> Void)?
    static var closePopover: (() -> Void)?
}

/// Tiny always-alive view that captures the SwiftUI `openSettings` environment
/// action and exposes it to AppKit (the status-item menu).
struct SettingsBridge: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear { GlobalActions.openSettings = { openSettings() } }
    }
}
