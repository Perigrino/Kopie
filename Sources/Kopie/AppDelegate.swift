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
    /// Retains a hosting controller that captures the SwiftUI `openSettings`
    /// action so the AppKit status menu can open the Settings scene natively.
    private var settingsBridge: NSHostingController<SettingsBridge>?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppIcon.menuBarImage()
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 640)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(state))

        // Capture the SwiftUI openSettings action for the AppKit status menu.
        // The hosting view must live inside a real window (the status item's
        // button) so onAppear fires at launch; an unattached hosting controller
        // never appears and never captures the action.
        let bridge = NSHostingController(rootView: SettingsBridge())
        bridge.view.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        statusItem.button?.addSubview(bridge.view)
        settingsBridge = bridge

        GlobalActions.openMain = { [weak self] in self?.showMainWindow() }
        GlobalActions.openOnboarding = { [weak self] in self?.showOnboarding() }
        GlobalActions.closePopover = { [weak self] in self?.popover?.performClose(nil) }

        state.objectWillChange.sink { [weak self] _ in
            self?.applyVisibility()
            self?.closeOnboardingIfDone()
        }
        .store(in: &cancellables)
        applyVisibility()

        registerHotKey()
        NotificationCenter.default.addObserver(forName: .kopieHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
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
        // Activate so the welcome is frontmost and interactive (hover effects,
        // clicks) even though the app stays accessory.
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeOnboardingIfDone() {
        if let win = onboardingWindow, !state.showOnboarding, win.isVisible {
            win.close()
            onboardingWindow = nil
        }
    }

    // MARK: - Status item

    private func applyVisibility() { statusItem.isVisible = SettingsStore.shared.showMenuBarIcon }
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            state.refresh()
        }
    }

    /// Left-click toggles the popover; right-click shows a small menu with Quit.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { togglePopover(); return }
        if event.type == .rightMouseUp {
            popover.performClose(nil)
            statusItem.menu = buildStatusMenu()
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Kopie", action: #selector(openFromMenu), keyEquivalent: "o")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kopie", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { item in
            if item.action != nil { item.target = self }
        }
        return menu
    }

    @objc private func openFromMenu() { GlobalActions.openMain?() }
    @objc private func openSettingsFromMenu() {
        // Prefer the SwiftUI openSettings action captured at launch; fall back
        // to the standard responder-chain action for the Settings scene.
        if let open = GlobalActions.openSettings {
            open()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    func popoverShouldClose(_ p: NSPopover) -> Bool { true }

    func popoverDidShow(_ notification: Notification) {
        // Re-capture the settings action if the status item was hidden at
        // launch (its button — and the bridge — only exist once it's shown).
        if GlobalActions.openSettings == nil,
           let contentView = popover.contentViewController?.view {
            let bridge = NSHostingController(rootView: SettingsBridge())
            bridge.view.frame = .zero
            contentView.addSubview(bridge.view)
            settingsBridge = bridge
        }
    }

    func showFromHotKey() { togglePopover() }

    // MARK: - Hotkey

    private func registerHotKey() {
        let spec = SettingsStore.shared.hotkey
        _ = HotKeyManager.register(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.showFromHotKey() }
        }
    }
}
