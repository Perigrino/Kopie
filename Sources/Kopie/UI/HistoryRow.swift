import SwiftUI
import KopieCore
import AppKit

struct HistoryRow: View {
    let item: ClipboardItem
    var isPaused: Bool
    var thumbnail: NSImage?
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onFavorite: () -> Void
    var onToggleSelect: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .onTapGesture { onToggleSelect?() }
            }
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
            if !selectionMode && hovering {
                quickButtons
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            selectionMode ? (onToggleSelect?() ?? onCopy()) : onCopy()
        }
    }

    @ViewBuilder private var icon: some View {
        if let thumb = thumbnail {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if item.kind == .image {
            Image(systemName: "photo")
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "doc.text")
                .frame(width: 40, height: 40)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var quickButtons: some View {
        HStack(spacing: 8) {
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
            }.buttonStyle(.plain).foregroundStyle(item.isFavorite ? .yellow : .secondary)
            Button(action: onRemove) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}
