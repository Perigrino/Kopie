import SwiftUI
import AppKit
import Carbon
import KopieCore

/// Human-readable label for a `HotKeySpec`, e.g. "⌘⇧V".
extension HotKeySpec {
    var label: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        parts.append(HotKeyRecorder.keyName(keyCode))
        return parts.joined()
    }
}

/// Button that, when clicked, records the next keydown and stores it as the global hotkey.
struct HotKeyRecorder: View {
    @State private var recording = false
    @State private var errorMessage: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if recording { stopRecording() }
                else {
                    recording = true
                    errorMessage = nil
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if event.keyCode == 53 { // Esc cancels
                            stopRecording()
                            return nil
                        }
                        handle(event)
                        return nil
                    }
                }
            } label: {
                Text(recording ? "Press a key… (Esc to cancel)" : (SettingsStore.shared.hotkey.label))
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 140)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let spec = HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
        if let problem = Self.problem(with: spec) {
            errorMessage = problem
            return
        }
        // Trial-register so combos macOS (or another app) already owns fail loudly
        // instead of silently saving a dead shortcut. On failure UserDefaults is
        // untouched and the notification lets AppDelegate re-register the old spec.
        if HotKeyManager.register(keyCode: spec.keyCode, modifiers: spec.modifiers, handler: {}) {
            SettingsStore.shared.hotkey = spec
            errorMessage = nil
            stopRecording()
        } else {
            errorMessage = "That combination is already in use by the system or another app."
        }
        NotificationCenter.default.post(name: .kopieHotKeyChanged, object: nil)
    }

    /// Rejects combinations that would hijack typing or collide with reserved system shortcuts.
    nonisolated static func problem(with spec: HotKeySpec) -> String? {
        let cmd = UInt32(cmdKey), shift = UInt32(shiftKey), opt = UInt32(optionKey), ctrl = UInt32(controlKey)
        let mods = spec.modifiers
        guard mods & (cmd | shift | opt | ctrl) != 0 else {
            return "Add a modifier key (⌘, ⌥, ⌃, or ⇧) so typing is not hijacked."
        }
        switch spec.keyCode {
        case 48 where mods == cmd: return "⌘Tab switches apps; pick another combination."
        case 49 where mods == cmd: return "⌘Space is Spotlight; pick another combination."
        case 49 where mods == ctrl: return "⌃Space switches input sources; pick another combination."
        case 53 where mods == (cmd | opt): return "⌘⌥Esc is Force Quit; pick another combination."
        default: return nil
        }
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    nonisolated static func keyName(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            13: "S", 17: "T", 32: "U", 9: "V", 16: "W", 7: "X",
            6: "Y", 1: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        ]
        return special[keyCode] ?? "Key\(keyCode)"
    }
}

extension Notification.Name { static let kopieHotKeyChanged = Notification.Name("kopieHotKeyChanged") }
