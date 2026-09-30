import SwiftUI
import AppKit
import KopieCore

// MARK: - Controller

/// The floating chat-bubble preview. Hangs beside the popover list — on the
/// left by default, flipped to the right when the screen edge blocks it —
/// so it never overlaps or displaces the list. Owns ALL preview state: the
/// show/hide lifecycle, the hover grace timer, geometry, and the popover
/// behavior flip that keeps the popover alive while the bubble is
/// interactive (a transient popover would close on the first click inside
/// the bubble).
@MainActor
final class PreviewPanelController {
    weak var popover: NSPopover?

    private let state: AppState

    // Content layout constants (points). These define the panel's inner
    // geometry: [marginX][bubble][tail][marginR] horizontally,
    // [marginY] vertically.
    static let gap: CGFloat = 6          // bubble edge → popover window edge
    static let marginX: CGFloat = 8      // leading content margin
    static let marginR: CGFloat = 4      // trailing margin after the tail
    static let marginY: CGFloat = 2      // top/bottom content margin
    static let tailLength: CGFloat = 7   // tail protrusion
    static let tailHeight: CGFloat = 16

    private var panel: NSPanel?
    private var visibleItem: ClipboardItem?
    private var rowY: CGFloat?           // row center, popover-root top-down
    private var tailSide: Edge = .trailing
    private var clearWork: DispatchWorkItem?
    private var fadeWork: DispatchWorkItem?
    private var hoveringBubble = false

    init(state: AppState) {
        self.state = state
    }

    // MARK: Intent entry points (from PopoverView)

    /// Show the bubble for `item`, anchored to the row at `rowY`. Also the
    /// switch path when the target item changes.
    func preview(_ item: ClipboardItem, rowY: CGFloat?) {
        clearWork?.cancel(); clearWork = nil
        let switched = visibleItem?.id != item.id
        visibleItem = item
        if let rowY { self.rowY = rowY }
        guard let win = popoverWindow else { return }
        // Critical: with the popover transient, any click (or wheel-down)
        // outside it — including inside this bubble — closes the popover.
        popover?.behavior = .applicationDefined
        layoutAndShow(win: win, animated: switched || panel?.isVisible != true)
    }

    /// Re-anchor an already-visible bubble (the list scrolled under it, or
    /// the keyboard highlight moved). Never resurrects a hidden bubble.
    func move(_ item: ClipboardItem, rowY: CGFloat?) {
        guard visibleItem?.id == item.id, let rowY else { return }
        self.rowY = rowY
        guard let win = popoverWindow, panel?.isVisible == true else { return }
        layoutAndShow(win: win, animated: true)
    }

    /// Hide after `seconds`, unless the cursor has reached the bubble.
    func scheduleClear(after seconds: Double) {
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.hoveringBubble else { return }
                self.hide()
            }
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Popover closed (ESC, outside click, app-side close): drop the bubble
    /// and restore transient behavior for the next open.
    func popoverDidClose() {
        clearWork?.cancel(); clearWork = nil
        hoveringBubble = false
        hide()
    }

    func hide() {
        visibleItem = nil
        rowY = nil
        popover?.behavior = .transient
        guard let p = panel, p.isVisible else { return }
        fadeWork?.cancel()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduce else { p.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak p] in
            MainActor.assumeIsolated {
                p?.orderOut(nil)
                p?.alphaValue = 1
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
    }

    // MARK: Geometry & display

    private var popoverWindow: NSWindow? {
        popover?.contentViewController?.view.window
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        // Window shadow is derived from the content's alpha shape — it wraps
        // the bubble + tail and is never clipped (it draws outside the frame).
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return p
    }

    private func makeBubble(item: ClipboardItem, side: Edge, tailOffset: CGFloat) -> some View {
        PreviewBubbleView(
            item: item,
            tailSide: side,
            tailOffset: tailOffset,
            onHoverChange: { [weak self] hovering in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hoveringBubble = hovering
                    if hovering {
                        self.clearWork?.cancel(); self.clearWork = nil
                    } else {
                        self.scheduleClear(after: 0.25)
                    }
                }
            })
            .environmentObject(state)
    }

