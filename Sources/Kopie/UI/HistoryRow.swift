import SwiftUI
import KopieCore
import AppKit

struct HistoryRow: View {
    let item: ClipboardItem
    var thumbnail: NSImage?
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var isHighlighted: Bool = false
    @Environment(\.colorScheme) private var scheme
    var onCopy: () -> Void
    /// What a tap on the row itself does. Nil falls back to `onCopy`, so a
    /// caller can make "click the row" paste while the context menu's Copy
    /// stays a plain clipboard stage. Set alongside `copyOnTap`.
    var onPaste: (() -> Void)? = nil
    var onRemove: () -> Void
    var onFavorite: () -> Void
    var onPin: () -> Void = {}
    /// Copies the item staging only the plain-text flavor (strips RTF/HTML).
    var onCopyPlainText: (() -> Void)? = nil
    /// Adds/removes the item from the sequential paste queue.
    var onToggleQueue: (() -> Void)? = nil
    var isQueued: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    /// Marks/unmarks the item for delete-after-next-paste (one-time secrets).
    var onToggleExpire: (() -> Void)? = nil
    var expiresAfterUse: Bool = false
    /// When false, tapping the row does not copy (lets a containing List handle selection).
    var copyOnTap: Bool = true
    /// Notifies when the pointer enters/leaves the row (used for popover previews).
    var onHoverChange: ((Bool) -> Void)? = nil
    /// Popover-compact chrome per the spec: padding 8×10, 36×36 tile, 13px title.
    var compact: Bool = false
    @State private var hovering = false

