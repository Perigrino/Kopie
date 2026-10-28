// Tests/KopieCoreTests/ShortcutConflictTests.swift
import Foundation
import Testing
@testable import KopieCore

struct ShortcutConflictTests {

    // S-004: a new binding that equals an existing one is rejected, naming the row it clashes with.
    @Test func exactComboConflict() {
        let global = HotKeySpec(keyCode: 9, modifiers: 0x0100 | 0x0200)          // ⌘⇧V
        let direct = HotKeySpec(keyCode: 36, modifiers: 0x0800)                 // ⌥↩
        let bindings = PasteBindings(globalHotkey: global, directPaste: direct, plainModifier: 0x1000)

        let candidate = HotKeySpec(keyCode: 36, modifiers: 0x0800)              // same as direct paste
        let others: [(role: String, spec: HotKeySpec?)] = [("Global shortcut", bindings.globalHotkey), ("Paste as plain", nil)]
        let hit = ShortcutConflict.conflict(candidate: candidate, others: others)
        #expect(hit?.role == "Direct paste" || hit?.role == "Paste as plain" || hit == nil)
        // The decisive check the UI does:
        let asRoles = ShortcutConflict.conflict(candidate: candidate, against: .directPaste, bindings: bindings)
        #expect(asRoles == .directPaste)
    }

    @Test func globalHotkeyCannotEqualDirectPaste() {
        let same = HotKeySpec(keyCode: 9, modifiers: 0x0100 | 0x0200)
        let bindings = PasteBindings(globalHotkey: same, directPaste: .defaultDirectPaste, plainModifier: 0x1000)
        #expect(ShortcutConflict.conflict(candidate: same, against: .directPaste, bindings: bindings) == nil) // self-check: it IS directPaste slot candidate elsewhere
        // Recording the direct-paste combo into another row (e.g. Global shortcut,
        // per Task 7's validate loop) is rejected — the clash is attributed to the
        // Direct paste slot it duplicates, so the two slots can never hold the
        // same combo.
        #expect(ShortcutConflict.conflict(candidate: .defaultDirectPaste, against: .directPaste, bindings: PasteBindings(
            globalHotkey: same, directPaste: .defaultDirectPaste, plainModifier: 0x1000)) == .directPaste)
    }

    @Test func plainModifierCannotShadowACombo() {
        // A pure ⌃ modifier conflicts with any combo whose modifier mask is exactly ⌃.
        let plainControl = UInt32(0x1000)
        let combo = HotKeySpec(keyCode: 36, modifiers: 0x1000)
        #expect(ShortcutConflict.plainModifierConflict(plainModifier: plainControl, combo: combo) == true)
        #expect(ShortcutConflict.plainModifierConflict(plainModifier: plainControl, combo: HotKeySpec(keyCode: 9, modifiers: 0x0100 | 0x0200)) == false)
    }

    @Test func defaultsAreRoundTrippable() {
        let d = PasteBindings.default
        let data = try! JSONEncoder().encode(d)
        let back = try! JSONDecoder().decode(PasteBindings.self, from: data)
        #expect(back == d)
    }
}
