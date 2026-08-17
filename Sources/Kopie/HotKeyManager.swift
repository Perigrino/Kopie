import Carbon
import Foundation

/// Registers a system-wide hotkey via Carbon and fires a handler on press.
final class HotKeyManager {
    nonisolated(unsafe) private static var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private static var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private static var handler: (() -> Void)?

    /// - Parameters:
    ///   - keyCode: Carbon virtual key code (e.g. 9 = V).
    ///   - modifiers: Carbon modifier flags (cmdKey | shiftKey | ...).
    static func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let handlerUPP: EventHandlerUPP = { _, _, _ in
            HotKeyManager.handler?()
            return noErr
        }
        guard InstallEventHandler(GetEventDispatcherTarget(), handlerUPP, 1, &eventType, nil, &eventHandlerRef) == noErr else {
            return false
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4F5045), id: 1) // "KOPE"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            unregister()
            return false
        }
        return true
    }

    static func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
        handler = nil
    }

}
