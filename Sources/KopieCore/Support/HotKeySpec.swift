import Foundation

/// A global shortcut described by a Carbon virtual key code and Carbon modifier flags.
/// Persisted as JSON under `SettingsStore.Keys.hotkey`.
public struct HotKeySpec: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon modifier values (cmdKey = 0x0100, shiftKey = 0x0200). ⌘⇧V by default.
    public static let `default` = HotKeySpec(keyCode: 9, modifiers: 0x0100 | 0x0200)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}
