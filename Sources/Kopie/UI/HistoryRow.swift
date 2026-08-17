import SwiftUI
import KopieCore
import AppKit

struct HistoryRow: View {
    let item: ClipboardItem
    var thumbnail: NSImage?
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var isHighlighted: Bool = false
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onFavorite: () -> Void
    var onToggleSelect: (() -> Void)? = nil
    /// When false, tapping the row does not copy (lets a containing List handle selection).
    var copyOnTap: Bool = true
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
            } else if !selectionMode && item.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(8)
        .background(backgroundFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isHighlighted && !selectionMode {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .modifier(TapAction(enabled: selectionMode || copyOnTap) {
            if selectionMode { onToggleSelect?() ?? () }
            else { onCopy() }
        })
    }

    /// Applies onTapGesture only when enabled, so a plain row can participate
    /// in List selection instead of swallowing the click.
    private struct TapAction: ViewModifier {
        let enabled: Bool
        let action: () -> Void
        func body(content: Content) -> some View {
            if enabled {
                content.onTapGesture(perform: action)
            } else {
                content
            }
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
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            .help("Copy")
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
            }.buttonStyle(.plain).foregroundStyle(item.isFavorite ? .yellow : .secondary)
            .help(item.isFavorite ? "Unfavorite" : "Favorite")
            Button(action: onRemove) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Delete")
        }
    }

    private var backgroundFill: Color {
        if selectionMode && isSelected { Color.accentColor.opacity(0.12) }
        else if isHighlighted { Color.accentColor.opacity(0.08) }
        else { Color.clear }
    }

    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}
