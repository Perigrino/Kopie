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
    var onPin: () -> Void = {}
    /// Copies the item staging only the plain-text flavor (strips RTF/HTML).
    var onCopyPlainText: (() -> Void)? = nil
    /// Adds/removes the item from the sequential paste queue.
    var onToggleQueue: (() -> Void)? = nil
    var isQueued: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    /// When false, tapping the row does not copy (lets a containing List handle selection).
    var copyOnTap: Bool = true
    /// Notifies when the pointer enters/leaves the row (used for popover previews).
    var onHoverChange: ((Bool) -> Void)? = nil
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
                HStack(spacing: 4) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                    Text(item.preview).lineLimit(1).font(.body)
                }
                metadataLine
            }
            Spacer()
            if !selectionMode && hovering {
                quickButtons
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
        .onHover { hovering = $0; onHoverChange?(hovering) }
        // Gives the quick-buttons opacity transition (and the selection fill)
        // a 150ms ease instead of a hard swap.
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .contextMenu {
            ContextMenuBuilder(
                item: item,
                onCopy: onCopy,
                onRemove: onRemove,
                onFavorite: onFavorite,
                onPin: onPin,
                onCopyPlainText: onCopyPlainText,
                onToggleQueue: onToggleQueue,
                isQueued: isQueued
            )
        }
        .modifier(TapAction(enabled: selectionMode || copyOnTap) {
            if selectionMode { onToggleSelect?() ?? () }
            else { onCopy() }
        })
    }

    @ViewBuilder private var metadataLine: some View {
        HStack(spacing: 4) {
            // Source app icon and name (compact)
            if let sourceApp = item.sourceApp {
                Image(nsImage: AppIconResolver.icon(for: sourceApp, size: NSSize(width: 10, height: 10)))
                    .frame(width: 10, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                Text(item.sourceAppName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Type label
            if item.sourceApp != nil {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(item.typeLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if item.isRichText {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Rich")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            
            // Time
            Text("·")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(time(item.createdAt))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            
            // Content-specific details
            if item.kind == .image, let d = item.dimensionLabel {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(d)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if item.kind == .text, let c = item.charCount {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(c) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if item.kind == .file, let n = item.filePaths?.count {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(n) file\(n == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            // Copy count (only if > 1)
            if item.copyCount > 1 {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(item.copyCount)×")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
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
        ZStack(alignment: .bottomTrailing) {
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
            } else if item.kind == .file {
                Image(systemName: "folder")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "doc.text")
                    .frame(width: 40, height: 40)
                    .foregroundStyle(.secondary)
            }
            

        }
    }

    private var backgroundFill: Color {
        if selectionMode && isSelected { Color.accentColor.opacity(0.12) }
        else if isHighlighted { Color.accentColor.opacity(0.08) }
        else { Color.clear }
    }

    @ViewBuilder private var quickButtons: some View {
        HStack(spacing: 8) {
            Button(action: onPin) {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isPinned ? .blue : .secondary)
            .help(item.isPinned ? "Unpin" : "Pin")
            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete")
        }
    }

    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}
