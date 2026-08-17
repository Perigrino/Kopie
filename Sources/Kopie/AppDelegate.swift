import SwiftUI
import AppKit
import Combine
import KopieCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: HotKeyManager?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Kopie")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
        }
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 640)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(state))

        state.objectWillChange.sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
        applyVisibility()

        registerHotKey()
        NotificationCenter.default.addObserver(forName: .kopieHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKey()
        }
    }

    private func registerHotKey() {
        let spec = UserDefaults.standard.hotKeySpec
        let ok = HotKeyManager.register(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.showFromHotKey() }
        }
        _ = ok
    }
    private func applyVisibility() { statusItem.isVisible = visibleFromSettings() }
    private func visibleFromSettings() -> Bool {
        (UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool) ?? true
    }
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            state.refresh()
        }
    }
    func popoverShouldClose(_ p: NSPopover) -> Bool { true }
    // Hotkey + onboarding + notifications wired in Milestones 3/4; stubs now:
    func showFromHotKey() { togglePopover() }
}
