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
    /// Item whose image is being previewed (hover or keyboard highlight).
    @State private var previewID: Int64?
    /// True while Control is held: the next copy stages plain text only,
    /// stripping rich text (paste-as-plain-text one-shot override).
    @State private var controlHeld = false
    @State private var flagsMonitor: Any?

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
        .onDisappear { removeKeyMonitor(); removeFlagsMonitor() }
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
                                               previewID = hovering ? item.id : (previewID == item.id ? nil : previewID)
                                           })
                                    .id(item.id)
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
                                    .help("Click to copy · ⌥-click to copy and paste · ⌥1-9 quick-select · hold ⌃ to paste as plain text")
                            }
                        }
                    }.padding(.horizontal, DS.pad).padding(.vertical, 8)
                }
                .frame(height: 360)
                .overlay(alignment: .top) { hoverPreview }
                .onChange(of: highlightedIndex) { _ in
                    guard let i = highlightedIndex, state.items.indices.contains(i) else { return }
                    let it = state.items[i]
                    previewID = (it.kind == .image || (it.kind == .text && it.isRichText)) ? it.id : nil
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(state.items[i].id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Item under the pointer or keyboard highlight (any kind).
    private var previewCandidate: ClipboardItem? {
        guard let id = previewID else { return nil }
        return state.items.first { $0.id == id }
    }

    private var previewItem: ClipboardItem? {
        guard let item = previewCandidate, item.kind == .image else { return nil }
        return item
    }

    /// Rich-text item under the pointer or keyboard highlight.
    private var previewRichItem: ClipboardItem? {
        guard let item = previewCandidate, item.kind == .text, item.isRichText else { return nil }
        return item
    }

    /// Floating previews for the row under the pointer/keyboard highlight.
    /// Floats over the list (not in flow) so the cursor never leaves the row it
    /// is hovering, avoiding a hover↔layout flicker loop. Non-interactive so
    /// mouse events pass through to the row underneath.
    @ViewBuilder private var hoverPreview: some View {
        imagePreview
        richPreview
    }

    /// Rendered rich-text (RTF/HTML) preview of the highlighted item, styled
    /// like the image preview. Uses the SwiftUI Text renderer so it paints
    /// reliably inside the ScrollView-hosted overlay.
    @ViewBuilder private var richPreview: some View {
        if let item = previewRichItem, let data = state.richText(for: item) {
            let isHTML = item.richTextRelPath?.hasSuffix(".html") ?? false
            let resolved = RichTextRepresentation.resolve(
                data: data, isHTML: isHTML, fallbackText: item.text)
            VStack(alignment: .leading, spacing: 4) {
                ScrollView {
                    RichTextRepresentation(attributed: resolved.text)
                }
                .frame(maxWidth: 408, maxHeight: 150)
                Text(resolved.usedFallback ? "Rich Text (plain fallback)" : "Rich Text")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(width: 428)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .padding(.top, 6)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var imagePreview: some View {
        if let item = previewItem, item.kind == .image, let img = state.thumbnail(for: item) {
            VStack(spacing: 4) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 408, maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("\(item.width ?? 0) × \(item.height ?? 0)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .padding(.top, 6)
            .transition(.opacity)
            .allowsHitTesting(false)
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
