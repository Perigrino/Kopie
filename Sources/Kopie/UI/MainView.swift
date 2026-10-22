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
    @Environment(\.colorScheme) private var scheme
    @State private var selection: HistoryFilter? = .all
    @State private var selectedID: Int64?
    @State private var searchText = ""
    /// ⌘F focuses the clipboard search field (mock shows a ⌘F hint).
    @FocusState private var searchFocused: Bool
    /// Filter sidebar: on by default (categories must be discoverable),
    /// persisted per the user's toggle.
    @AppStorage("sidebarVisible") private var sidebarVisible = true
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
        // NavigationStack gives the toolbar a home (this view is hosted in a
        // bare NSHostingController).
        NavigationStack {
            ZStack {
                // The Ember canvas fills the whole window — near-black with two
                // radial glows in dark, warm paper in light.
                EmberCanvas(scheme: scheme)
                mainLayout
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
            applyFilter()

            // Auto-select the first item when the view appears
            if selectedID == nil, let firstItem = filtered.first {
                selectedID = firstItem.id
            }

            // macOS autofocuses the first text field when a window becomes
            // key; the spec opens with the field unfocused (⌘F hint shown).
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !Task.isCancelled { searchFocused = false }
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

    /// Spec layout, widened per request: fixed sidebar + flexible list + fixed
    /// 440px aside (spec base `aside{width:340px;flex:none;padding:20px}`, bumped
    /// to 440 so rich-text previews breathe) — no resizable splitter, no dead
    /// gutters. The HStack fills the window so every pane runs edge to edge,
    /// top to bottom.
    private var mainLayout: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebarContent
                    .frame(width: 208)
            }

            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            detail
                .frame(width: 440)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sidebar

    /// Kopie's nav — stays on the left. Custom `nav-item` rows per the spec:
    /// 13px label, 9px gap, 7×10 padding, radius 9; hover = chip fill,
    /// active = the Ember gradient pill with white text. Settings pinned at
    /// the bottom.
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Spec brand row: `2px 8px 14px`, icon 22, wordmark 14/600.
            HStack(spacing: 9) {
                Image(nsImage: AppIcon.image(pointSize: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Kopie")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary(for: scheme))
            }
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 14)

            // Spec `.eyebrow`: 10/700 uppercase, wide tracking, tertiary.
            Text("History")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary(for: scheme))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ForEach(HistoryFilter.allCases) { f in
                EmberNavItem(
                    symbol: f.symbol,
                    title: f.label,
                    badge: count(for: f),
                    isActive: selection == f,
                    scheme: scheme) {
                        selection = f
                    }
            }

            Spacer(minLength: 12)

            EmberNavItem(
                symbol: "gearshape",
                title: "Settings",
                isActive: false,
                scheme: scheme) {
                    GlobalActions.openSettings?()
                }
        }
        .padding(10)
    }

    /// Sidebar nav row implementing the spec's `.nav-item` chrome.
    private struct EmberNavItem: View {
        let symbol: String
        let title: String
        /// Spec `.badge`: 10px tabular count, right-aligned, 70% opacity.
        var badge: Int? = nil
        var isActive: Bool
        let scheme: ColorScheme
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 9) {
                    Image(systemName: symbol)
                        .font(.system(size: 15))
                        .frame(width: 16)
                    Text(title)
                        .font(.system(size: 13))
                    if let badge {
                        Spacer(minLength: 0)
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .opacity(0.7)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.gradient)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.chipColor(for: scheme))
                    }
                }
                .foregroundStyle(isActive ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(Theme.textSecondary(for: scheme)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - List

    private var list: some View {
        // .leading matters: the default VStack alignment would center the
        // page header (its own width) over the column.
        VStack(alignment: .leading, spacing: 0) {
            // Spec `.page-header`: 26/700 tight tracking + 13px subtitle.
            VStack(alignment: .leading, spacing: 3) {
                Text("History")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.textPrimary(for: scheme))
                Text("Everything you copy, available when you need it.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary(for: scheme))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Spec search row `14px 24px 0` — field flex-1 + a Today chip.
            HStack(spacing: 8) {
                searchField
                todayChip
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filtered.isEmpty {
                        EmptyStateView(
                            symbol: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                            title: searchText.isEmpty ? "Nothing copied yet" : "Nothing found",
                            message: searchText.isEmpty ? "Copy some text or an image and it will appear here." : "Try searching for something else.")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(groupByDay(filtered)) { group in
                            Section {
                                LazyVStack(alignment: .leading, spacing: 8) {
                                    ForEach(group.items) { item in
                                        HistoryRow(item: item,
                                                   thumbnail: state.thumbnail(for: item),
                                                   isSelected: item.id == selectedID,
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
                                            .onTapGesture { selectedID = item.id }
                                            .id(item.id)
                                    }
                                }
                            } header: {
                                groupLabel(group.label, count: group.items.count)
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            // Extra trailing clearance keeps the rows clear of the
            // window's overlay vertical scrollbar.
            .padding(.leading, 18)
            .padding(.trailing, 46)
            .padding(.bottom, 18)

            // Hidden ⌘F activator: focuses the search field like the badge hint.
            Button {
                searchFocused = true
            } label: { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        }
    }

    /// The spec's `.field`: 34px-high rounded search well — white .06 fill on
    /// dark, solid white with a hairline on light. Focus paints the 1px
    /// accent ring; an inert ⌘F hint sits right-aligned while empty.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary(for: scheme))
            TextField("Search clipboard…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary(for: scheme))
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary(for: scheme))
                }
                .buttonStyle(.plain)
            } else if !searchFocused {
                Text("⌘F")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(Theme.fieldBackground(for: scheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(searchFocused
                              ? AnyShapeStyle(Theme.accent)
                              : AnyShapeStyle(scheme == .light ? AnyShapeStyle(Theme.hairline(for: scheme)) : AnyShapeStyle(Color.clear)),
                              lineWidth: 1)
        }
        .animation(Motion.quick, value: searchText.isEmpty)
        .animation(Motion.quick, value: searchFocused)
    }

    /// The spec's `.chip` beside the field: clock icon + "Today", gradient
    /// pill when the Today filter is live.
    private var todayChip: some View {
        let on = selection == .today
        return Button {
            withAnimation(Motion.quick) { selection = on ? .all : .today }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(on ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(Theme.textSecondary(for: scheme)))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(on ? AnyShapeStyle(Theme.gradient)
                                  : AnyShapeStyle(Theme.chipColor(for: scheme)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show only what you copied today")
    }

    /// The spec's `.group-label`: 11px semibold uppercase, wide tracking,
    /// tertiary color + a right-aligned tabular count. Scrolls with content
    /// over the shared canvas — margin `18px 6px 8px`.
    private func groupLabel(_ title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: Theme.tMeta, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary(for: scheme))
            Spacer(minLength: 12)
            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.system(size: Theme.tMeta))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary(for: scheme))
        }
        .padding(.leading, 6)
        // Clear the same overlay scrollbar the rows clear.
        .padding(.trailing, 34)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sidebar badge counts, straight off the shared store snapshot.
    private func count(for f: HistoryFilter) -> Int {
        let items = state.items
        switch f {
        case .all: return items.count
        case .text: return items.filter { $0.kind == .text }.count
        case .images: return items.filter { $0.kind == .image }.count
        case .files: return items.filter { $0.kind == .file }.count
        case .today: return items.filter { Calendar.current.isDateInToday($0.createdAt) }.count
        case .favorites: return items.filter { $0.isFavorite }.count
        case .pinned: return items.filter { $0.isPinned }.count
        case .sensitive: return items.filter { $0.isSensitive }.count
        }
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
