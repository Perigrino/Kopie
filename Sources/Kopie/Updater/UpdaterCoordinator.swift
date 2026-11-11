import Foundation
import Sparkle

/// Owns Sparkle's standard updater for the lifetime of the app.
///
/// Sparkle is deliberately given the *standard* user driver: its update panel
/// is native AppKit, shows the version and the appcast's release notes, and
/// already implements "Remind Me Later" / "Skip This Version" with persisted
/// state, so the same notification is never pushed at the user twice. Because
/// Kopie is an `LSUIElement` app, Sparkle treats it as background-running and
/// uses gentle (notification-style) reminders rather than yanking focus.
///
/// No custom update UI lives here: the Settings row and the status-menu item
/// only route into Sparkle, which keeps the update path one auditable codebase
/// instead of two.
@MainActor
final class UpdaterCoordinator: ObservableObject {
    static let shared = UpdaterCoordinator()

    private var controller: SPUStandardUpdaterController?

    private init() {}

    /// Sparkle needs a real application bundle: acceptance runs execute the
    /// bare binary (`--smoke-*`), which has no bundle identifier and no
    /// Info.plist feed keys.
    var isSupported: Bool {
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundleURL.pathExtension == "app" else { return false }
        let args = ProcessInfo.processInfo.arguments
        return !args.contains(where: { $0.hasPrefix("--smoke-") })
    }

    /// True once `start()` has handed control to Sparkle.
    var isStarted: Bool { controller != nil }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    var automaticallyChecksForUpdates: Bool {
        controller?.updater.automaticallyChecksForUpdates ?? true
    }

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    /// Starts Sparkle's scheduler. Called after the launch splash has been
    /// dismissed so an update alert and the welcome screen never race.
    func start() {
        guard isSupported, controller == nil else { return }
        // Both come from the Info.plist scripts/build.sh generates. Without
        // them Sparkle cannot verify anything, so stay quiet rather than show
        // an "update failed" panel at launch.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard !key.isEmpty, !feed.isEmpty else {
            NSLog("Kopie updater: SUFeedURL/SUPublicEDKey missing; update checks disabled")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    /// Opens Sparkle's standard update panel. Safe to call before `start()`
    /// (for example from the status menu during the splash) — it starts the
    /// updater and then checks.
    func checkForUpdates() {
        if controller == nil { start() }
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        if controller == nil { start() }
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
