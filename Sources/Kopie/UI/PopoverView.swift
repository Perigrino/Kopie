import SwiftUI
import KopieCore
import AppKit
import UniformTypeIdentifiers

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    @State private var selectionMode = false
    @State private var selectedIDs = Set<Int64>()
    @State private var showClearConfirm = false
    @State private var showToast = false
    @State private var toastTask: Task<Void, Never>?
    /// Flat index into `state.items` for keyboard navigation (nil = nothing highlighted).
    @State private var highlightedIndex: Int?
    /// True while Control is held: the next copy stages plain text only,
    /// stripping rich text (paste-as-plain-text one-shot override).
    @State private var controlHeld = false
    @State private var flagsMonitor: Any?
    /// Item whose preview bubble we last requested — lets row-frame updates
    /// re-anchor the (externally owned) bubble while the list scrolls.
    @State private var activePreviewID: Int64?
    /// Row frames in the popover root's coordinate space (top-down, live
    /// layout position — scroll offsets are already baked in). Rows report
    /// these through `RowFramePreference`.
    @State private var rowFrames: [Int64: CGRect] = [:]

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
        .coordinateSpace(name: Self.rootSpace)
        .onAppear {
            state.refresh()
            DispatchQueue.main.async { searchFocused = true }
            highlightedIndex = state.items.isEmpty ? nil : 0
        }
        .onChange(of: state.searchText) { _ in
            state.refresh()
            highlightedIndex = state.items.isEmpty ? nil : 0
        }
        .onAppear { installKeyMonitor(); installFlagsMonitor() }
        .onDisappear {
            removeKeyMonitor(); removeFlagsMonitor()
            activePreviewID = nil
            GlobalActions.clearPreview?(0)
        }
        .overlay(alignment: .bottom) {
            if showToast {
                CopiedToast().padding(.bottom, 12)
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
        HStack(spacing: 7) {
            Image(nsImage: AppIcon.image(pointSize: 18))
            Text("Kopie").font(.headline)
            Spacer()
            Button {
                withAnimation { state.isPaused ? state.startMonitoring() : state.pauseMonitoring() }
            } label: {
                Image(systemName: state.isPaused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(state.isPaused ? "Resume monitoring" : "Pause monitoring")
        }.padding(DS.pad)
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(searchFocused ? Color.accentColor : Color.secondary)
                .frame(width: 24)
            
            TextField("Search clipboard…", text: $state.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { state.refresh() }
                .font(.system(size: 13))
            
            if !state.searchText.isEmpty {
                Button { 
                    withAnimation(.easeInOut(duration: 0.15)) {
                        state.searchText = ""
                        state.refresh()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        // Fixed-height field: SwiftUI vertically centers the plain TextField
        // inside it, which is what keeps the placeholder on the same baseline
        // as the magnifier icon (padding-based sizing let them drift apart).
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(searchFocused ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.22),
                                      lineWidth: searchFocused ? 1 : 0.5)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
        .animation(.easeInOut(duration: 0.15), value: state.searchText.isEmpty)
        .padding(.horizontal, DS.pad)
        .padding(.top, 2)
        .padding(.bottom, 10)
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groupByDay(state.items)) { group in
                            Text(group.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 10).padding(.bottom, 4)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { _, item in
                                let idx = state.items.firstIndex { $0.id == item.id } ?? 0
                                HistoryRow(item: item,
                                           thumbnail: state.thumbnail(for: item),
                                           selectionMode: selectionMode,
                                           isSelected: selectedIDs.contains(item.id),
                                           isHighlighted: highlightedIndex == idx,
                                           onCopy: { copy(item) },
                                           onRemove: { state.remove(item) },
                                           onFavorite: { state.toggleFavorite(item) },
                                           onPin: { state.togglePin(item) },
                                           onCopyPlainText: item.isRichText ? { copyPlainText(item) } : nil,
                                           onToggleQueue: { state.toggleQueued(item) },
                                           isQueued: state.isQueuedForPaste(item),
                                           onToggleSelect: { toggleSelect(item.id) },
                                           onHoverChange: { hovering in
                                               rowHover(item, hovering)
                                           })
                                    .id(item.id)
                                    .modifier(RowGeometry(itemID: item.id))
                                    // Drag & drop out of Kopie: text drags its text,
                                    // images drag the bitmap, files their paths.
                                    .onDrag {
                                        if item.kind == .image, let img = state.thumbnail(for: item) {
                                            return NSItemProvider(object: img)
                                        }
                                        return NSItemProvider(object: item.dragPayload as NSString)
                                    }
                                    // ⌥-click: copy back AND paste into the frontmost app.
                                    .onTapGesture { }
                                    .simultaneousGesture(TapGesture().modifiers(.option).onEnded { _ in
                                        copy(item)
                                        if SettingsStore.shared.pasteDirect {
                                            closeAndPaste()
                                        }
                                    })
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
                    guard let i = highlightedIndex, state.items.indices.contains(i) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(state.items[i].id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Show (or switch) the preview bubble for a row — hover or keyboard.
    /// No preview fires on the programmatic highlight made when the popover
    /// opens: only real interaction enters here.
    private func showPreview(_ item: ClipboardItem) {
        activePreviewID = item.id
        GlobalActions.showPreview?(item, rowFrames[item.id]?.midY)
    }

    /// Row-frame changes re-anchor the visible bubble (list scrolled under it).
    private func forwardPreviewAnchor() {
        guard let id = activePreviewID,
              let item = state.items.first(where: { $0.id == id }) else { return }
        GlobalActions.movePreview?(item, rowFrames[id]?.midY)
    }

    private func rowHover(_ item: ClipboardItem, _ hovering: Bool) {
        if hovering {
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
        HStack {
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
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        .padding(10).padding(.horizontal, DS.pad)
    }

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item, plainTextOnly: controlHeld)
        showToast = true
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                withAnimation { showToast = false }
            }
        }
    }

    /// Context-menu action: stages the item without its rich-text flavors.
    private func copyPlainText(_ item: ClipboardItem) {
        state.copyBack(item, plainTextOnly: true)
        showToast = true
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled {
                withAnimation { showToast = false }
            }
        }
    }

    private func copyHighlighted() {
        if let i = highlightedIndex, state.items.indices.contains(i) {
            copy(state.items[i])
        } else if let first = state.items.first {
            copy(first)
        }
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
        copy(item)
        guard SettingsStore.shared.pasteDirect else { return }
        closeAndPaste()
    }

    /// ⌥1…⌥9 quick-select: copy the nth item, then direct-paste it.
    private func quickSelect(_ n: Int) {
        guard state.items.indices.contains(n - 1) else { return }
        copy(state.items[n - 1])
        guard SettingsStore.shared.pasteDirect else { return }
        closeAndPaste()
    }

    /// Closes the popover, waits for the target app to become frontmost,
    /// then simulates ⌘V. Without the Accessibility permission, falls back
    /// to staging on the clipboard and asks the system for permission.
    private func closeAndPaste() {
        GlobalActions.closePopover?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !PasteDirectService.paste() {
                PasteDirectService.requestPermission()
            }
        }
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

    @State private var keyMonitor: Any?

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let option = event.modifierFlags.contains(.option)
            switch event.keyCode {
            case 126: moveHighlight(-1); return nil   // up arrow
            case 125: moveHighlight(1); return nil     // down arrow
            case 36:                                   // return
                if option { MainActor.assumeIsolated { copyAndPasteHighlighted() } }
                else { copyHighlighted() }
                return nil
            case 53:  handleEscape(); return nil       // escape
            case 51:  handleDelete(); return event     // delete (pass through if nothing to delete)
            case 18, 19, 20, 21, 23, 22, 26, 28, 25:   // ⌥1…⌥9 quick-select
                if option {
                    let digits = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
                    if let n = digits[Int(event.keyCode)] {
                        MainActor.assumeIsolated { quickSelect(n) }
                        return nil
                    }
                }
                return event
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Tracks the Control key so a copy can be forced to plain text
    /// (hold ⌃ while clicking/pressing return — paste-as-plain-text).
    private func installFlagsMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            MainActor.assumeIsolated { controlHeld = event.modifierFlags.contains(.control) }
            return event
        }
    }

    private func removeFlagsMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func handleEscape() {
        if !state.searchText.isEmpty {
            state.searchText = ""
            state.refresh()
        } else {
            GlobalActions.closePopover?()
        }
    }

    private func handleDelete() {
        if let idx = highlightedIndex, state.items.indices.contains(idx) {
            state.remove(state.items[idx])
            highlightedIndex = min(idx, state.items.count - 1)
        }
    }
}
