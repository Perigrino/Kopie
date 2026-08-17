import SwiftUI
import KopieCore
import AppKit

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kopie").font(.headline)
                Spacer()
                Button {
                    withAnimation { state.isPaused ? state.startMonitoring() : state.pauseMonitoring() }
                } label: {
                    Image(systemName: state.isPaused ? "play.circle" : "pause.circle")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(DS.pad)
            Divider()
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard…", text: $state.searchText)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { state.refresh() }
            }.padding(10).padding(.horizontal, DS.pad).padding(.bottom, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))

            if state.items.isEmpty {
                EmptyStateView(symbol: "doc.on.clipboard",
                               title: state.isPaused ? "Monitoring paused" : "Nothing copied yet",
                               message: state.isPaused ? "Resume monitoring to start saving copied items again." : "Copy some text or an image and it will appear here.")
                    .frame(height: 200)
                if state.isPaused {
                    Button("Resume Monitoring") { state.startMonitoring() }.padding(.bottom, 12)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(state.items) { item in
                            HistoryRow(item: item, isPaused: state.isPaused,
                                       onCopy: { state.copyBack(item) },
                                       onRemove: { state.remove(item) },
                                       onFavorite: { state.toggleFavorite(item) })
                        }
                    }.padding(.horizontal, DS.pad).padding(.vertical, 8)
                }.frame(height: 360)
            }
            Divider()
            HStack {
                Button("Open Kopie") { openMain() }
                Button("Settings…") { showSettings() }
                Spacer()
                Button("Clear") { state.removeAll() }
            }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .padding(10).padding(.horizontal, DS.pad)
        }
        .frame(width: 340)
        .onAppear { state.refresh(); DispatchQueue.main.async { searchFocused = true } }
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
