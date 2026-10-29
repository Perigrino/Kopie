import Foundation
import KopieCore
import AppKit
import SwiftUI

enum SelfTest {
    static func run(_ args: [String]) -> Bool {
        guard let first = args.first else { return false }
        let store = ClipStore()
        let writer = DiskClipWriter()
        let pipe = CapturePipeline(store: store, writer: writer)
        let cfg = CaptureConfig(paused: false)   // smoke always captures
        // ensure storage dir is isolated via KOPIE_STORAGE_DIR (set by caller)
        switch first {
        case "--smoke-capture":
            let text = args.count > 1 ? args[1] : "smoke"
            let r = pipe.process(.init(kind: .text(text), sourceAppID: nil), config: cfg)
            if case .captured(let id) = r { print("ID \(id)") } else { print("RESULT \(r)") }
        case "--smoke-capture-image":
            guard args.count > 1, let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])) else { print("ERR no image"); return true }
            let r = pipe.process(.init(kind: .image(data), sourceAppID: nil), config: cfg)
            if case .captured(let id) = r { print("ID \(id)") } else { print("RESULT \(r)") }
        case "--smoke-capture-richtext":
            // Seeds a rich-text item from an .html or .rtf file, then verifies the
            // full round-trip: relPath set, data readable, parses with formatting.
            guard args.count > 1, let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])) else { print("ERR no file"); return true }
            let isHTML = args[1].hasSuffix(".html")
            let plain: String
            if isHTML {
                plain = NSAttributedString(html: data, documentAttributes: nil)?.string ?? "rich"
            } else {
                plain = NSAttributedString(rtf: data, documentAttributes: nil)?.string ?? "rich"
            }
            let kind: CapturedContent.Kind = isHTML ? .textWithHTML(plain, data) : .textWithRichText(plain, data)
            let r = pipe.process(.init(kind: kind, sourceAppID: "com.apple.Safari"), config: cfg)
            guard case .captured(let id) = r, let item = store.get(id) else { print("RESULT \(r)"); return true }
            guard let rel = item.richTextRelPath else { print("FAIL no richTextRelPath"); return true }
            guard let loaded = writer.loadRichText(relPath: rel) else { print("FAIL loadRichText nil"); return true }
            let parsed = isHTML ? NSAttributedString(html: loaded, documentAttributes: nil)
                                : NSAttributedString(rtf: loaded, documentAttributes: nil)
            var hasBold = false
            parsed?.enumerateAttribute(.font, in: NSRange(0..<(parsed?.length ?? 0))) { v, _, _ in
                if let f = v as? NSFont, f.fontDescriptor.symbolicTraits.contains(.bold) { hasBold = true }
            }
            print("ID \(id) rel=\(rel) loaded=\(loaded.count)B parsed=\(parsed != nil) bold=\(hasBold)")
        case "--smoke-restore":
            guard args.count > 1, let id = Int64(args[1]) else { print("ERR id"); return true }
            if let item = store.get(id) {
                let svc = RestoreService(); svc.restore(item, writer: writer); print("RESTORED \(item.kind.rawValue)")
            } else { print("ERR notfound") }
        case "--smoke-list":
            for it in store.query(.init(limit: 50)) {
                print("\(it.id) \(it.kind.rawValue) \(it.createdAt.timeIntervalSince1970) \(it.preview)")
            }
        case "--smoke-count":
            print("COUNT \(store.count())")
        case "--smoke-purge":
            let days = args.count > 1 ? Double(args[1]) ?? 7 : 7
            let delFav = (args.count > 2 && args[2] == "fav")
            let p = RetentionJob(store: store)
            let n = p.run(config: .init(period: RetentionPeriod(rawValue: Int(days)) ?? .daySeven, deleteFavorites: delFav))
            print("PURGED \(n) remaining \(store.count())")
        case "--smoke-readboard":
            let b = NSPasteboard.general
            if let s = b.string(forType: .string) { print("TEXT \(s)") }
            print("TYPES \(b.types?.map { "\($0)" } ?? [])")
        case "--smoke-fav", "--smoke-pin":
            // Sets favorite/pin on an item so the on-state chrome can be
            // rendered (`--smoke-fav <id> on|off` / `--smoke-pin <id> on|off`).
            guard args.count > 1, let id = Int64(args[1]) else { print("ERR id"); return true }
            guard store.get(id) != nil else { print("ERR notfound"); return true }
            let on = args.count < 3 || args[2] != "off"
            if args[0] == "--smoke-fav" { store.setFavorite(id, on) } else { store.setPinned(id, on) }
            print("\(args[0]) \(id) on=\(on)")
        case "--smoke-render":
            // Renders DetailsPanel for an item offscreen and writes PNG snapshots
            // to /tmp for visual verification. Pass "dark" as arg 3 for dark mode.
            guard args.count > 1, let id = Int64(args[1]) else { print("ERR id"); return true }
            guard let item = store.get(id) else { print("ERR notfound"); return true }
            let dark = args.count > 2 && args[2] == "dark"
            MainActor.assumeIsolated { renderDetailsPanel(item: item, dark: dark) }
        case "--smoke-render-popover":
            // Renders PopoverView offscreen (pure list baseline — the preview
            // lives in its own panel now) and writes a PNG to /tmp.
            MainActor.assumeIsolated {
                renderPopover(dark: args.contains("dark"))
            }
        case "--smoke-render-settings":
            // Renders a settings tab offscreen. Arg: tab name (general,
            // clipboard, cleanup, privacy, storage, security).
            MainActor.assumeIsolated {
                renderSettings(tab: args.count > 1 ? args[1] : "privacy")
            }
        case "--smoke-render-main":
            // Renders MainView (sidebar + list + detail) offscreen for
            // README screenshots. Honors KOPIE_STORAGE_DIR for demo stores.
            // Optional size arg: --smoke-render-main 1518x1102 [dark]
            MainActor.assumeIsolated {
                let sizeArg = args.dropFirst().first { $0.contains("x") && $0.range(of: #"^\d+x\d+$"#, options: .regularExpression) != nil }
                renderMain(dark: args.contains("dark"), size: sizeArg.flatMap { size -> NSSize? in
                    let parts = size.split(separator: "x").compactMap { Int($0) }
                    return parts.count == 2 ? NSSize(width: parts[0], height: parts[1]) : nil
                })
            }
        case "--smoke-render-onboarding":
            // Renders the onboarding window offscreen. Args: [step(0-4)] ["dark"]
            // ["splash"] — "splash" fakes a return-launch splash, an integer
            // step renders that onboarding step.
            MainActor.assumeIsolated {
                renderOnboarding(arg: args.count > 1 ? args[1] : "0", dark: args.contains("dark"))
            }
        case "--smoke-render-bubble":
            // Renders the floating preview bubble offscreen. Args: [id |
            // "text" | "image"] [dark] — kind picks the first matching item.
            guard args.count > 1, args[1] != "dark" else {
                print("ERR usage: --smoke-render-bubble <id|text|image> [dark]")
                return true
            }
            let item: ClipboardItem?
            if let id = Int64(args[1]) {
                item = store.get(id)
            } else {
                item = store.query(.init(limit: 500)).first { $0.kind.rawValue == args[1] }
            }
            guard let item else { print("ERR no item \(args[1])"); return true }
            MainActor.assumeIsolated {
                renderBubble(item: item, dark: args.contains("dark"))
            }
        case "--smoke-render-confirm":
            // Renders ConfirmDialog offscreen. Args: [danger|plain|privacy] [dark]
            // — privacy fake-requires typing a phrase.
            MainActor.assumeIsolated {
                renderConfirm(kind: args.count > 1 && args[1] != "dark" ? args[1] : "danger",
                              dark: args.contains("dark"))
            }
        case "--smoke-paste-plan":
            // App-target smoke of the KopieCore.PastePlan decision machine
            // (S-001/S-002/S-003): the decision table plus the live Secure
            // Input probe. Backs the [manual] paste matrix in acceptance.sh.
            MainActor.assumeIsolated { checkPastePlan() }
        case "--smoke-rapid-capture":
            // S-010 [self]: 50 copies ≤500 ms apart all land, in order. Pumping
            // the run loop lets the monitor's 150 ms timer tick 2-3× per write.
            MainActor.assumeIsolated { smokeRapidCapture() }
        case "--smoke-own-write":
            // S-011 [self]: capture⇨paste-back⇄capture leaves history unchanged.
            MainActor.assumeIsolated { smokeOwnWriteCycle() }
        case "--smoke-render-loading":
            // Renders the spec's "Loading" skeleton demo offscreen.
            MainActor.assumeIsolated {
                renderLoading(dark: args.contains("dark"))
            }
        default:
            return false
        }
        return true
    }

    @MainActor
    private static func renderDetailsPanel(item: ClipboardItem, dark: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let host = NSHostingController(rootView: AnyView(DetailsPanel(item: item)
            .environmentObject(state)
            .environment(\.colorScheme, dark ? .dark : .light)))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 480, height: 400))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = dark ? "-dark" : ""
            let out = "/tmp/kopie-render-\(item.id)\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-render-\(item.id)\(dark ? "-dark" : "")")
    }

    @MainActor
    private static func renderConfirm(kind: String, dark: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let dialog: ConfirmDialog
        switch kind {
        case "privacy":
            dialog = ConfirmDialog(title: "Clear All History",
                                   message: "This will permanently remove all items. Type DELETE to confirm.",
                                   confirmTitle: "Clear All", destructive: true,
                                   requiresTyping: "DELETE",
                                   onConfirm: {}, onCancel: {})
        case "plain":
            dialog = ConfirmDialog(title: "Clear All History",
                                   message: "This will permanently remove all items.",
                                   confirmTitle: "Clear All",
                                   onConfirm: {}, onCancel: {})
        default:
            dialog = ConfirmDialog(title: "Delete Items",
                                   message: "Selected items will be permanently removed.",
                                   confirmTitle: "Delete", destructive: true,
                                   onConfirm: {}, onCancel: {})
        }
        // The offscreen harness window doesn't reliably propagate the
        // darkAqua appearance into SwiftUI's colorScheme environment — force
        // it so captures match the appearance under test.
        let styled = AnyView(dialog.environment(\.colorScheme, dark ? .dark : .light))
        let win = NSWindow(contentViewController: NSHostingController(rootView: styled))
        win.setContentSize(NSSize(width: 340, height: 280))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        let host = win.contentViewController as! NSHostingController<AnyView>
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = kind == "danger" ? "" : "-\(kind)"
            let out = "/tmp/kopie-confirm\(suffix)\(dark ? "-dark" : "").png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-confirm\(kind == "danger" ? "" : "-\(kind)")\(dark ? "-dark" : "")")
    }

    @MainActor
    private static func renderLoading(dark: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let content = ZStack {
            EmberCanvas(scheme: dark ? .dark : .light)
            LoadingRowsCard().padding(24)
        }
        .frame(width: 320, height: 240)
        let win = NSWindow(contentViewController: NSHostingController(rootView: AnyView(content)))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        let host = win.contentViewController as! NSHostingController<AnyView>
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let out = "/tmp/kopie-loading\(dark ? "-dark" : "").png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-loading\(dark ? "-dark" : "")")
    }

    /// Paste-plan smoke (S-001/S-002/S-003): three decision paths of the
    /// `KopieCore.PastePlan` machine plus the app-target Secure Input probe.
    /// `CGEventSource.secureInputEnabled` is not exported by this SDK's
    /// CoreGraphics stub, so instead of comparing the probe against that symbol
    /// the check asserts the true content: `PasteDirectService.isSecureInputActive`
    /// is a plain Bool and `PasteObstacle.detect`'s final-signal ordering maps it
    /// to `.secureInput` exactly when it is true.
    @MainActor
    private static func checkPastePlan() {
        let ok1 = PastePlan.decide(PasteInput(axGranted: true, secureInputActive: true, attemptsMade: 0)) == .fallback(.secureInput)
        let ok2 = PastePlan.decide(PasteInput(axGranted: true, secureInputActive: false, attemptsMade: 2)) == .fallback(.targetRefused)
        let probe = PasteDirectService.isSecureInputActive
        let probeExpected: PasteObstacle? = probe ? .secureInput : nil
        let ok3 = PasteObstacle.detect(axGranted: true, secureInputActive: probe, targetStillFront: true) == probeExpected
        let ok = ok1 && ok2 && ok3
        print(ok ? "PASS PastePlan decisions (S-001/S-002/S-003)"
                 : "FAIL PastePlan decisions (S-001/S-002/S-003) s1=\(ok1) s2=\(ok2) probe=\(ok3)")
    }

    /// Renders one Settings tab for visual verification.
    @MainActor
    private static func renderSettings(tab: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let view: AnyView
        switch tab {
        case "general": view = AnyView(SettingsView(initialSelection: .general))
        case "clipboard": view = AnyView(SettingsView(initialSelection: .clipboard))
        case "cleanup": view = AnyView(SettingsView(initialSelection: .cleanup))
        case "storage": view = AnyView(SettingsView(initialSelection: .storage))
        case "security": view = AnyView(SettingsView(initialSelection: .security))
        default: view = AnyView(SettingsView(initialSelection: .privacy))
        }
        let host = NSHostingController(rootView: AnyView(view
            .environmentObject(state)))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 660, height: 520))
        win.styleMask = [.titled]
        win.title = "\(tab.capitalized) Settings"
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let out = "/tmp/kopie-settings-\(tab).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-settings-\(tab)")
    }

    /// Renders the main window (sidebar, history list, detail panel).
    @MainActor
    private static func renderMain(dark: Bool, size: NSSize? = nil) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        // Force the color environment (like renderConfirm): the harness NSWindow's
        // system appearance must not override the requested scheme.
        let styled = AnyView(MainView()
            .environmentObject(state)
            .environment(\.colorScheme, dark ? .dark : .light))
        let host = NSHostingController(rootView: styled)
        let win = NSWindow(contentViewController: host)
        win.setContentSize(size ?? NSSize(width: 900, height: 560))
        win.styleMask = [.titled]
        win.title = "Kopie"
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = dark ? "-dark" : ""
            let out = "/tmp/kopie-render-main\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-render-main\(dark ? "-dark" : "")")
    }

    /// Renders the onboarding (step 0-4) or return-launch splash offscreen.
    @MainActor
    private static func renderOnboarding(arg: String, dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let view: OnboardingView
        if arg == "splash" {
            state.showOnboarding = true
            state.isReturnLaunch = true
            view = OnboardingView()
        } else {
            state.showOnboarding = true
            state.isReturnLaunch = false
            view = OnboardingView(initialStep: Int(arg) ?? 0)
        }
        let host = NSHostingController(rootView: AnyView(view
            .environmentObject(state)
            .environment(\.colorScheme, dark ? .dark : .light)))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 520, height: 420))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = dark ? "-dark" : ""
            let out = "/tmp/kopie-onboarding-\(arg)\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-onboarding-\(arg)\(dark ? "-dark" : "")")
    }

    /// Captures the window's actual composited pixels. `cacheDisplay` misses
    /// NSViewRepresentable content (NSTextView embeds render only into the
    /// window's layer, not through recursive drawRect), so this is what makes
    /// rich-text views visible in smoke snapshots. Own-window capture needs no
    /// screen-recording permission.
    @MainActor
    private static func writeWindowCapture(_ win: NSWindow, name: String) {
        let id = CGWindowID(UInt32(max(win.windowNumber, 0)))
        guard id != kCGNullWindowID else { return }
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, .bestResolution) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) {
                let out = "/tmp/\(name)-win.png"
                try? png.write(to: URL(fileURLWithPath: out))
                print("WROTE \(out) \(png.count)B")
            }
        }
    }

    @MainActor
    private static func renderPopover(dark: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let host = NSHostingController(rootView: AnyView(PopoverView()
            .environmentObject(state)
            .environment(\.colorScheme, dark ? .dark : .light)))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 440, height: 420))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = dark ? "-dark" : ""
            let out = "/tmp/kopie-render-popover\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-render-popover\(dark ? "-dark" : "")")
    }

    @MainActor
    private static func renderBubble(item: ClipboardItem, dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = AppState()
        let view = PreviewBubbleView(
            item: item,
            tailSide: .trailing,
            tailOffset: 0,
            onHoverChange: { _ in })
            .environmentObject(state)
        let host = NSHostingController(rootView: AnyView(view
            .environment(\.colorScheme, dark ? .dark : .light)))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 400, height: 400))
        win.styleMask = [.titled]
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        // Rich items parse off the main thread now — give the background
        // parse a beat to land so the capture shows the formatted text.
        if item.isRichText {
            let deadline = Date().addingTimeInterval(8)
            while state.cachedRich(for: item) == nil, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
        }
        host.view.layoutSubtreeIfNeeded()
        guard let rep = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else { print("ERR bitmap"); return }
        host.view.cacheDisplay(in: host.view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            let suffix = dark ? "-dark" : ""
            let out = "/tmp/kopie-render-bubble\(suffix).png"
            try? png.write(to: URL(fileURLWithPath: out))
            print("WROTE \(out) \(png.count)B")
        }
        Self.writeWindowCapture(win, name: "kopie-render-bubble\(dark ? "-dark" : "")")
    }

    /// S-010 [self]: 50 copies ≤500 ms apart with cadence 150 ms must all land
    /// in order (deltas of 1 are expected; >1 would surface the badge).
    ///
    /// Each write is `clearContents()` + `setString(...)`: `setString` alone
    /// does NOT replace the pasteboard's contents (the old string survives and
    /// `changeCount` stays put), so a type-only write would look like "no
    /// change" to the monitor and land nothing. Clear-then-set is also what a
    /// real copy operation does, and it advances `changeCount` by exactly 1.
    @MainActor
    private static func smokeRapidCapture() {
        let state = AppState()
        // AppState.init() already starts monitoring when not paused (the
        // default), so the monitor's 150 ms timer is live before the first
        // write — starting it after the writes would silently capture nothing.
        let board = NSPasteboard.general
        var targets: [String] = []
        for i in 0..<50 {
            targets.append("rapid-capture-\(i)")
            board.clearContents()
            board.setString(targets[i], forType: .string)
            // Pump the run loop so the monitor's 150 ms timer ticks 2-3× per write.
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.35))
        }
        // Let the last capture drain.
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(1.0))
        // Monitor already running from AppState.init — no startMonitoring() needed.
        var f = QueryFilter()
        f.limit = 100
        let got = Array(state.store.query(f).prefix(50).reversed().compactMap(\.text))
        // Diags go LAST so they are guaranteed flushed before the PASS/FAIL result.
        print("diag first=\(Array(state.items.prefix(12)).map(\.text)) count=\(got.count)")
        print(got == targets
              ? "PASS Rapid capture (S-010) \(got.count)/50"
              : "FAIL Rapid capture (S-010) landed=\(got)")
    }

    /// S-011 [self]: full capture⇨paste-back⇄capture leaves history count
    /// unchanged for the same content (one row for the marker through all three phases).
    @MainActor
    private static func smokeOwnWriteCycle() {
        let A = "own-write-cycle-\(UUID().uuidString)"
        let state = AppState()
        // Phase 1: one capture of the marker → exactly one row.
        let board = NSPasteboard.general
        board.clearContents(); board.setString(A, forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let afterFirst = state.items.filter { $0.text == A }.count
        // Phase 2: paste-back via the app's public copyBack (which routes through
        // the wired RestoreService → onDidWrite → monitor.noteSelfWrite).
        // A fresh RestoreService() would not be wired to anything and would
        // silently re-capture its own staging.
        if let item = state.items.first(where: { $0.text == A }) {
            state.copyBack(item)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let afterRestore = state.items.filter { $0.text == A }.count
        // Phase 3: same content written again → copyTextToClipboard calls noteSelfWrite.
        state.copyTextToClipboard(A)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let afterReCapture = state.items.filter { $0.text == A }.count
        let ok = afterFirst == 1 && afterRestore == 1 && afterReCapture == 1
        print("afterFirst=\(afterFirst) afterRestore=\(afterRestore) afterReCapture=\(afterReCapture)")
        print(ok ? "PASS Own-write filter (S-011)" : "FAIL Own-write filter (S-011)")
    }
}
