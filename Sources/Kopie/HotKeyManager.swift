import Carbon
import Foundation
// Minimal hotkey manager — full implementation in Task 11.
final class HotKeyManager {
    static func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> HotKeyManager? {
        let m = HotKeyManager()
        m.handler = handler
        // Register with Carbon (implemented in Task 11)
        return m
    }
    private var handler: (() -> Void)?
}