    private func layoutAndShow(win: NSWindow, animated: Bool) {
        guard let item = visibleItem, let rowY else { return }
        let p: NSPanel
        if let existing = panel {
            p = existing
        } else {
            p = makePanel()
            panel = p
        }
        // The bubble must never tuck under the popover: match its level.
        p.level = win.level

        let host: NSHostingController<AnyView>
        if let existing = p.contentViewController as? NSHostingController<AnyView> {
            host = existing
            host.rootView = AnyView(makeBubble(item: item, side: tailSide, tailOffset: 0))
        } else {
            host = NSHostingController(
                rootView: AnyView(makeBubble(item: item, side: tailSide, tailOffset: 0)))
            p.contentViewController = host
        }
        position(host: host, panel: p, item: item, win: win, rowY: rowY, animated: animated)
    }

    private func position(host: NSHostingController<AnyView>, panel p: NSPanel,
                          item: ClipboardItem, win: NSWindow, rowY: CGFloat, animated: Bool) {
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        guard size.width > 1, size.height > 1 else { return }

        let visible = (win.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // Default: hang to the LEFT of the list, bubble flush toward the
        // popover edge: [marginX][bubble][tail][marginR]. Flip to the right
        // only when the screen's left edge would clip it.
        let bubbleW = size.width - Self.marginX - Self.tailLength - Self.marginR
        var originX = win.frame.minX - Self.gap - Self.marginX - bubbleW
        var side: Edge = .trailing
        if originX < visible.minX + 4 {
            side = .leading
            originX = win.frame.maxX + Self.gap
        }
        if side != tailSide {
            tailSide = side
            // Tail side only reorders the HStack — the measured size is
            // identical, so keep it and swap the content in place.
            host.rootView = AnyView(makeBubble(item: item, side: side, tailOffset: 0))
            host.view.layoutSubtreeIfNeeded()
        }

        // Row center in AppKit window coordinates (root space is top-down and
        // fills the window, so: y_from_top → window.maxY − y_from_top).
        let rowCenter = win.frame.maxY - rowY
        var originY = rowCenter - size.height / 2
        // Clamp inside the popover window, then inside the screen.
        originY = min(max(originY, win.frame.minY + 4), win.frame.maxY - size.height - 4)
        originY = min(max(originY, visible.minY), visible.maxY - size.height)

        // The tail tracks the row: 0 when unclamped, then leans to stay on
        // the bubble. Measured from the bubble's vertical center.
        var tailOffset = (originY + size.height / 2) - rowCenter
        let tailRoom = size.height / 2 - Self.tailHeight / 2 - 4
        tailOffset = min(max(tailOffset, -tailRoom), tailRoom)

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        host.rootView = AnyView(makeBubble(item: item, side: side, tailOffset: tailOffset))

        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !p.isVisible {
            p.setFrame(frame, display: false)
            fadeWork?.cancel()
            p.alphaValue = reduce ? 1 : 0
            p.orderFront(nil)
            if !reduce {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    p.animator().alphaValue = 1
                }
            }
        } else if animated, !reduce {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrame(frame, display: true)
            }
        } else {
            p.setFrame(frame, display: true)
        }
    }
}

// MARK: - Bubble view

/// Content-hugging chat bubble: a one-liner produces a compact pill, longer
/// text wraps at the width cap and scrolls past the height cap, and images
/// render at their natural size (capped, never upscaled). The tail points at
/// the hovered row.
struct PreviewBubbleView: View {
    @EnvironmentObject var state: AppState

    let item: ClipboardItem
    /// Edge of the bubble the tail sits on: `.trailing` when the bubble hangs
    /// left of the list (tail points right at it), `.leading` when flipped.
    let tailSide: Edge
    /// Tail displacement from the bubble's vertical center (top-down).
    let tailOffset: CGFloat
    let onHoverChange: (Bool) -> Void

    static let maxWidth: CGFloat = 330
    static let maxHeight: CGFloat = 300

