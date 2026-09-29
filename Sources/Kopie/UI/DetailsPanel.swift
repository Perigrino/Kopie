import SwiftUI
import KopieCore
import AppKit

struct DetailsPanel: View {
    let item: ClipboardItem
    @EnvironmentObject var state: AppState
    @State private var showRichText = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.typeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            metaGrid
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Detected language/format for the Formatted tab, based on the item text.
    private var codeLanguage: CodeLanguage {
        guard let text = item.text else { return .plainText }
        return CodeLanguageDetector.detect(content: text)
    }

    @ViewBuilder private var content: some View {
        if item.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                // Load rich text data once
                let richData = item.isRichText ? state.richText(for: item) : nil
                let hasRich = richData != nil
                let isHTML = item.richTextRelPath?.hasSuffix(".html") ?? false
                let isCode = codeLanguage != .plainText

                // Always show the Plain/Formatted toggle for text items so you can
                // switch between the two either way.
                Picker("", selection: $showRichText) {
                    Text("Plain Text").tag(false)
                    Text("Formatted").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Group {
                    if showRichText {
                        if isCode {
                            // The code card scrolls itself (both axes), so don't
                            // wrap it in another ScrollView — that caused nested
                            // vertical scrollbars and a collapsed one-line view.
                            FormattedCodeView(content: item.text ?? "", language: codeLanguage)
                        } else if hasRich, let data = richData {
                            ScrollView {
                                RichTextRepresentation(data: data, isHTML: isHTML)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            // Not rich text and not detected code: friendly empty state.
                            EmptyStateView(symbol: "textformat",
                                           title: "No rich text",
                                           message: "This copied item is plain text — it has no rich formatting like bold, italics, colours, or links. Switch to the Plain Text tab to see the raw text.")
                        }
                    } else {
                        // Plain Text tab
                        ScrollView {
                            Text(item.text ?? "")
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .id(item.id) // rebuild when a different item is selected
                .animation(.easeInOut(duration: 0.18), value: showRichText) // crossfade tabs
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if item.kind == .file {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(path)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let img = state.fullImage(for: item) ?? state.thumbnail(for: item) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        } else {
            EmptyStateView(symbol: "photo", title: "Image unavailable", message: "The image file could not be loaded.")
        }
    }

    private var metaGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            // Source application
            if item.sourceApp != nil {
                GridRow { meta("Application", item.sourceAppName) }
            }
            
            // Copy timestamps
            GridRow { meta("First Copy", item.createdAt.formatted(date: .abbreviated, time: .standard)) }
            if let lastCopy = item.lastCopiedAt {
                GridRow { meta("Last Copy", lastCopy.formatted(date: .abbreviated, time: .standard)) }
            }
            
            // Copy count (show only if > 1)
            if item.copyCount > 1 {
                GridRow { meta("Copies", item.copyCountLabel) }
            }
            
            // Content-specific metadata
            if item.kind == .text, let c = item.charCount { GridRow { meta("Characters", "\(c)") } }
            if item.kind == .file, let n = item.filePaths?.count { GridRow { meta("Files", "\(n)") } }
            if item.kind == .image, let d = item.dimensionLabel { GridRow { meta("Dimensions", d) } }
            GridRow { meta("Size", ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file)) }
            if item.kind == .text, codeLanguage != .plainText {
                GridRow { meta("Language", codeLanguage.displayName) }
            }
            if item.isFavorite { GridRow { meta("Favorite", "Yes") } }
            if item.isPinned { GridRow { meta("Pinned", "Yes") } }
            if item.isRichText { GridRow { meta("Rich Text", "Yes") } }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func meta(_ label: String, _ value: String) -> some View {
        Group {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(.primary)
        }
        .font(.caption)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                state.copyBack(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy to clipboard (⌘C)")
            
            Divider().frame(height: 20)
            
            Button {
                state.toggleFavorite(item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(item.isFavorite ? .yellow : .primary)
            }
            .buttonStyle(.bordered)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")
            
            Button {
                state.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.isPinned ? .blue : .primary)
            }
            .buttonStyle(.bordered)
            .help(item.isPinned ? "Unpin item" : "Pin to top")
            
            Spacer()
            
            Button(role: .destructive) {
                state.remove(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .help("Delete item")
        }
        .padding(.top, 4)
    }
}
