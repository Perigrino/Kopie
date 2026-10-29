import Foundation

/// Tracks "the user touched this app recently" for the capture read gate
/// (S-013). On macOS 15+/26, periodic pasteboard reads behind the user's
/// back trigger the system's periodic "app read your clipboard" prompts.
/// We therefore only read when a session interaction is recent, unless the
/// user opts the app back into always-on capture via settings
/// (`captureOnlyWhileInteracting` == false is the default: opted-in).
public struct CaptureRecency: Sendable {
    /// An interaction counts toward reads for this long, in seconds.
    public let activeWindow: TimeInterval
    private var lastActivity: Date?
    private var touchedAnyTime: Bool

    public init(activeWindow: TimeInterval = 90) {
        self.activeWindow = activeWindow
        self.lastActivity = nil
        self.touchedAnyTime = false
    }

    public mutating func touch(_ now: Date = .now) {
        lastActivity = now
        touchedAnyTime = true
    }

    /// True when the app may read the pasteboard on this tick: touched
    /// within `activeWindow` at `now` (inclusive boundary).
    public func mayRead(_ now: Date = .now) -> Bool {
        guard touchedAnyTime, let last = lastActivity else { return false }
        return now.timeIntervalSince(last) <= activeWindow
    }
}
