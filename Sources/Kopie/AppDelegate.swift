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
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    /// Headless launch probe (--smoke-windows): reports visible windows, then quits.
    private var smokeProbeTimer: Timer?


    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearance()
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

        GlobalActions.openMain = { [weak self] in self?.showMainWindow() }
        GlobalActions.openSettings = { [weak self] in self?.showSettings() }
        GlobalActions.openOnboarding = { [weak self] in self?.showOnboarding() }
        GlobalActions.closePopover = { [weak self] in self?.popover?.performClose(nil) }

        state.objectWillChange.sink { [weak self] _ in
            self?.applyVisibility()
            self?.closeOnboardingIfDone()
        }
        .store(in: &cancellables)
        applyVisibility()

        registerHotKey()
        // Re-apply the appearance whenever the persisted setting changes (the
        // Settings picker and the status menu both write through SettingsStore).
        NotificationCenter.default.addObserver(forName: .kopieAppearanceChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
        NotificationCenter.default.addObserver(forName: .kopieHotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }
        installSmokeProbe()

        if state.showOnboarding {
            DispatchQueue.main.async { GlobalActions.openOnboarding?() }
        }

        // Headless smoke hook: skip onboarding and open the main window directly.
        if CommandLine.arguments.contains("--smoke-main-window") {
            state.showOnboarding = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showMainWindow()
            }
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
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Settings"
            win.setContentSize(NSSize(width: 520, height: 420))
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
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
        let paused = SettingsStore.shared.monitorPaused
        let pauseItem = menu.addItem(withTitle: paused ? "Resume Monitoring" : "Pause Monitoring",
                                     action: #selector(toggleMonitoringFromMenu), keyEquivalent: "")
        pauseItem.image = NSImage(systemSymbolName: paused ? "play.circle" : "pause.circle",
                                  accessibilityDescription: pauseItem.title)
        let clearItem = menu.addItem(withTitle: "Clear History…",
                                     action: #selector(clearHistoryFromMenu), keyEquivalent: "")
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: clearItem.title)
        menu.addItem(.separator())
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()
        for mode in SettingsStore.AppAppearance.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setAppearance(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = mode == SettingsStore.shared.appearance ? .on : .off
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.label)
            appearanceMenu.addItem(item)
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Kopie", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { item in
            if item.action != nil { item.target = self }
        }
        return menu
    }

    /// Persists the chosen appearance and re-applies it to the whole app.
    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SettingsStore.AppAppearance(rawValue: raw) else { return }
        SettingsStore.shared.appearance = mode
        NotificationCenter.default.post(name: .kopieAppearanceChanged, object: nil)
    }

    /// Applies the persisted appearance to every window, popover and menu.
    /// `nil` (system mode) removes the override so the app follows macOS.
    private func applyAppearance() {
        switch SettingsStore.shared.appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @objc private func openFromMenu() { GlobalActions.openMain?() }
    @objc private func openSettingsFromMenu() { showSettings() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    @objc private func toggleMonitoringFromMenu() {
        if SettingsStore.shared.monitorPaused { state.startMonitoring() }
        else { state.pauseMonitoring() }
    }

    /// Clear-all uses the same typed-confirmation dialog as Settings → Encryption.
    @objc private func clearHistoryFromMenu() {
        showMainWindow()
        NotificationCenter.default.post(name: .kopieRequestClearAll, object: nil)
    }

    func popoverShouldClose(_ p: NSPopover) -> Bool { true }

    func popoverDidShow(_ notification: Notification) {}

    // MARK: - Launch probe (--smoke-windows)

    /// Headless probe: reports all visible windows shortly after launch, then
    /// terminates. Catches stray windows (e.g. the blank Settings window SwiftUI
    /// used to present at startup from the vestigial scene).
    private func installSmokeProbe() {
        guard CommandLine.arguments.contains("--smoke-windows") else { return }
        state.showOnboarding = false
        smokeProbeTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportSmokeProbe() }
        }
    }

    private func reportSmokeProbe() {
        let windows = NSApp.windows
            .filter { $0.isVisible && !$0.title.isEmpty }
            .map { "\($0.title)|\(Int($0.frame.width))x\(Int($0.frame.height))" }
        print("WINDOWS \(windows.isEmpty ? "NONE" : windows.joined(separator: ","))")
        exit(0)
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
