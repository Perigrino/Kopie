import AppKit
import ApplicationServices
import Carbon.HIToolbox
import KopieCore

/// Pastes the current clipboard contents into the frontmost application by
/// simulating ⌘V, closing the copy→paste loop in one keystroke (Maccy-style
/// ⌥↩ / ⌥-click). Requires the Accessibility (AXIsProcessTrusted) permission.
///
/// All *decisions* live in `KopieCore.PastePlan` (unit-tested); this type only
/// reads system state and posts the events.
@MainActor
enum PasteDirectService {

    /// True when Kopie may synthesize key events (Accessibility granted).
    static var isPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    /// True while Secure Input is active session-wide (password field focused).
    /// Synthetic key events posted now are silently swallowed by the system,
    /// so the paste plan aborts before posting (S-001).
    ///
    /// `CGEventSourceGetSecureInputEnabled` / `CGEventSource.secureInputEnabled`
    /// are not exported by the CoreGraphics stub, so the public Carbon probe
    /// does the same job: it reports whether Secure Event Input is active for
    /// this login session (any process, system-wide effect).
    static var isSecureInputActive: Bool {
        IsSecureEventInputEnabled()
    }

    /// Opens the System Settings pane where the user can grant Accessibility.
    /// `AXIsProcessTrustedWithOptions` runs off the main actor to sidestep the
    /// non-Sendable global constant under Swift 6 strict concurrency; it is a
    /// stateless system call.
    nonisolated static func requestPermission() {
        DispatchQueue.global().async {
            // kAXTrustedCheckOptionPrompt is a C global that Swift 6 treats as
            // non-Sendable. Its value is the constant "AXTrustedCheckOptionPrompt";
            // referencing that literal directly keeps the stateless system call
            // free of actor isolation, which is exactly what Apple's AX API expects.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    /// Jumps straight to Privacy & Security → Accessibility, where the grant
    /// lives. Pointing at the pane beats describing it: the system's own prompt
    /// only offers "Open System Settings", which lands the user on the privacy
    /// front door with the right list still to find.
    static func openAccessibilitySettings() {
        // The anchor changed across macOS releases; try the current one first
        // and fall back to the privacy root rather than doing nothing.
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    /// The plan-consulting executor. `postToPID` routes the ⌘V into the target
    /// app's own event queue instead of the session-wide tap — that queue-hop is
    /// what keeps Electron/terminal/VM targets from eating the keystroke (S-002).
    /// Returns the plan outcome; on `.fallback` nothing was posted and the caller
    /// surfaces the obstacle (the clip remains staged on the pasteboard).
    @discardableResult
    static func attempt(delayMs: UInt32 = 80,
                        attemptsMade: Int = 0,
                        postToPID: pid_t? = nil) -> PasteOutcome {
        let input = PasteInput(axGranted: isPermissionGranted,
                               secureInputActive: isSecureInputActive,
                               attemptsMade: attemptsMade)
        let decision = PastePlan.decide(input)
        PasteLog.logger.info("decision=\(decision.logString, privacy: .public) attempts=\(attemptsMade) secure=\(isSecureInputActive) ax=\(isPermissionGranted)")
        switch decision {
        case .post, .retry:
            schedulePost(delayMs: delayMs, postToPID: postToPID)
        case .fallback:
            break
        }
        return decision
    }

    /// Legacy boolean wrapper retained until Task 3 rewires the last callers.
    @discardableResult
    static func paste(delayMs: UInt32 = 80) -> Bool {
        if case .fallback = attempt(delayMs: delayMs) { return false }
        return true
    }

    private static func schedulePost(delayMs: UInt32, postToPID: pid_t?) {
        let post = { postKeyEvents(postToPID: postToPID) }
        if delayMs > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs))) {
                MainActor.assumeIsolated { post() }
            }
        } else {
            post()
        }
    }

    /// 0x09 = v. Posts down then ⌘V up with a 10ms gap, into `pid`'s queue when
    /// the target is another process, else the session-wide event tap.
    private static func postKeyEvents(postToPID: pid_t?) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        down?.flags = [.maskCommand]
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        up?.flags = [.maskCommand]
        guard let down, let up else { return }
        if let pid = postToPID, pid != ProcessInfo.processInfo.processIdentifier {
            down.postToPid(pid)
            usleep(10_000)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            usleep(10_000)
            up.post(tap: .cghidEventTap)
        }
    }
}

private extension PasteOutcome {
    /// os.Logger interpolation accepts a String; map the enum once here.
    var logString: String {
        switch self {
        case .post: return "post"
        case .retry: return "retry"
        case .fallback(let obstacle): return "fallback:\(obstacle.rawValue)"
        }
    }
}
