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

    private var contentType: ContentType {
        guard let text = item.text else { return .plainText }
        return ContentDetector.detectContentType(text)
    }

    /// Renders the body of the "Formatted" tab. Code always renders as the
    /// dark editor card; rich text renders as attributed text; anything else
    /// gets a friendly empty state.
    @ViewBuilder private func formattedBody(richData: Data?, hasRich: Bool, isHTML: Bool, isCode: Bool) -> some View {
        if isCode, case .code(let language) = contentType {
            CodeBlockView(code: item.text ?? "", language: language)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if hasRich, let data = richData {
            RichTextRepresentation(data: data, isHTML: isHTML)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyStateView(symbol: "textformat", title: "No rich text",
                           message: "This copied item doesn't have any rich text formatting. Switch to the Plain Text tab to view it as plain text.")
        }
    }
    
    @ViewBuilder private var content: some View {
        if item.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                // Load rich text data once
                let richData = item.isRichText ? state.richText(for: item) : nil
                let hasRich = richData != nil
                let isHTML = item.richTextRelPath?.hasSuffix(".html") ?? false
                let isCode = { if case .code = contentType { return true } else { return false } }()
                // Show the Plain/Formatted toggle whenever there is formatting to
                // show. If a plain item is selected while still in Formatted mode,
                // keep it visible so the user can switch back.
                let showTabs = hasRich || isCode || showRichText

                if showTabs {
                    Picker("", selection: $showRichText) {
                        Text("Plain Text").tag(false)
                        Text("Formatted").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Wrap the body in a scroll view so long content scrolls instead of
                // overflowing the panel. The tabs pin above it.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if showRichText {
                            formattedBody(richData: richData, hasRich: hasRich, isHTML: isHTML, isCode: isCode)
                        } else {
                            Text(item.text ?? "")
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .id(item.id) // rebuild when a different item is selected
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            if item.kind == .text, case .code(let lang) = contentType, let language = lang {
                GridRow { meta("Language", language.uppercased()) }
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
            // Primary action: Copy
            Button {
                state.copyBack(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy to clipboard (⌘C)")
            
            Divider().frame(height: 20)
            
            // Toggle actions
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
            
            // Destructive action: Delete
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
