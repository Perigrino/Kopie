import SwiftUI
import KopieCore

struct HistoryRow: View {
    let item: ClipboardItem
    var isPaused: Bool
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onFavorite: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview).lineLimit(1).font(.body)
                HStack(spacing: 6) {
                    Text(item.typeLabel).font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    Text(time(item.createdAt)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if item.kind == .image, item.width != nil {
                        Text("·").foregroundStyle(.secondary)
                        Text("\((item.width ?? 0)) × \((item.height ?? 0))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if let c = item.charCount { Text("·").foregroundStyle(.secondary); Text("\(c) chars").font(.caption).foregroundStyle(.tertiary) }
                }
            }
            Spacer()
            if hovering {
                quickButtons
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
    }
    @ViewBuilder private var icon: some View {
        if item.kind == .image {
            Text("🖼").frame(width: 32, height: 32)
        } else {
            Image(systemName: "doc.text").frame(width: 32, height: 32).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var quickButtons: some View {
        HStack(spacing: 4) {
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
            }.buttonStyle(.plain)
            Button(action: onRemove) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }
    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}
