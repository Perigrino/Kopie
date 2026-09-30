import SwiftUI
import KopieCore
import AppKit

struct DetailsPanel: View {
    let item: ClipboardItem
    @EnvironmentObject var state: AppState
    @State private var showRichText = true
    /// Non-nil while the inline plain-text editor is open.
    @State private var draftText: String?
    @State private var savedRecently = false
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
        .onChange(of: item.id) { _ in
            // Switching items discards any unsaved edit.
            draftText = nil
            savedRecently = false
        }
    }

    /// Detected language/format for the Formatted tab, based on the item text.
    private var codeLanguage: CodeLanguage {
        guard let text = item.text else { return .plainText }
        return CodeLanguageDetector.detect(content: text)
    }

    /// Stored rich-text payload (RTF/HTML) for this item, if any.
    private var richData: Data? {
        item.isRichText ? state.richText(for: item) : nil
    }

    /// Language shown in the meta grid: an item with stored rich text is
    /// "Rich Text", not the code detector's guess about its plain text.
    private var effectiveLanguage: CodeLanguage? {
        if richData != nil { return nil }
        return codeLanguage != .plainText ? codeLanguage : nil
    }

    @ViewBuilder private var content: some View {
        if item.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                // Load rich text data once per body pass
                let data = richData
                let hasRich = data != nil
                let isHTML = item.richTextRelPath?.hasSuffix(".html") ?? false
                let isCode = codeLanguage != .plainText

                // Always show the Plain/Formatted toggle for text items so you can
                // switch between the two either way. The Edit button opens the
                // inline plain-text editor.
                HStack(spacing: 8) {
                    Picker("", selection: $showRichText) {
                        Text("Plain Text").tag(false)
                        Text("Formatted").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if draftText != nil {
                        if savedRecently {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                        Button("Cancel") { draftText = nil }
                        Button("Save") {
                            if let draft = draftText {
                                state.updateText(item, to: draft)
                            }
                            draftText = nil
                            savedRecently = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                savedRecently = false
                            }
                        }
                        .disabled((draftText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button {
                            draftText = item.text ?? ""
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .keyboardShortcut("e", modifiers: .command)
                        .help("Edit this text (⌘E)")
                    }
                }

                if draftText != nil {
                    editor
                } else {
                Group {
                    if showRichText {
                        if hasRich, let data = data {
                            // Rich formatting is the item's true representation —
                            // it always wins over the code detector's guess about
                            // the plain text (fixes rich items rendering blank).
                            let resolved = RichTextRepresentation.resolve(
                                data: data, isHTML: isHTML, fallbackText: item.text)
                            VStack(alignment: .leading, spacing: 6) {
                                ScrollView {
                                    RichTextRepresentation(attributed: resolved.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                if resolved.usedFallback {
                                    Label("Rich formatting couldn't be displayed — showing plain text.",
                                          systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if isCode {
                            // No rich text stored: code-detected text gets the
                            // code card. It scrolls itself (both axes), so don't
                            // wrap it in another ScrollView — that caused nested
                            // vertical scrollbars and a collapsed one-line view.
                            FormattedCodeView(content: item.text ?? "", language: codeLanguage)
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

    /// Inline plain-text editor shown in place of the tabs' content while
    /// editing. Saving re-hashes the item (dedupes future re-copies) and
    /// refreshes the encrypted search index.
    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: Binding(
                get: { draftText ?? item.text ?? "" },
                set: { draftText = $0 }))
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            Text(item.isRichText
                 ? "Editing the plain text — rich formatting (RTF/HTML) is kept for pasting."
                 : "Edits re-save this item; re-copying the edited text won't create a duplicate.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            if item.kind == .text, let lang = effectiveLanguage {
                GridRow { meta("Language", lang.displayName) }
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
            
            if state.isQueuedForPaste(item) {
                Button {
                    state.toggleQueued(item)
                } label: {
                    Label("Queued \(state.pasteQueueCount)", systemImage: "list.number")
                }
                .buttonStyle(.bordered)
                .help("Remove from paste queue")
            }
            
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
