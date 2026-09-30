import AppKit
import KopieCore

/// Applies `NSWindow.sharingType = .none` to Kopie's windows according to the
/// ScreenShield setting. A window with sharingType .none is excluded from ALL
/// screen capture — screenshots, screen recordings, and sharing apps —
/// enforced by WindowServer (no per-frame work, no polling).
///
/// "During calls" mode watches NSWorkspace's frontmost-application
/// notifications and shields while a conferencing app (user-extendable list)
/// is frontmost. Re-evaluated on every frontmost change and setting change.
@MainActor
final class ScreenShield {
    /// Bundle IDs treated as "in a call" for the auto mode.
    static let defaultConferencingApps: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.apple.FaceTime",
        "com.google.Chrome.app.hgfgneokhccnkapfheijbhikenbeeamd", // Chrome Meet PWA
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeets",
        "com.ringcentral.GrannySmith",
    ]

    /// Original sharing type per window, captured before the first shield so
    /// un-shielding restores exactly what the window started with (the enum
    /// case names have shifted across SDKs; the observed value never lies).
    private var originalTypes: [ObjectIdentifier: NSWindow.SharingType] = [:]

    private weak var appDelegate: AppDelegate?
    // nonisolated(unsafe): touched from deinit (nonisolated), same pattern
    // as AppState.retentionTimer / GatedEventMonitor.token.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        observers.append(center.addObserver(forName: .kopieScreenShieldChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        })
        apply()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    func apply() {
        let mode = SettingsStore.shared.screenShieldMode
        let shield: Bool
        switch mode {
        case .always:
            shield = true
        case .whenConferencing:
            shield = isConferencingFrontmost()
        case .off:
            shield = false
        }
        appDelegate?.setCaptureSharingType(shield, originalTypes: &originalTypes)
    }

    private func isConferencingFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Self.defaultConferencingApps.contains(front)
    }
}

extension Notification.Name {
    /// Posted by Settings when the shield mode changes.
    static let kopieScreenShieldChanged = Notification.Name("kopieScreenShieldChanged")
}
