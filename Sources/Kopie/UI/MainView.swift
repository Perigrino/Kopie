import SwiftUI
import KopieCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selection: HistoryFilter? = .all
    @State private var selectedID: Int64?
    @State private var searchText = ""

    private var filtered: [ClipboardItem] {
        var f = QueryFilter()
        f.textQuery = searchText
        switch selection {
        case .text: f.kind = .text
        case .images: f.kind = .image
        case .today: f.bucket = .today
        case .favorites: f.favoritesOnly = true
        default: break
        }
        return state.store.query(f)
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
        } content: {
            list
        } detail: {
            if let item = state.items.first(where: { $0.id == selectedID }) {
                DetailsPanel(item: item)
            } else {
                ContentUnavailableView("Select an item", systemImage: "square.stack", description: Text("Choose an item from your history to see its details."))
            }
        }
        .navigationTitle("Kopie")
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search clipboard…")
        .onAppear {
            GlobalActions.openMain = { openWindow(id: "main") }
        }
    }

    private var list: some View {
        List(selection: $selectedID) {
            let groups = groupByDay(filtered)
            if groups.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Nothing copied yet" : "Nothing found",
                    systemImage: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Copy some text or an image and it will appear here." : "Try searching for something else."))
            } else {
                ForEach(groups) { group in
                    Section(group.label) {
                        ForEach(group.items) { item in
                            HistoryRow(item: item,
                                       isPaused: state.isPaused,
                                       thumbnail: state.thumbnail(for: item),
                                       onCopy: { copy(item) },
                                       onRemove: { state.remove(item) },
                                       onFavorite: { state.toggleFavorite(item) })
                                .tag(item.id)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item)
    }
}
