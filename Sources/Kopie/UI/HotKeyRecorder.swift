import SwiftUI
import AppKit
import Carbon
import KopieCore

extension HotKeySpec {
    /// Human-readable label, e.g. "⌘⇧V".
    var label: String {
        var parts: [String] = []
        if modifiers & 0x0100 != 0 { parts.append("⌘") }   // cmdKey
        if modifiers & 0x0200 != 0 { parts.append("⇧") }   // shiftKey
        if modifiers & 0x0800 != 0 { parts.append("⌥") }   // optionKey
        if modifiers & 0x1000 != 0 { parts.append("⌃") }   // controlKey
        parts.append(HotKeyRecorder.keyName(keyCode))
        return parts.joined()
    }
}

/// Button that, when clicked, records the next keydown and stores it as the global hotkey.
struct HotKeyRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if recording { stopRecording() }
            else {
                recording = true
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
            Text(recording ? "Press a key… (Esc to cancel)" : SettingsStore.shared.hotkey.label)
                .font(.body.monospacedDigit())
                .frame(minWidth: 140)
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let spec = HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
        SettingsStore.shared.hotkey = spec
        stopRecording()
        NotificationCenter.default.post(name: .kopieHotKeyChanged, object: nil)
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= 0x0100 }
        if flags.contains(.shift) { mods |= 0x0200 }
        if flags.contains(.option) { mods |= 0x0800 }
        if flags.contains(.control) { mods |= 0x1000 }
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