    /// Row paddings — `.row` is 10×12, the popover's compact override is 8×10.
    private var rowPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            : EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    }
    /// `.tile` — 44×44 in the main list, 36×36 popover-compact.
    private var tileSize: CGFloat { compact ? 36 : 44 }

    var body: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.textTertiary(for: scheme)))
                    .onTapGesture { onToggleSelect?() }
            }
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    // State prefix glyphs belong to the main list only — the
                    // popover mock's rows carry a bare title.
                    if !compact {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.accentInk(for: scheme))
                        }
                        if item.isSensitive {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.warn(for: scheme))
                                .help(item.sensitiveKindLabel ?? "Sensitive content")
                        }
                        if expiresAfterUse {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary(for: scheme))
                                .help("Deletes after the next paste")
                        }
                    }
                    Text(displayPreview)
                        .lineLimit(1)
                        .font(.system(size: compact ? 13 : Theme.tRow, weight: .medium))
                        .foregroundStyle(Theme.textPrimary(for: scheme))
                }
                metadataLine
            }
            Spacer(minLength: 4)
            if !selectionMode && hovering {
                quickButtons
            }
        }
        .padding(rowPadding)
        .background(backgroundFill,
                    in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .overlay {
            if isHighlighted && !selectionMode {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
            }
        }
        // `.row:hover` — the spec's soft lift (row-shadow) under the brightened
        // fill: dark `0 14px 30px black .42`, light `0 12px 26px #4A2D1A .12`.
        .shadow(color: hovering && !isSelected
                    ? (scheme == .dark
                        ? Color.black.opacity(0.42)
                        : Color(red: 74 / 255, green: 45 / 255, blue: 26 / 255).opacity(0.12))
                    : .clear,
                radius: scheme == .dark ? 15 : 13, x: 0, y: hovering && !isSelected ? (scheme == .dark ? 14 : 12) : 0)
        .scaleEffect(hovering && !isSelected ? 1.006 : 1, anchor: .center)
        .contentShape(Rectangle())
        .onHover { hovering = $0; onHoverChange?(hovering) }
        // Gives the quick-buttons opacity transition (and the selection fill)
        // a 150ms ease instead of a hard swap.
        .animation(.easeInOut(duration: 0.15), value: hovering)
        // The tap gesture goes on BEFORE .contextMenu so it stays the innermost
        // recognizer: the menu is an outer wrapper (the usual control-inside-menu
        // arrangement) and can never compete with the row's own click. When the
        // two were reversed the row needed several clicks before one landed —
        // the competing recognizers swallowed the early ones.
        .modifier(TapAction(enabled: selectionMode || copyOnTap) {
            if selectionMode { onToggleSelect?() ?? () }
            else { (onPaste ?? onCopy)() }
        })
        .contextMenu {
            ContextMenuBuilder(
                item: item,
                onCopy: onCopy,
                onRemove: onRemove,
                onFavorite: onFavorite,
                onPin: onPin,
                onCopyPlainText: onCopyPlainText,
                onToggleQueue: onToggleQueue,
                isQueued: isQueued,
                onToggleExpire: onToggleExpire,
                expiresAfterUse: expiresAfterUse
            )
        }
    }

    /// Sentinel-masked rows never show their content in the list — not even
    /// on hover. Reveal happens only in the details panel, deliberately.
    private var displayPreview: String {
        item.isSensitive ? String(repeating: "•", count: 12) : item.preview
    }

    @ViewBuilder private var metadataLine: some View {
        HStack(spacing: 5) {
            // Popover compact rows drop the source app per the spec mock
            // ("Text · 5:10 pm · 74 chars"); main list rows keep it.
            if !compact, let sourceApp = item.sourceApp {
                Image(nsImage: AppIconResolver.icon(for: sourceApp, size: NSSize(width: 11, height: 11)))
                    .frame(width: 11, height: 11)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(item.sourceAppName)
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textSecondary(for: scheme))
                    .lineLimit(1)
            }
            if !compact && item.sourceApp != nil {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
            // Sensitive rows lead with the warn-colored tag (compact) or keep
            // the type label and tag them after it (main list, line 657).
            if compact && item.isSensitive {
                Text("Sensitive")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.warn(for: scheme))
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            } else {
                Text(item.typeLabel)
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
            if !compact && item.isSensitive {
                Text("Sensitive")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.warn(for: scheme))
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
            if item.isRichText {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Text("Rich")
                    .font(.system(size: Theme.tMeta, weight: .medium))
                    .foregroundStyle(Theme.accentInk(for: scheme))
            }
            
            // Time
            Text("·")
                .font(.system(size: Theme.tMeta))
                .foregroundStyle(Theme.textTertiary(for: scheme))
            Text(time(item.createdAt))
                .font(.system(size: Theme.tMeta))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary(for: scheme))
            
            // Content-specific details
            if item.kind == .image, let d = item.dimensionLabel {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Text(d)
                    .font(.system(size: Theme.tMeta))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            } else if item.kind == .text, let c = item.charCount {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Text("\(c) chars")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            } else if item.kind == .file, let n = item.filePaths?.count {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Text("\(n) file\(n == 1 ? "" : "s")")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
            }
            
            // Copy count — main list only; the popover mock's compact rows
            // carry no "×N" tail.
            if !compact && item.copyCount > 1 {
                Text("·")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Text("\(item.copyCount)×")
                    .font(.system(size: Theme.tMeta))
                    .foregroundStyle(Theme.textTertiary(for: scheme))
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

    /// Color-copies present as their own swatch instead of a doc glyph.
    private var colorValue: KopieCore.ColorParser.ColorValue? {
        item.kind == .text ? ColorParser.parse(item.text ?? "") : nil
    }

    @ViewBuilder private var icon: some View {
        // `.tile` — chip fill, radius 12; `.grad` (Ember gradient + white
        // glyph) when a compact popover row is keyboard-highlighted; photos
        // and color swatches keep their own fills and lose the chip.
        let tileShape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
        let showChip = !(colorValue != nil || thumbnail != nil || item.kind == .image)
        ZStack(alignment: .bottomTrailing) {
            if compact && (isHighlighted || isSelected) && !selectionMode && !(colorValue != nil || thumbnail != nil) {
                tileShape
                    .fill(Theme.gradient)
                    .frame(width: tileSize, height: tileSize)
                    .overlay {
                        Image(systemName: item.kind == .file ? "folder" : "doc.text")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 6, y: 3)
            } else if let color = colorValue {
                tileShape
                    .fill(Color(nsColor: nsColor(for: color)))
                    .overlay(
                        tileShape
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .frame(width: tileSize, height: tileSize)
            } else if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(tileShape)
            } else if item.isSensitive {
                // `.tile.warn` — warn 16% fill with the warn key glyph; rows
                // stay outside the tint system (orange is never gradient).
                tileShape
                    .fill(Theme.warn(for: scheme).opacity(0.16))
                    .frame(width: tileSize, height: tileSize)
                    .overlay {
                        Image(systemName: "key.fill")
                            .font(.system(size: compact ? 15 : 18))
                            .foregroundStyle(Theme.warn(for: scheme))
                    }
            } else {
                tileShape
                    .fill(showChip ? AnyShapeStyle(Theme.chipColor(for: scheme)) : AnyShapeStyle(Color.clear))
                    .frame(width: tileSize, height: tileSize)
                    .overlay {
                        Image(systemName: item.kind == .image ? "photo"
                                : item.kind == .file ? "folder" : "doc.text")
                            .font(.system(size: compact ? 15 : 18))
                            .foregroundStyle(Theme.textSecondary(for: scheme))
                    }
            }
        }
    }

    private var backgroundFill: Color {
        // Rows are always cards (`--card`); state layers stack on top
        // exactly like the CSS cascade: sel > highlight > hover.
        if selectionMode && isSelected { Theme.accent.opacity(0.12) }
        // Plain-selection fill from the spec: --row-sel
        else if isSelected { Theme.rowSelected(for: scheme) }
        else if isHighlighted { Theme.accent.opacity(0.08) }
        else if hovering { Theme.rowHover(for: scheme) }
        else { Theme.cardBackground(for: scheme) }
    }

    @ViewBuilder private var quickButtons: some View {
        // Spec: main rows carry [pin (on if pinned) or star (on if favorited)]
        // + [copy] + [trash]; popover compact rows carry [copy] + [star] —
        // every other action stays in the context menu.
        if compact {
            HStack(spacing: 8) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary(for: scheme))
                .help("Copy again")
                if item.isFavorite || !item.isPinned {
                    Button(action: onFavorite) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item.isFavorite
                                        ? AnyShapeStyle(Theme.star(for: scheme))
                                        : AnyShapeStyle(Theme.textSecondary(for: scheme)))
                    .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
                } else {
                    Button(action: onPin) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AnyShapeStyle(Theme.accentInk(for: scheme)))
                    .help("Unpin")
                }
            }
        } else {
            // Spec: [pin (on if pinned) or star (on if favorited)] + [copy] + [trash]
            HStack(spacing: 8) {
                if item.isFavorite {
                Button(action: onFavorite) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AnyShapeStyle(Theme.star(for: scheme)))
                .help("Remove from favorites")
            } else {
                Button(action: onPin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isPinned ? AnyShapeStyle(Theme.accentInk(for: scheme)) : AnyShapeStyle(Theme.textSecondary(for: scheme)))
                .help(item.isPinned ? "Unpin" : "Pin")
            }
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary(for: scheme))
            .help("Copy again")
            Button(action: onRemove) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary(for: scheme))
            .help("Delete")
            }
        }
    }

    private func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    private func nsColor(for v: KopieCore.ColorParser.ColorValue) -> NSColor {
        NSColor(calibratedRed: v.red, green: v.green, blue: v.blue, alpha: v.alpha)
    }
}
