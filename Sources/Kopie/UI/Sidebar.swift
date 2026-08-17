import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, images, today, favorites
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .today: "Today"
        case .favorites: "Favorites"
        }
    }
    var symbol: String {
        switch self {
        case .all: "tray.full"
        case .text: "doc.text"
        case .images: "photo"
        case .today: "clock"
        case .favorites: "star"
        }
    }
}

struct Sidebar: View {
    @Binding var selection: HistoryFilter?
    @EnvironmentObject var state: AppState

    var body: some View {
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
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        .onAppear {
            if selection == nil { selection = .all }
        }
    }
}