    var body: some View {
        HStack(spacing: 0) {
            if tailSide == .leading { tail.padding(.trailing, -1) }
            bubble
                .padding(.leading, tailSide == .trailing ? PreviewPanelController.marginX : 0)
                .padding(.trailing, tailSide == .leading ? PreviewPanelController.marginR : 0)
            if tailSide == .trailing {
                tail
                    .padding(.leading, -1)
                    .padding(.trailing, PreviewPanelController.marginR)
            }
        }
    }

    private var tail: some View {
        PreviewBubbleTail(pointingRight: tailSide == .trailing)
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: PreviewPanelController.tailLength, height: PreviewPanelController.tailHeight)
            .offset(y: tailOffset)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.typeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            itemBody(for: item)
            footer
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .onHover { onHoverChange($0) }
        .padding(.vertical, PreviewPanelController.marginY)
        .id(item.id)
        .transition(.opacity)
    }

    @ViewBuilder private func itemBody(for item: ClipboardItem) -> some View {
        if item.kind == .image {
            imageBody(for: item)
        } else if item.isRichText {
            richContent(for: item)
        } else {
            plainBody(item.text ?? item.preview)
        }
    }

    /// Cached rich-text body. Never parses here: resolve() can block on
    /// WebKit and hang the app. Starts the one background parse instead and
    /// renders plain text until it lands (the cache is @Published, so the
    /// bubble re-renders with rich formatting when ready).
    private func richContent(for item: ClipboardItem) -> some View {
        if state.cachedRich(for: item) == nil, let data = state.richText(for: item) {
            state.loadRich(item, data: data,
                           isHTML: item.richTextRelPath?.hasSuffix(".html") ?? false)
        }
        let plain = item.text ?? item.preview
        return richBody(state.cachedRich(for: item)?.text ?? NSAttributedString(string: plain))
    }

    @ViewBuilder private func plainBody(_ text: String) -> some View {
        let natural = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular)),
        ])
        if natural.width <= Self.maxWidth, natural.height <= Self.maxHeight {
            Text(text)
                .font(.body)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: natural.width, alignment: .leading)
        } else if natural.height <= Self.maxHeight {
            Text(text)
                .font(.body)
                .frame(width: Self.maxWidth, alignment: .leading)
        } else {
            ScrollView {
                Text(text)
                    .font(.body)
                    .frame(width: Self.maxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.maxWidth, height: Self.maxHeight)
        }
    }

    @ViewBuilder private func richBody(_ attributed: NSAttributedString) -> some View {
        let full = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        if full.width <= Self.maxWidth, full.height <= Self.maxHeight {
            RichTextRepresentation(attributed: attributed)
                .fixedSize(horizontal: true, vertical: true)
        } else if full.height <= Self.maxHeight {
            RichTextRepresentation(attributed: attributed)
                .frame(width: Self.maxWidth, alignment: .leading)
        } else {
            ScrollView {
                RichTextRepresentation(attributed: attributed)
                    .frame(width: Self.maxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.maxWidth, height: Self.maxHeight)
        }
    }

    private func imageBody(for item: ClipboardItem) -> some View {
        Group {
            if let img = state.fullImage(for: item) ?? state.thumbnail(for: item) {
                let size = naturalSize(of: img)
                let scale = min(1, Self.maxWidth / size.width, Self.maxHeight / size.height)
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width * scale, height: size.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.maxWidth, height: 80)
            }
        }
    }

    private func naturalSize(of img: NSImage) -> NSSize {
        var size = img.size
        if size.width < 1, size.height < 1, let rep = img.representations.first {
            size = NSSize(width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh))
        }
        if size.width < 1, size.height < 1 { size = NSSize(width: 1, height: 1) }
        return size
    }

    @ViewBuilder private var footer: some View {
        if item.kind == .image {
            Text("\(item.width ?? 0) × \(item.height ?? 0)")
                .font(.caption2).foregroundStyle(.secondary)
        } else if item.isRichText {
            Text("Rich Text")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tail

/// The chat-bubble tail: a small triangle pointing at the list.
struct PreviewBubbleTail: Shape {
    /// True when the tail points right (bubble hangs left of the list).
    var pointingRight: Bool

    func path(in r: CGRect) -> Path {
        var p = Path()
        if pointingRight {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}
