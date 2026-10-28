// Sources/KopieCore/Support/ShortcutConflict.swift
import Foundation

/// Pure conflict rules for paste bindings — the settings UI renders the
/// violations, this decides them (no silent override, S-004).
public enum ShortcutConflict {

    /// `candidate` (a full key + modifier combo) versus one saved role slot.
    public static func conflict(candidate: HotKeySpec,
                                against role: PasteBindings.Role,
                                bindings: PasteBindings) -> PasteBindings.Role? {
        let other: HotKeySpec
        switch role {
        case .globalHotkey: other = bindings.globalHotkey
        case .directPaste: other = bindings.directPaste
        case .plainModifier: return plainModifierConflict(plainModifier: bindings.plainModifier, combo: candidate) ? .plainModifier : nil
        }
        return other == candidate ? role : nil
    }

    /// `candidate` versus every other saved slot; first conflict wins.
    public static func conflict(candidate: HotKeySpec, others: [(role: String, spec: HotKeySpec?)]) -> (role: String, spec: HotKeySpec?)? {
        others.first { $0.spec == candidate }
    }

    /// A held plain modifier (no key) shadows any combo whose modifier mask is
    /// exactly that modifier — e.g. binding "Paste as plain" to ⌃ while a combo
    /// is also bare ⌃ would make one keystroke do both jobs.
    public static func plainModifierConflict(plainModifier: UInt32, combo: HotKeySpec) -> Bool {
        combo.modifiers == plainModifier
    }
}
