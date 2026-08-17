import SwiftUI
import AppKit
import Carbon

/// Small value describing a global shortcut (Carbon key code + modifier flags).
struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeySpec(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey)) // ⌘⇧V

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

extension UserDefaults {
    var hotKeySpec: HotKeySpec {
        get {
            guard let data = data(forKey: "hotkey"),
                  let spec = try? JSONDecoder().decode(HotKeySpec.self, from: data) else {
                return .default
            }
            return spec
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: "hotkey")
            }
        }
    }
}

/// Button that, when clicked, records the next keydown and stores it as the global hotkey.
struct HotKeyRecorder: View {
    @State private var recording = false
    private var monitor: Any?

    var body: some View {
        Button {
            recording = true
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handle(event)
                return nil
            }
        } label: {
            Text(recording ? "Press a key…" : (UserDefaults.standard.hotKeySpec.label))
                .font(.body.monospacedDigit())
                .frame(minWidth: 120)
        }
        .disabled(recording == false ? false : true)
    }

    private func handle(_ event: NSEvent) {
        let spec = HotKeySpec(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags))
        UserDefaults.standard.hotKeySpec = spec
        recording = false
        NotificationCenter.default.post(name: .kopieHotKeyChanged, object: nil)
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    static func keyName(_ keyCode: UInt32) -> String {
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
