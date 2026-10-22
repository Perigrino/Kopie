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
    /// Floating chat-bubble preview beside the popover list.
    private var previewPanel: PreviewPanelController!
    /// Hides Kopie's windows from screen capture per the ScreenShield setting.
    private var screenShield: ScreenShield!
    /// Headless launch probe (--smoke-windows): reports visible windows, then quits.
    private var smokeProbeTimer: Timer?
    /// The app that was frontmost when the popover took focus. The popover
    /// activates Kopie so its window can be key (first click lands, search
    /// field focused); this is what gets handed focus back when it closes, and
    /// the app ⌘V must reach. nil when Kopie was already frontmost.
    private var prePopoverApp: NSRunningApplication?
    /// True once this launch has raised the system's Accessibility dialog.
    /// `AXIsProcessTrustedWithOptions(prompt:)` re-shows it on every call while
    /// the grant is missing, so without this each click became a modal prompt.
    private var axPromptShown = false

    /// Shields (or unshields) every Kopie window. Each window's original
    /// sharing type is remembered on first shield so un-shielding restores
    /// exactly what the window was created with.
    func setCaptureSharingType(_ shield: Bool, originalTypes: inout [ObjectIdentifier: NSWindow.SharingType]) {
        for win in NSApp.windows where isKopieWindow(win) {
            let key = ObjectIdentifier(win)
            if originalTypes[key] == nil { originalTypes[key] = win.sharingType }
            win.sharingType = shield ? .none : (originalTypes[key] ?? .none)
        }
    }

    /// Kopie-owned windows only — never system windows that happen to be
    /// listed (menus, the status-bar window).
    private func isKopieWindow(_ win: NSWindow) -> Bool {
        win === mainWindow || win === settingsWindow || win === onboardingWindow
            || win === popover?.contentViewController?.view.window
            || win === previewPanel?.panelWindow
    }


    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearance()
        // App Intents surface: hand the live state to the intents bridge.
        KopieStateBridge.register(KopieStateHandle(state: state))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = AppIcon.menuBarImage(paused: state.isPaused)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover = NSPopover()
        popover.contentSize = NSSize(width: 440, height: 640)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(state))
        // One-time registration so the popover's event handlers can tell
        // which window an event belongs to (see GlobalActions.isPopoverKeyEvent).
        GlobalActions.bindPopover(popover)

        previewPanel = PreviewPanelController(state: state)
        previewPanel.popover = popover
        screenShield = ScreenShield(appDelegate: self)
        // Clicks on the menu-bar icon belong to the popover's toggle, not to
        // "outside": without this, the icon's own press would collapse the
        // popover on mouse-down and re-open it on mouse-up.
        previewPanel.shouldIgnoreClick = { [weak self] loc in
            guard let self, let win = self.statusItem.button?.window else { return false }
            return win.frame.contains(loc)
        }

        // Opening any app window closes the popover first. The popover's
        // local event monitors see the whole process, so leaving it "open"
        // while another window takes focus left stale keyboard state pointed
        // at the popover — arrows/clicks in the main window were visibly
        // routed to the menu-bar list instead.
        GlobalActions.openMain = { [weak self] in self?.showMainWindow(closePopover: true) }
        GlobalActions.openSettings = { [weak self] in self?.showSettings(closePopover: true) }
        GlobalActions.openOnboarding = { [weak self] in self?.showOnboarding(closePopover: true) }
        GlobalActions.closePopover = { [weak self] in self?.popover?.performClose(nil) }
        GlobalActions.pasteWhenFocusReturns = { [weak self] in self?.pasteWhenFocusReturns() }
        GlobalActions.requestPastePermission = { [weak self] in self?.requestAccessibilityOnce() }
        GlobalActions.showPreview = { [weak self] item, y in self?.previewPanel.preview(item, rowY: y) }
        GlobalActions.movePreview = { [weak self] item, y in self?.previewPanel.move(item, rowY: y) }
        GlobalActions.clearPreview = { [weak self] seconds in self?.previewPanel.scheduleClear(after: seconds) }

        state.objectWillChange.sink { [weak self] _ in
            self?.applyVisibility()
            self?.closeOnboardingIfDone()
        }
        .store(in: &cancellables)
        // `isPaused` is set together with `monitorPaused` in start/pauseMonitoring,
        // so the bar glyph tracks monitoring without a separate notification.
        state.$isPaused
            .removeDuplicates()
            .sink { [weak self] paused in
                self?.statusItem.button?.image = AppIcon.menuBarImage(paused: paused)
            }
            .store(in: &cancellables)
        applyVisibility()

        registerHotKey()
        // Resolve source-app icons before the popover is ever opened. The first
        // render used to pay for NSWorkspace lookups and offscreen image draws
        // row by row — on the critical path of the very click that revealed
        // them. Deferred so launch itself isn't held up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.prewarmRowIcons()
        }
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

    func showMainWindow(closePopover: Bool = false) {
        prePopoverApp = nil   // the user is coming to Kopie on purpose: don't bounce focus back out
        if closePopover { popover?.performClose(nil) }
        if mainWindow == nil {
            let hosting = NSHostingController(rootView: MainView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Kopie"
            // Fixed geometry: the main window opens at the approved
            // 1518 × 1102 frame and does not resize (clamped to a
            // smaller display's visible frame).
            let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            win.setContentSize(NSSize(width: min(1518, vf.width), height: min(1102, vf.height)))
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            mainWindow = win
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(closePopover: Bool = false) {
        prePopoverApp = nil
        if closePopover { popover?.performClose(nil) }
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(state))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Settings"
            win.setContentSize(NSSize(width: 660, height: 520))
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showOnboarding(closePopover: Bool = false) {
        prePopoverApp = nil
        if closePopover { popover?.performClose(nil) }
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
            beginPopoverShow(pasteOnClick: false)   // menu-bar icon: copy only
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            endPopoverShow()
        }
    }

    /// Everything that has to happen before the popover's window exists.
    ///
    /// The refresh moved here from after `show(...)`: the popup used to appear
    /// first and query afterwards, so the list landed a beat late (and the very
    /// first open flashed its empty state before any rows were fetched).
    /// Activation is what makes the *first* click land — an accessory app whose
    /// window never becomes active spends the opening mouse-down on activation
    /// instead of on the row, which is why a row used to need two or three
    /// clicks before anything was copied. The app that had focus is recorded
    /// first so it can be handed back on close.
    private func beginPopoverShow(pasteOnClick: Bool) {
        let front = NSWorkspace.shared.frontmostApplication
        prePopoverApp = (front?.processIdentifier == ProcessInfo.processInfo.processIdentifier) ? nil : front
        // Which popover this is decides whether a plain click may paste — see
        // AppState.pasteOnClickEnabled.
        state.pasteOnClickEnabled = pasteOnClick
        state.refresh()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func endPopoverShow() {
        if let w = popover.contentViewController?.view.window { w.level = .popUpMenu; w.makeKey() }
    }

    /// Warms `AppIconResolver` for the source apps already in history so the
    /// popover's first paint doesn't resolve them inline. Matches the 10×10
    /// size HistoryRow asks for — the cache is keyed by size, so any other
    /// size would warm the wrong entry.
    private func prewarmRowIcons() {
        let size = NSSize(width: 10, height: 10)
        for bundleID in Set(state.items.compactMap(\.sourceApp)) {
            _ = AppIconResolver.icon(for: bundleID, size: size)
        }
    }

    /// Invisible 1×1 window the hotkey popover anchors to; lives only while
    /// the popover is shown.
    private var cursorAnchor: NSWindow?

    /// ⌘⇧V: opens the list at the cursor so it lands next to whatever the
    /// user was just working in. Flips above the cursor near the screen
    /// bottom, like a context menu.
    func togglePopoverAtCursor() {
        if popover.isShown { popover.performClose(nil); return }
        let mouse = NSEvent.mouseLocation
        let anchor = NSWindow(contentRect: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1),
                              styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.hasShadow = false
        anchor.ignoresMouseEvents = true
        anchor.isReleasedWhenClosed = false
        anchor.orderFront(nil)
        cursorAnchor?.close()
        cursorAnchor = anchor
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let edge: NSRectEdge = (mouse.y - popover.contentSize.height < (screen?.visibleFrame.minY ?? 0))
            ? .maxY : .minY
        beginPopoverShow(pasteOnClick: true)        // global hotkey: click may paste
        popover.show(relativeTo: NSRect(x: 0, y: 0, width: 1, height: 1),
                     of: anchor.contentView!, preferredEdge: edge)
        endPopoverShow()
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
        // Sequential paste queue controls.
        let qn = state.pasteQueueCount
        if qn > 0 {
            let next = menu.addItem(withTitle: "Paste Next (\(qn) queued)",
                                    action: #selector(pasteNextFromMenu), keyEquivalent: "")
            next.image = NSImage(systemSymbolName: "arrow.down.to.line.compact",
                                 accessibilityDescription: next.title)
            let clearQ = menu.addItem(withTitle: "Clear Paste Queue",
                                      action: #selector(clearPasteQueueFromMenu), keyEquivalent: "")
            clearQ.image = NSImage(systemSymbolName: "xmark.circle",
                                   accessibilityDescription: clearQ.title)
        }
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

    @objc private func pasteNextFromMenu() {
        _ = state.pasteNextFromQueue()
    }

    @objc private func clearPasteQueueFromMenu() {
        state.clearPasteQueue()
    }

    /// Clear-all uses the same typed-confirmation dialog as Settings → Encryption.
    @objc private func clearHistoryFromMenu() {
        showMainWindow()
        NotificationCenter.default.post(name: .kopieRequestClearAll, object: nil)
    }

    // MARK: - Focus hand-back & direct paste

    /// Hands focus back to the app that was frontmost before the popover
    /// opened. Only acts while Kopie itself holds focus — if the user has
    /// already clicked into some other app, that choice wins and we stay out
    /// of the way rather than yanking focus back to the original one.
    private func restoreFrontmostApp() {
        guard let target = prePopoverApp, !target.isTerminated else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let kopieFrontmost = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        guard kopieFrontmost || front == nil else { return }
        guard front?.processIdentifier != target.processIdentifier else { return }
        if #available(macOS 14.0, *) { _ = target.activate() }
        else { _ = target.activate(options: [.activateIgnoringOtherApps]) }
    }

    /// Closes the popover, returns focus to the interrupted app, and pastes
    /// into it once it is genuinely frontmost again.
    ///
    /// The old path fired ⌘V on a blind 150ms timer with no focus bookkeeping
    /// at all: Kopie had activated itself to show the popover, so the keystroke
    /// frequently went to Kopie (or to nothing) and the caret never received
    /// the item. Waiting for the actual frontmost app removes the guesswork.
    private func pasteWhenFocusReturns() {
        guard let target = prePopoverApp else {
            // Kopie was already frontmost before the popover opened — there is
            // no other app to hand back to, so paste straight away.
            firePaste()
            return
        }
        restoreFrontmostApp()
        var attempts = 0
        func step() {
            attempts += 1
            let back = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
            if !back && attempts < 20 {          // ≤ ~0.6s of waiting
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { MainActor.assumeIsolated { step() } }
                return
            }
            if !back { restoreFrontmostApp() }   // last attempt: activate, then paste anyway
            // One run-loop turn so the target's window is key before ⌘V lands.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                MainActor.assumeIsolated { self?.firePaste() }
            }
        }
        step()
    }

    /// Raises the system's Accessibility dialog — at most once per launch.
    /// `AXIsProcessTrustedWithOptions(prompt:)` shows it again on every call
    /// for as long as the grant is missing, which is exactly what turned each
    /// paste attempt into a permission prompt.
    private func requestAccessibilityOnce() {
        guard !axPromptShown else { return }
        axPromptShown = true
        PasteDirectService.requestPermission()
    }

    /// Simulates ⌘V, or tells the user why it can't when Accessibility is
    /// missing. The popover is already gone at this point, so failing silently
    /// reads as "my click did nothing" — hence the notification. The system
    /// dialog itself is raised once per launch, never once per click.
    private func firePaste() {
        if PasteDirectService.paste(delayMs: 0) { return }
        requestAccessibilityOnce()
        KopieNotifications.show(
            title: "Paste Blocked",
            message: "Grant Kopie Accessibility access in System Settings → Privacy & Security, then reopen Kopie. Your clipboard still has the item — press ⌘V to paste it.")
    }

    func popoverShouldClose(_ p: NSPopover) -> Bool { true }

    func popoverDidShow(_ notification: Notification) {
        // The popover's window is created lazily on first show; re-apply the
        // shield so a freshly created window starts with the right sharingType.
        screenShield?.apply()
    }

    func popoverDidClose(_ notification: Notification) {
        cursorAnchor?.close()
        cursorAnchor = nil
        previewPanel?.popoverDidClose()
        // Kopie activated itself to open the popover; give the user their app
        // back so Escape or an outside click leaves them where they were.
        restoreFrontmostApp()
    }

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

    func showFromHotKey() { togglePopoverAtCursor() }

    // MARK: - Hotkey

    private func registerHotKey() {
        let spec = SettingsStore.shared.hotkey
        let ok = HotKeyManager.register(keyCode: spec.keyCode, modifiers: spec.modifiers) { [weak self] in
            MainActor.assumeIsolated { self?.showFromHotKey() }
        }
        // A silently-failed registration means the global hotkey is simply
        // dead — impossible to debug from user behavior alone.
        if ok {
            NSLog("Kopie hotkey registered (keyCode=%d, modifiers=%#x)", spec.keyCode, spec.modifiers)
        } else {
            NSLog("Kopie hotkey REGISTRATION FAILED (keyCode=%d, modifiers=%#x) — combo likely owned by another app", spec.keyCode, spec.modifiers)
        }
    }
}
