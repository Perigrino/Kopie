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

/// Paste-related key bindings (S-004): the global hotkey (already stored under
/// Keys.hotkey — carried here too so conflict checks see all three at once),
/// the popover's direct-paste key, and the "paste as plain" held modifier.
public struct PasteBindings: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        case globalHotkey, directPaste, plainModifier

        /// Settings row titles (one name per idea — glossary).
        public var label: String {
            switch self {
            case .globalHotkey: return "Global shortcut"
            case .directPaste: return "Direct paste"
            case .plainModifier: return "Paste as plain"
            }
        }
    }

    public var globalHotkey: HotKeySpec
    public var directPaste: HotKeySpec
    public var plainModifier: UInt32

    public static let `default` = PasteBindings(
        globalHotkey: .default,                // ⌘⇧V
        directPaste: .defaultDirectPaste,      // ⌥↩
        plainModifier: UInt32(0x1000))         // hold ⌃ (Carbon controlKey)
}

extension HotKeySpec {
    /// ⌥↩ — the direct-paste default (Carbon optionKey 0x0800, Return keycode 36).
    public static let defaultDirectPaste = HotKeySpec(keyCode: 36, modifiers: 0x0800)
}
