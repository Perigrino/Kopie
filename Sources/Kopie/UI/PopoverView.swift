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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            content
            Divider()
            bottomBar
        }
        .frame(width: 340)
        .onAppear { state.refresh(); DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: state.searchText) { state.refresh() }
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
                onConfirm: { state.removeAll(); showClearConfirm = false; notifyCleared() },
                onCancel: { showClearConfirm = false })
        }
    }

    private var header: some View {
        HStack {
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupByDay(state.items)) { group in
                        Text(group.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10).padding(.bottom, 4)
                        ForEach(group.items) { item in
                            HistoryRow(item: item,
                                       isPaused: state.isPaused,
                                       thumbnail: state.thumbnail(for: item),
                                       selectionMode: selectionMode,
                                       isSelected: selectedIDs.contains(item.id),
                                       onCopy: { copy(item) },
                                       onRemove: { state.remove(item) },
                                       onFavorite: { state.toggleFavorite(item) },
                                       onToggleSelect: { toggleSelect(item.id) })
                        }
                    }
                }.padding(.horizontal, DS.pad).padding(.vertical, 8)
            }.frame(height: 360)
        }
    }

    private var bottomBar: some View {
        HStack {
            if selectionMode {
                Button(selectedIDs.isEmpty ? "Select All" : "Cancel") {
                    if selectedIDs.isEmpty {
                        selectedIDs = Set(state.items.map { $0.id })
                    } else {
                        selectionMode = false; selectedIDs = []
                    }
                }
                if !selectedIDs.isEmpty {
                    Button("Delete \(selectedIDs.count)") { deleteSelected() }
                        .foregroundStyle(.red)
                }
            } else {
                Button("Open Kopie") { openMain() }
                Button("Settings…") { showSettings() }
            }
            Spacer()
            Button(selectionMode ? "Done" : "Select") {
                withAnimation { selectionMode.toggle(); if !selectionMode { selectedIDs = [] } }
            }
            if !selectionMode {
                Button("Clear") { showClearConfirm = true }
                    .disabled(state.items.isEmpty)
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

    private func toggleSelect(_ id: Int64) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func deleteSelected() {
        let ids = Array(selectedIDs)
        state.remove(ids)
        selectionMode = false
        selectedIDs = []
    }

    private func notifyCleared() {
        NotificationCenter.default.post(name: .kopieHistoryCleared, object: nil)
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

extension Notification.Name { static let kopieHistoryCleared = Notification.Name("kopieHistoryCleared") }
