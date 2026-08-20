import SwiftUI
import KopieCore

struct KopieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
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


