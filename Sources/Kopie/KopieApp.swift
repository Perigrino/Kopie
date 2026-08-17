import SwiftUI
import KopieCore

struct KopieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView().environmentObject(appDelegate.state)
                .background(WindowProxy())
        }
        Window("Kopie", id: "main") {
            MainView().environmentObject(appDelegate.state)
                .background(WindowProxy())
        }
        .defaultSize(width: 900, height: 560)
    }
}

/// Captures `openWindow`/`openSettings` from the scene environment and exposes
/// them via `GlobalActions` so the menu-bar popover can open the windows.
private struct WindowProxy: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                GlobalActions.openMain = { openWindow(id: "main") }
                GlobalActions.openSettings = { openSettings() }
            }
    }
}

/// Cross-cutting actions the popover can trigger (opening windows/settings).
@MainActor
enum GlobalActions {
    static var openMain: (() -> Void)?
    static var openSettings: (() -> Void)?
}
