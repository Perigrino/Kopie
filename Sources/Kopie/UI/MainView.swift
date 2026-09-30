import SwiftUI
import KopieCore

/// Sidebar history filters.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, images, files, today, favorites, pinned, sensitive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .files: "Files"
        case .today: "Today"
        case .favorites: "Favorites"
        case .pinned: "Pinned"
        case .sensitive: "Sensitive"
        }
    }
    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .text: "doc.text"
        case .images: "photo"
        case .files: "folder"
        case .today: "clock"
        case .favorites: "star"
        case .pinned: "pin"
        case .sensitive: "key.fill"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: HistoryFilter? = .all
    @State private var selectedID: Int64?
    @State private var searchText = ""
    /// Filter sidebar: on by default (categories must be discoverable),
    /// persisted per the user's toggle.
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    @State private var splitPosition: Double = SettingsStore.shared.splitPosition
    /// Clear-all confirmation, also triggered from the status menu.
    @State private var showClearAll = false
    /// Copy acknowledgment — the popover shows a toast; the main window was
    /// silent, so a click felt like nothing happened.
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?
    /// Debounce for the search field: the store query runs once typing pauses.
    @State private var searchDebounce: Task<Void, Never>?

    /// The main window's list. Backed by the published `mainItems` snapshot —
    /// never a store query in the body (queries here made every click lag).
    private var filtered: [ClipboardItem] { state.mainItems }

    /// Builds the query from the current sidebar filter + search text and
    /// hands it to AppState. Called on filter changes, launch, and (after a
    /// 0.2s debounce) search-text changes.
    private func applyFilter() {
        var f = QueryFilter()
        f.textQuery = searchText
        if !searchText.isEmpty { f.useRegex = searchText.isValidRegex }
        switch selection {
        case .text: f.kind = .text
        case .images: f.kind = .image
        case .files: f.kind = .file
        case .today: f.bucket = .today
        case .favorites: f.favoritesOnly = true
        case .pinned: f.pinnedOnly = true
        case .sensitive: f.sensitiveOnly = true
        default: break
        }
        state.setMainQuery(f)
    }

    var body: some View {
        // NavigationStack gives .searchable a home — without it the search
        // field never renders (this view is hosted in a bare NSHostingController).
        NavigationStack {
            HSplitView {
                // Sidebar (visible only when toggled on)
                if sidebarVisible {
                    sidebarContent
                        .frame(minWidth: 170, idealWidth: 190)
                }

                // History list – 40% of available width
                list
                    .frame(
                        minWidth: 200,
                        idealWidth: idealListWidth
                    )

                // Detail panel – fills remaining space
                detail
                    .frame(minWidth: 300)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { sidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
            }
        }
        .navigationTitle("Kopie")
        .sheet(isPresented: $showClearAll) {
            ConfirmDialog(
                title: "Clear clipboard history?",
                message: "This will permanently remove all saved clipboard items. This action cannot be undone.",
                confirmTitle: "Clear All", destructive: true,
                onConfirm: { state.removeAll(); showClearAll = false },
                onCancel: { showClearAll = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .kopieRequestClearAll)) { _ in
            showClearAll = true
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                CopiedToast().padding(.bottom, 16)
            }
        }
        .onAppear {
            // Load persisted split position
            splitPosition = SettingsStore.shared.splitPosition
            applyFilter()

            // Auto-select the first item when the view appears
            if selectedID == nil, let firstItem = filtered.first {
                selectedID = firstItem.id
            }
        }
        .onChange(of: selection) { _ in
            applyFilter()
        }
        .onChange(of: searchText) { _ in
            // Debounce: one store query after the user stops typing.
            searchDebounce?.cancel()
            searchDebounce = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                applyFilter()
            }
        }
        .onChange(of: state.mainItems) { items in
            // If the currently selected item is no longer visible, select the first one
            if let selectedID, !items.contains(where: { $0.id == selectedID }) {
                self.selectedID = items.first?.id
            }
        }
        .onDisappear { searchDebounce?.cancel() }
    }

    // MARK: - Computed widths

    /// Ideal width for the list column based on persisted split position.
    private var idealListWidth: CGFloat {
        let windowWidth: CGFloat = 1000 // Reference width for ideal sizing
        return windowWidth * splitPosition
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selection) {
            Section {
                HStack(spacing: 8) {
                    Image(nsImage: AppIcon.image(pointSize: 18))
                    Text("Kopie").font(.headline)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            Section("History") {
                ForEach(HistoryFilter.allCases) { f in
                    Label(f.label, systemImage: f.symbol).tag(f)
                }
            }
            Section {
                Button {
                    GlobalActions.openSettings?()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            if selection == nil { selection = .all }
        }
    }

    // MARK: - List

    private var list: some View {
        List(selection: $selectedID) {
            let groups = groupByDay(filtered)
            if groups.isEmpty {
                EmptyStateView(
                    symbol: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                    title: searchText.isEmpty ? "Nothing copied yet" : "Nothing found",
                    message: searchText.isEmpty ? "Copy some text or an image and it will appear here." : "Try searching for something else.")
            } else {
                ForEach(groups) { group in
                    Section(group.label) {
                        ForEach(group.items) { item in
                            HistoryRow(item: item,
                                       thumbnail: state.thumbnail(for: item),
                                       onCopy: { copy(item) },
                                       onRemove: { state.remove(item) },
                                       onFavorite: { state.toggleFavorite(item) },
                                       onPin: { state.togglePin(item) },
                                       onCopyPlainText: item.isRichText ? { copyPlainText(item) } : nil,
                                       onToggleQueue: { state.toggleQueued(item) },
                                       isQueued: state.isQueuedForPaste(item),
                                       onToggleExpire: { state.toggleExpireAfterUse(item) },
                                       expiresAfterUse: state.isExpiredAfterUse(item),
                                       copyOnTap: false)
                                .tag(item.id)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .searchable(text: $searchText, prompt: "Search clipboard…")
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let item = filtered.first(where: { $0.id == selectedID }) {
                DetailsPanel(item: item, onCopied: { showToast() })
            } else {
                EmptyStateView(symbol: "square.stack", title: "Select an item", message: "Choose an item from your history to see its details.")
            }
        }
    }

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item)
        showToast()
    }

    /// Shows the Copied toast for a moment, replacing any running timer.
    private func showToast() {
        showCopiedToast = true
        copiedToastTask?.cancel()
        copiedToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showCopiedToast = false }
        }
    }

    /// Context-menu action: stages the item without its rich-text flavors.
    private func copyPlainText(_ item: ClipboardItem) {
        state.copyBack(item, plainTextOnly: true)
    }
}
