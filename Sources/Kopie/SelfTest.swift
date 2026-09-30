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
        let host = NSHostingController(rootView: DetailsPanel(item: item).environmentObject(state))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 480, height: 400))
        win.styleMask = [.titled]
        if dark { win.appearance = NSAppearance(named: .darkAqua) }
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
        let host = NSHostingController(rootView: PopoverView().environmentObject(state))
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 440, height: 420))
        win.styleMask = [.titled]
        if dark { win.appearance = NSAppearance(named: .darkAqua) }
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
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.setContentSize(NSSize(width: 400, height: 400))
        win.styleMask = [.titled]
        if dark { win.appearance = NSAppearance(named: .darkAqua) }
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
}
