import SwiftUI
import KopieCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: HistoryFilter? = .all
    @State private var selectedID: Int64?
    @State private var searchText = ""

    private var filtered: [ClipboardItem] {
        var f = QueryFilter()
        f.textQuery = searchText
        switch selection {
        case .text: f.kind = .text
        case .images: f.kind = .image
        case .files: f.kind = .file
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
            if let item = filtered.first(where: { $0.id == selectedID }) {
                DetailsPanel(item: item)
            } else {
                EmptyStateView(symbol: "square.stack", title: "Select an item", message: "Choose an item from your history to see its details.")
            }
        }
        .navigationTitle("Kopie")
    }

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

    private func copy(_ item: ClipboardItem) {
        state.copyBack(item)
    }
}
