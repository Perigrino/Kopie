import SwiftUI
import KopieCore
import AppKit
import UniformTypeIdentifiers

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool
    @State private var selectionMode = false
    @State private var selectedIDs = Set<Int64>()
    @State private var showClearConfirm = false
    @State private var showToast = false
    /// Copy of the confirmation capsule, so it can say *why* a paste was
    /// skipped instead of only confirming the clipboard write.
    @State private var toastText = "Copied"
    @State private var toastWarning = false
    @State private var toastActionTitle: String?
    @State private var toastAction: (() -> Void)?
    @State private var toastTask: Task<Void, Never>?
    /// Flat index into `state.items` for keyboard navigation (nil = nothing highlighted).
    @State private var highlightedIndex: Int?
    /// True while Control is held: the next copy stages plain text only,
    /// stripping rich text (paste-as-plain-text one-shot override).
    @State private var controlHeld = false
    @State private var flagsMonitor: GatedEventMonitor?
    /// Item whose preview bubble we last requested — lets row-frame updates
    /// re-anchor the (externally owned) bubble while the list scrolls.
    @State private var activePreviewID: Int64?
    /// Row frames in the popover root's coordinate space (top-down, live
    /// layout position — scroll offsets are already baked in). Rows report
    /// these through `RowFramePreference`.
    @State private var rowFrames: [Int64: CGRect] = [:]
    /// Set just before the keyboard path moves the highlight, so the
    /// `onChange(of: highlightedIndex)` scroll only fires for arrow keys.
    /// Hover also moves the highlight (the spec's "what Enter will paste is
    /// unmistakable"), but scrolling the list to center a merely-hovered row
    /// yanks the whole list around — hover must not scroll.
    @State private var scrollPending = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            content
            Divider()
            bottomBar
        }
        .frame(width: 440)
        // `.win.dark.canvas` — the popover sits on the Ember canvas (the two
        // fixed radial glows) exactly like the mock, not on a flat fill.
        .background(Theme.canvas(for: scheme))
        .coordinateSpace(name: Self.rootSpace)
        .onChange(of: state.searchText) { _ in
            state.refresh()
            highlightedIndex = state.items.isEmpty ? nil : 0
        }
        .onAppear {
            // No refresh() here: AppDelegate refreshes before it shows the
            // popover, and every capture refreshes via .kopieStoreChanged.
            // Refreshing again on appear doubled the queries on every open
            // and is what made the list visibly lag behind the popup.
            DispatchQueue.main.async { searchFocused = true }
            highlightedIndex = state.items.isEmpty ? nil : 0
            // Re-install safely: SwiftUI can call onAppear again while
            // monitors are live (sheet presentation, host-window reuse). The
            // old install path stacked a second monitor pair on top of the
            // first — a leaked pair that outlived the view and kept acting on
            // the popover's list from anywhere in the app.
            if keyMonitor == nil { installKeyMonitor() }
            if flagsMonitor == nil { installFlagsMonitor() }
        }
        .onDisappear {
            // Always unwind both monitors together — onDisappear does not
            // fire on app termination (and NSPopover's transient teardown can
            // skip it entirely). A leaked monitor was the other half of the
            // "main view dead, menu-bar list moves instead" bug.
            removeKeyMonitor(); removeFlagsMonitor()
            activePreviewID = nil
            GlobalActions.clearPreview?(0)
        }
        .overlay(alignment: .bottom) {
            if showToast {
                CopiedToast(text: toastText, warning: toastWarning,
                            actionTitle: toastActionTitle, action: toastAction)
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showClearConfirm) {
            ConfirmDialog(
                title: "Clear clipboard history?",
                message: "This will permanently remove all saved clipboard items. This action cannot be undone.",
                confirmTitle: "Clear All", destructive: true,
                onConfirm: { state.removeAll(); showClearConfirm = false },
                onCancel: { showClearConfirm = false })
        }
    }

    private var header: some View {
        // `.popover-head` — flex gap 9, padding 16 per the spec mock.
        HStack(spacing: 9) {
            Image(nsImage: AppIcon.image(pointSize: 18))
            Text("Kopie")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary(for: scheme))
            Spacer()
            EmberIconButton(systemName: state.isPaused ? "play.circle" : "pause.circle",
                            scheme: scheme) {
                withAnimation { state.isPaused ? state.startMonitoring() : state.pauseMonitoring() }
            }
            .help(state.isPaused ? "Resume monitoring" : "Pause monitoring")
        }.padding(DS.pad)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.textTertiary(for: scheme))

            TextField("Search clipboard…", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { state.refresh() }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary(for: scheme))

            if !state.searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.searchText = ""
                        state.refresh()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Theme.textTertiary(for: scheme))
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        // Fixed-height field: SwiftUI vertically centers the plain TextField
        // inside it, which is what keeps the placeholder on the same baseline
        // as the magnifier icon (padding-based sizing let them drift apart).
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.fieldBackground(for: scheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            // `.field:focus` — 1px accent ring; at rest the dark field has no
            // edge and the light one keeps the inset hairline.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focusRingColor, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
        .animation(.easeInOut(duration: 0.15), value: state.searchText.isEmpty)
        .padding(.horizontal, DS.pad)
        .padding(.top, 12)        .padding(.bottom, 10)
    }

    /// `.field:focus` ring — the accent itself; transparent at rest in dark mode.
    private var focusRingColor: Color {
        if searchFocused { return Theme.accent }
        return scheme == .light ? Theme.hairline(for: scheme) : .clear
    }

    @ViewBuilder private var content: some View {
        if state.items.isEmpty {
            EmptyStateView(
                symbol: "doc.on.clipboard",
                title: state.isPaused ? "Monitoring paused" : (state.searchText.isEmpty ? "Nothing copied yet" : "Nothing found"),
                message: state.isPaused ? "Resume monitoring to start saving copied items again."
                        : (state.searchText.isEmpty ? "Copy some text or an image and it will appear here."
                           : "Try searching for something else."))
                .frame(height: 200)
            if state.isPaused {
                Button("Resume Monitoring") { state.startMonitoring() }.padding(.bottom, 12)
            }
        } else {
            // Flat index per item, built once per render. `firstIndex` inside
            // the ForEach was O(n²) on every paint (including the hover-driven
            // ones). Uniquing rather than trapping so a bad row can never take
            // the popover down with it.
            let indexByID = Dictionary(state.items.enumerated().map { ($1.id, $0) },
                                       uniquingKeysWith: { first, _ in first })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let groups = groupByDay(state.items)
                        let firstGroupID = groups.first?.id
                        ForEach(groups) { group in
                            // `.group-label` — 11/600 uppercase, wide tracking,
                            // tertiary; popover inline overrides: 2px in, first
                            // label 6px up, later ones 18px (the css default),
                            // 8px down.
                            Text(group.label.uppercased())
                                .font(.system(size: Theme.tMeta, weight: .semibold))
                                .tracking(0.9)
                                .foregroundStyle(Theme.textTertiary(for: scheme))
                                .padding(.leading, 2)
                                .padding(.top, group.id == firstGroupID ? 6 : 18)
                                .padding(.bottom, 8)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { _, item in
                                // Flat index per item, built once per render.
                                // Calling firstIndex inside the ForEach was O(n²)
                                // on every paint (including the hover-driven ones).
                                let idx = indexByID[item.id] ?? 0
                                // `.row-interstitial` grid gap — 6px between
                                // cards; nothing after the very last row, where
                                // the list wrapper's 8px pad closes the column.
                                popoverRow(item, idx)
                                    .padding(.bottom,
                                             item.id == state.items.last?.id ? 0 : 6)
                            }
                        }
                    }.padding(.horizontal, DS.pad).padding(.vertical, Self.listVerticalPadding)
                }
                .frame(height: Self.listViewportHeight)
                // Keep the externally owned bubble anchored while the list
                // scrolls: forward the live row frame for the active preview.
                .onPreferenceChange(RowFramePreference.self) { frames in
                    let live = frames.filter { $0.value.width > 0 }
                    guard live != rowFrames else { return }
                    rowFrames = live
                    forwardPreviewAnchor()
                }
                .onChange(of: highlightedIndex) { _ in
                    // Arrow-key moves scroll; hover moves don't (scrollPending
                    // is only set by `moveHighlight`).
                    guard scrollPending, let i = highlightedIndex,
                          state.items.indices.contains(i) else { return }
                    scrollPending = false
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(state.items[i].id, anchor: .center)
                    }
                }
            }
        }
    }

    /// One compact popover row, built in a function so the massive memberwise
    /// initializer doesn't blow the type-checker's budget per ForEach element.
    private func popoverRow(_ item: ClipboardItem, _ idx: Int) -> some View {
        HistoryRow(
            item: item,
            thumbnail: state.thumbnail(for: item),
            selectionMode: selectionMode,
            isSelected: selectedIDs.contains(item.id),
            isHighlighted: highlightedIndex == idx,
            onCopy: { copy(item) },
            onPaste: state.pasteOnClickEnabled ? { copyAndPaste(item) } : nil,
            onRemove: { state.remove(item) },
            onFavorite: { state.toggleFavorite(item) },
            onPin: { state.togglePin(item) },
            onCopyPlainText: item.isRichText ? { copyPlainText(item) } : nil,
            onToggleQueue: { state.toggleQueued(item) },
            isQueued: state.isQueuedForPaste(item),
            onToggleSelect: { toggleSelect(item.id) },
            onToggleExpire: { state.toggleExpireAfterUse(item) },
            expiresAfterUse: state.isExpiredAfterUse(item),
            onHoverChange: { hovering in rowHover(item, idx, hovering) },
            compact: true
        )
        .id(item.id)
        .modifier(RowGeometry(itemID: item.id))
        .simultaneousGesture(
            TapGesture().modifiers(.option).onEnded { _ in copyAndPaste(item) })
    }

    /// Show (or switch) the preview bubble for a row — hover or keyboard.
    /// No preview fires on the programmatic highlight made when the popover
    /// opens: only real interaction enters here. Honors the
    /// Settings → General "Show hover preview" toggle; when off, any
    /// visible bubble is dismissed instead.
    private func showPreview(_ item: ClipboardItem) {
        guard SettingsStore.shared.showMenuBarPreview else {
            activePreviewID = nil
            GlobalActions.clearPreview?(0)
            return
        }
        activePreviewID = item.id
        GlobalActions.showPreview?(item, rowFrames[item.id]?.midY)
    }

    /// Row-frame changes re-anchor the visible bubble (list scrolled under it).
    private func forwardPreviewAnchor() {
        guard let id = activePreviewID,
              let item = state.items.first(where: { $0.id == id }) else { return }
        GlobalActions.movePreview?(item, rowFrames[id]?.midY)
    }

    private func rowHover(_ item: ClipboardItem, _ idx: Int, _ hovering: Bool) {
        if hovering {
            // Hover moves the keyboard highlight too — the selection ring and
            // gradient tile follow the pointer, so Enter acts on what's under
            // it (the spec's "what Enter will paste is unmistakable" row).
            if highlightedIndex != idx {
                highlightedIndex = idx
            }
            showPreview(item)
        } else if activePreviewID == item.id {
            GlobalActions.clearPreview?(0.5)
        }
    }

    private static let listViewportHeight: CGFloat = 360
    private static let listVerticalPadding: CGFloat = 8
    private static let rootSpace = "popoverRoot"

    private struct RowFramePreference: PreferenceKey {
        static let defaultValue: [Int64: CGRect] = [:]
        static func reduce(value: inout [Int64: CGRect], nextValue: () -> [Int64: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }

    /// Reports a row's frame in the popover root's coordinate space (top-down
    /// from the window's top edge; scroll offsets are already applied).
    private struct RowGeometry: ViewModifier {
        let itemID: Int64
        func body(content: Content) -> some View {
            content.background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RowFramePreference.self,
                        value: [itemID: proxy.frame(in: .named("popoverRoot"))])
                }
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            if selectionMode {
                Button("Cancel") {
                    selectionMode = false; selectedIDs = []
                }
                Button("Select All") {
                    selectedIDs = Set(state.items.map { $0.id })
                }
                .disabled(selectedIDs.count == state.items.count)
                Spacer()
                Button("Delete \(selectedIDs.count)") { deleteSelected() }
                    .foregroundStyle(selectedIDs.isEmpty ? Color.secondary : Color.red)
                    .disabled(selectedIDs.isEmpty)
            } else {
                Button("Open Kopie") { openMain() }
                Button("Settings…") { openSettings() }
                Spacer()
                Button("Select") { withAnimation { selectionMode = true } }
                    .disabled(state.items.isEmpty)
                Button("Clear") { showClearConfirm = true }
                    .disabled(state.items.isEmpty)
            }
        }
        // `.popover-foot` — ghost buttons: transparent, 6×4 padding, 11/600,
        // tertiary; the bar itself is hairline-topped with 10/16/12 padding.
        .buttonStyle(.plain)
        .font(.system(size: Theme.tMeta, weight: .semibold))
        .foregroundStyle(Theme.textTertiary(for: scheme))
        .padding(.vertical, 6).padding(.horizontal, 4)
        .padding(.top, 4).padding(.horizontal, DS.pad).padding(.bottom, 8)
    }

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item, plainTextOnly: controlHeld)
        presentToast()
    }

    /// Context-menu action: stages the item without its rich-text flavors.
    private func copyPlainText(_ item: ClipboardItem) {
        state.copyBack(item, plainTextOnly: true)
        presentToast()
    }

    /// Shows the confirmation capsule. Warnings get longer on screen — the
    /// user has to have time to read why their click didn't paste, and to act
    /// on the `action` that takes them to the pane that fixes it.
    private func presentToast(_ text: String = "Copied", warning: Bool = false,
                              seconds: Double = 1,
                              actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastText = text
        toastWarning = warning
        toastActionTitle = actionTitle
        toastAction = action
        showToast = true
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation { showToast = false }
            }
        }
    }

    /// A click on a row: stage the item on the clipboard, then — when
    /// Settings → General "Paste directly into apps" is on — close the popover
    /// and paste it at the caret in the app underneath. With that setting off
    /// this is a plain copy and the popover stays open.
    ///
    /// When Accessibility hasn't been granted the paste can't happen, so the
    /// popover stays up and the toast says so. Closing would leave the click
    /// looking like it did nothing at all. The system's own permission dialog
    /// is raised at most once per launch — re-asking on every click is what
    /// turned each paste attempt into a modal prompt.
    private func copyAndPaste(_ item: ClipboardItem) {
        copy(item)
        guard SettingsStore.shared.pasteDirect else { return }
        guard PasteDirectService.isPermissionGranted else {
            GlobalActions.requestPastePermission?()
            presentToast("Copied — Accessibility needed to paste", warning: true, seconds: 6,
                         actionTitle: "Open Settings",
                         action: { PasteDirectService.openAccessibilitySettings() })
            return
        }
        closeAndPaste()
    }

    /// Copies the highlighted (or first) item, then simulates ⌘V in the
    /// frontmost app. Closes the popover first so the paste lands in the
    /// app underneath, not in Kopie.
    private func copyAndPasteHighlighted() {
        let item: ClipboardItem?
        if let i = highlightedIndex, state.items.indices.contains(i) {
            item = state.items[i]
        } else {
            item = state.items.first
        }
        guard let item else { return }
        copyAndPaste(item)
    }

    /// ⌥1…⌥9 quick-select: copy the nth item, then direct-paste it.
    private func quickSelect(_ n: Int) {
        guard state.items.indices.contains(n - 1) else { return }
        copyAndPaste(state.items[n - 1])
    }

    /// Closes the popover and asks AppDelegate to paste once the app the
    /// popover interrupted is frontmost again. That hand-back is the whole
    /// point: a blind `asyncAfter` fired ⌘V while Kopie could still have been
    /// the active app, so the keystroke went nowhere and the caret never
    /// received the item. Without the Accessibility permission the paste is
    /// skipped and the user is told instead of being left with silence.
    private func closeAndPaste() {
        GlobalActions.closePopover?()
        GlobalActions.pasteWhenFocusReturns?()
    }

    private func moveHighlight(_ delta: Int) {
        guard !selectionMode else { return }
        let count = state.items.count
        guard count > 0 else { return }
        let next: Int
        if let i = highlightedIndex {
            next = min(max(i + delta, 0), count - 1)
        } else {
            next = delta > 0 ? 0 : count - 1
        }
        // Keyboard-driven moves get the centering scroll; hover-driven ones
        // must not (the flag is consumed by the onChange scroll handler).
        scrollPending = true
        highlightedIndex = next
        showPreview(state.items[next])
    }

    private func toggleSelect(_ id: Int64) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func deleteSelected() {
        let ids = Array(selectedIDs)
        state.remove(ids)
        selectionMode = false
        selectedIDs = []
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        GlobalActions.openMain?()
    }

    private func openSettings() {
        GlobalActions.openSettings?()
    }

    // MARK: - macOS 13 keyboard handling

    @State private var keyMonitor: GatedEventMonitor?

    private func installKeyMonitor() {
        // Local keyDown monitors fire for the whole process — not just the
        // popover. GatedEventMonitor makes the window gate mandatory: only
        // events belonging to the popover's own shown window reach the
        // handler; keys meant for the main window (or settings) pass through
        // untouched, so the popover can never again eat the main view's
        // navigation.
        keyMonitor = GatedEventMonitor(
            for: .keyDown,
            accepts: { GlobalActions.isPopoverKeyEvent($0) },
            handle: { handleKeyDown($0) })
    }

    /// Key mapping for one popover-owned keyDown (the monitor has already
    /// gated it to the popover's window). Returns true to consume.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: moveHighlight(-1); return true   // up arrow
        case 125: moveHighlight(1); return true    // down arrow
        case 36:  copyAndPasteHighlighted(); return true // return
        case 53:  handleEscape(); return true      // escape
        // 51 (delete/backspace) deliberately unhandled: backspace may only
        // edit the search field text — it must never remove a record from
        // the copied items list.
        case 18, 19, 20, 21, 23, 22, 26, 28, 25:   // ⌥1…⌥9 quick-select
            if event.modifierFlags.contains(.option) {
                let digits = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                if let n = digits[Int(event.keyCode)] {
                    quickSelect(n)
                    return true
                }
            }
            return false
        default:  return false
        }
    }

    private func removeKeyMonitor() {
        keyMonitor?.remove()
        keyMonitor = nil
    }

    /// Tracks the Control key so a copy can be forced to plain text
    /// (hold ⌃ while clicking/pressing return — paste-as-plain-text).
    private func installFlagsMonitor() {
        // Same gate as the key monitor: modifier changes in other windows
        // must not mutate the popover's ⌃-state. Never consumes.
        flagsMonitor = GatedEventMonitor(
            for: .flagsChanged,
            accepts: { GlobalActions.isPopoverKeyEvent($0) },
            handle: { syncControlFlag($0); return false })
    }

    private func syncControlFlag(_ event: NSEvent) {
        controlHeld = event.modifierFlags.contains(.control)
    }

    private func removeFlagsMonitor() {
        flagsMonitor?.remove()
        flagsMonitor = nil
    }

    private func handleEscape() {
        if !state.searchText.isEmpty {
            state.searchText = ""
            state.refresh()
        } else {
            GlobalActions.closePopover?()
        }
    }
}
