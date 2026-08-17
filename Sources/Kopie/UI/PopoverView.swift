import SwiftUI
import KopieCore
import AppKit

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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            content
            Divider()
            bottomBar
        }
        .frame(width: 360)
        .onAppear {
            state.refresh()
            DispatchQueue.main.async { searchFocused = true }
            highlightedIndex = state.items.isEmpty ? nil : 0
        }
        .onChange(of: state.searchText) {
            state.refresh()
            highlightedIndex = state.items.isEmpty ? nil : 0
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
        .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
        .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
        .onKeyPress(.return) { copyHighlighted(); return .handled }
        .onKeyPress(.escape) {
            if !state.searchText.isEmpty {
                state.searchText = ""
                state.refresh()
            } else {
                GlobalActions.closePopover?()
            }
            return .handled
        }
        .onKeyPress(.delete) {
            if let idx = highlightedIndex, state.items.indices.contains(idx) {
                state.remove(state.items[idx])
                highlightedIndex = min(idx, state.items.count - 1)
                return .handled
            }
            return .ignored
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3).foregroundStyle(Color.accentColor)
            Text("Kopie").font(.headline)
            if !state.items.isEmpty {
                Text("\(state.items.count)")
                    .font(.caption).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation { state.isPaused ? state.startMonitoring() : state.pauseMonitoring() }
            } label: {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.circle" : "pause.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(state.isPaused ? "Resume monitoring" : "Pause monitoring")
        }.padding(DS.pad)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clipboard…", text: $state.searchText)
                .textFieldStyle(.plain).focused($searchFocused)
                .onSubmit { state.refresh() }
            if !state.searchText.isEmpty {
                Button { state.searchText = ""; state.refresh() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(10).padding(.horizontal, DS.pad).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
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
                                           onToggleSelect: { toggleSelect(item.id) })
                                    .id(item.id)
                                    .onHover { hovering in
                                        if hovering, !selectionMode { highlightedIndex = idx }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, DS.pad).padding(.vertical, 8)
                }
                .frame(height: 360)
                .onChange(of: highlightedIndex) {
                    guard let i = highlightedIndex, state.items.indices.contains(i) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(state.items[i].id, anchor: .center)
                    }
                }
            }
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
                Button { openMain() } label: {
                    Label("Open", systemImage: "square.grid.2x2").labelStyle(.iconOnly)
                }
                .help("Open Kopie window")
                Button { showSettings() } label: {
                    Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
                }
                .help("Open Settings")
                Spacer()
                Button { withAnimation { selectionMode = true } } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .disabled(state.items.isEmpty)
                .help("Multi-select")
                Button { showClearConfirm = true } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(state.items.isEmpty)
                .help("Clear history")
                Divider().frame(height: 14)
                Button { NSApp.terminate(nil) } label: {
                    Label("Quit", systemImage: "power").labelStyle(.iconOnly)
                }
                .help("Quit Kopie")
            }
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        .padding(10).padding(.horizontal, DS.pad)
    }

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item)
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        GlobalActions.openMain?()
    }
    private func showSettings() {
        GlobalActions.openSettings?()
    }
}
