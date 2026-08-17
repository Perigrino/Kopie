import SwiftUI
import AppKit
import Combine
import KopieCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let state = AppState()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var mainWindow: NSWindow?
    private var onboardingWindow: NSWindow?
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

        GlobalActions.openMain = { [weak self] in self?.showMainWindow() }
        GlobalActions.openSettings = { [weak self] in self?.showSettings() }
        GlobalActions.openOnboarding = { [weak self] in self?.showOnboarding() }

        state.objectWillChange.sink { [weak self] _ in
            self?.applyVisibility()
            self?.closeOnboardingIfDone()
        }
        .store(in: &cancellables)
        applyVisibility()

        registerHotKey()
        NotificationCenter.default.addObserver(forName: .kopieHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKey()
        }

        if state.showOnboarding {
            DispatchQueue.main.async { GlobalActions.openOnboarding?() }
        }
    }

    // MARK: - Windows

    func showMainWindow() {
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Kopie"
            win.setContentSize(NSSize(width: 900, height: 560))
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.center()
            mainWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let hosting = NSHostingController(rootView: OnboardingView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Welcome to Kopie"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            onboardingWindow = win
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func closeOnboardingIfDone() {
        if let win = onboardingWindow, !state.showOnboarding, win.isVisible {
            win.close()
            onboardingWindow = nil
        }
    }

    private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Status item

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
    func showFromHotKey() { togglePopover() }

    // MARK: - Hotkey

    private func registerHotKey() {
        let spec = UserDefaults.standard.hotKeySpec
        _ = HotKeyManager.register(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.showFromHotKey() }
        }
    }
}
