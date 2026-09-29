import AppKit
import ApplicationServices

/// Pastes the current clipboard contents into the frontmost application by
/// simulating ⌘V, closing the copy→paste loop in one keystroke (Maccy-style
/// ⌥↩ / ⌥-click). Requires the Accessibility (AXIsProcessTrusted) permission.
@MainActor
enum PasteDirectService {

    /// True when Kopie may synthesize key events (Accessibility granted).
    static var isPermissionGranted: Bool {
        AXIsProcessTrusted()
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

    /// Simulates ⌘V in the frontmost app after `delayMs`, giving the caller
    /// time to hide the popover first. Returns false when the permission is
    /// missing (caller should offer onboarding instead).
    @discardableResult
    static func paste(delayMs: UInt32 = 80) -> Bool {
        guard isPermissionGranted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = v
        keyDown?.flags = [.maskCommand]
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = [.maskCommand]
        if delayMs > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs))) { fire(down: keyDown, up: keyUp) }
        } else {
            fire(down: keyDown, up: keyUp)
        }
        return true
    }

    private static func fire(down: CGEvent?, up: CGEvent?) {
        guard let down, let up else { return }
        down.post(tap: .cghidEventTap)
        usleep(10_000)
        up.post(tap: .cghidEventTap)
    }
}
