import SwiftUI
import KopieCore
import AppKit

struct DetailsPanel: View {
    let item: ClipboardItem
    /// Called after any acknowledgment-worthy action (color copy buttons);
    /// lets the host surface its Copied toast.
    var onCopied: (() -> Void)? = nil
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showRichText = true
    /// Non-nil while the inline plain-text editor is open.
    @State private var draftText: String?
    @State private var savedRecently = false
    /// Result of the last JSON Validate action (nil = valid, else message).
    @State private var jsonValidationMessage: String?
    /// True briefly after a successful Validate (for the green confirmation).
    @State private var jsonValidatedOK = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if item.isSensitive {
                sensitiveBanner
            }
            // Spec eyebrow: `Text · Rich` + a pause icon-btn at the right.
            HStack(spacing: 8) {
                Text(item.typeLabel + (item.isRichText ? "  ·  Rich" : ""))
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textTertiary(for: scheme))
                Spacer(minLength: 8)
                EmberIconButton(systemName: state.isPaused ? "play.circle" : "pause.circle",
                                scheme: scheme,
                                action: { state.isPaused.toggle() },
                                isOn: state.isPaused)
                .help(state.isPaused ? "Resume monitoring" : "Pause monitoring")
            }
            if item.isSensitive && !revealed {
                maskedContentPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let msg = jsonValidationMessage {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if jsonValidatedOK {
                Label("Valid JSON", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            metaGrid
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: item.id) { _ in
            // Switching items discards any unsaved edit — and re-masks
            // sensitive content so a reveal never leaks across items.
            draftText = nil
            savedRecently = false
            revealed = false
            jsonValidationMessage = nil
            jsonValidatedOK = false
            showRichText = defaultFormattedTab
        }
        .onAppear {
            showRichText = defaultFormattedTab
        }
    }

    /// Items open on the Formatted tab only when they have something to show
    /// there (stored rich text or detected code); plain text opens on the
    /// Plain Text tab instead of a "No rich text" dead end.
    private var defaultFormattedTab: Bool {
        item.isRichText || codeLanguage != .plainText
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

    /// The Formatted tab for an item with stored rich text — rich formatting
    /// is the item's true representation and always wins over the code
    /// detector's guess about the plain text (fixes rich items rendering
    /// blank). Kicks the one background parse via `AppState.loadRich` —
    /// never `resolve()` directly here: the WebKit round-trip it makes can
    /// hang the main thread. Shows plain text until the parse lands (the
    /// cache is @Published, so this re-renders when ready). Rendered on the
    /// shared dark code card so it reads like the code tab.
    private func richFormattedView(data: Data, isHTML: Bool) -> some View {
        if state.cachedRich(for: item) == nil {
            state.loadRich(item, data: data, isHTML: isHTML)
        }
        let resolved = state.cachedRich(for: item)
        return DarkCodeCard(header: {
            HStack(spacing: 8) {
                Text("Rich Text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodeCardPalette.fg)
                Spacer()
                if resolved?.usedFallback == true {
                    Label("Plain-text fallback", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(CodeCardPalette.gutter)
                }
            }
        }, content: {
            ScrollView {
                RichTextRepresentation(
                    attributed: resolved?.text
                        ?? NSAttributedString(string: item.text ?? ""),
                    onDark: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        })
    }

    @ViewBuilder private var content: some View {
        if item.kind == .text {
            VStack(alignment: .leading, spacing: 8) {
                // Load rich text data once per body pass
                let data = richData
                let hasRich = data != nil
                let isHTML = item.richTextRelPath?.hasSuffix(".html") ?? false
                let isCode = codeLanguage != .plainText

                // Spec chips: Plain Text / Formatted pills (gradient when
                // live), Edit as a ghost chip. The Edit button opens the
                // inline plain-text editor.
                HStack(spacing: 6) {
                    chipToggle("Plain Text", on: !showRichText) { showRichText = false }
                    chipToggle("Formatted", on: showRichText) { showRichText = true }

                    if draftText != nil {
                        if savedRecently {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.ok(for: scheme))
                        }
                        Spacer(minLength: 0)
                        EmberGhostButton(title: "Cancel") {
                            draftText = nil
                            jsonValidationMessage = nil
                        }
                        EmberPrimaryButton(title: "Save", verticalPadding: 5, horizontalPadding: 12) {
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
                    } else {
                        Button {
                            draftText = item.text ?? ""
                            jsonValidationMessage = nil
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                                Text("Edit").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Theme.textSecondary(for: scheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.chipColor(for: scheme)))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("e", modifiers: .command)
                        .help("Edit this text (⌘E)")
                    }
                }

                // JSON utilities: Pretty / Minify / Validate on code items.
                if codeLanguage == .json, let original = item.text {
                    jsonMenu(originalText: original)
                }

                if draftText != nil {
                    editor
                } else {
                Group {
                    if showRichText {
                        if hasRich, let data = data {
                            richFormattedView(data: data, isHTML: isHTML)
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
                        // Spec .content-box: 13/1.6 text on a softly
                        // contrasting card with a 12pt radius, min-h 150.
                        ScrollView {
                            Text(item.text ?? "")
                                .font(.system(size: 13))
                                .lineSpacing(6)
                                .foregroundStyle(Theme.textSecondary(for: scheme))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                                .padding(14)
                                .background {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.contentBackground(for: scheme))
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        FileDetailRow(path: path)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if item.kind == .image {
            DetailsImage(item: item)
        } else if let color = item.kind == .text ? ColorParser.parse(item.text ?? "") : nil {
            colorSwatch(color)
        } else {
            EmptyStateView(symbol: "photo", title: "Image unavailable", message: "The image file could not be loaded.")
        }
    }

    /// Full-resolution image preview for an image item: the thumbnail (or a
    /// loading spinner) paints first, the full image swaps in when loaded.
    private struct DetailsImage: View {
        @EnvironmentObject var state: AppState
        let item: ClipboardItem
        @State private var full: NSImage?

        var body: some View {
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if let full {
                        Image(nsImage: full).resizable()
                    } else if let thumb = state.thumbnail(for: item) {
                        Image(nsImage: thumb).resizable()
                    } else {
                        EmberSkeleton(cornerRadius: 12)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .task(id: item.id) {
                full = nil
                // Deferred one runloop tick so the placeholder paints first.
                await Task.yield()
                full = state.fullImage(for: item)
            }
        }
    }

    /// One file path in a file item's list — image files show a live preview,
    /// everything else the path with a doc icon.
    private struct FileDetailRow: View {
        let path: String
        @State private var image: NSImage?

        private static let imageExtensions: Set<String> =
            ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "bmp", "webp"]

        private var isImageFile: Bool {
            Self.imageExtensions.contains((path as NSString).pathExtension.lowercased())
        }

        var body: some View {
            HStack(spacing: 8) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: isImageFile ? "photo" : "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 32)
                }
                Text(path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .task(id: path) {
                guard isImageFile, image == nil else { return }
                // Small file read; deferring to .task keeps it out of body
                // evaluation so the row paints its icon first.
                image = NSImage(contentsOfFile: path)
            }
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

    /// Large swatch with copy actions for color-literal items (plus the
    /// original text for reference).
    private func colorSwatch(_ color: KopieCore.ColorParser.ColorValue) -> some View {
        let nsColor = NSColor(calibratedRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        return VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: nsColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                .frame(height: 96)
            HStack(spacing: 8) {
                Button("Copy HEX") {
                    state.copyTextToClipboard(color.hexString)
                    onCopied?()
                }
                Button("Copy RGB") {
                    state.copyTextToClipboard(color.rgbString)
                    onCopied?()
                }
                Button("Copy HSL") {
                    state.copyTextToClipboard(color.hslString)
                    onCopied?()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { Text("HEX").foregroundStyle(.secondary); Text("#\(color.hexString)").textSelection(.enabled) }
                GridRow { Text("RGB").foregroundStyle(.secondary); Text(color.rgbString).textSelection(.enabled) }
                GridRow { Text("HSL").foregroundStyle(.secondary); Text(color.hslString).textSelection(.enabled) }
            }
            .font(.caption)
        }
    }

    /// Stands in for the real content while a sensitive item is masked.
    private var maskedContentPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Content hidden")
                .font(.callout.weight(.medium))
            Text("Reveal above to view, edit, or copy this content.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Spec `.chip` toggle — gradient fill when live.
    private func chipToggle(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color.white : Theme.textSecondary(for: scheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.chipColor(for: scheme))))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: on)
    }

    /// Pretty/Minify write back through `state.updateText` (re-hashes so
    /// re-copying the formatted text dedupes); Validate reports inline.
    private func jsonMenu(originalText: String) -> some View {
        Menu {
            Button("Pretty Print") {
                if let out = try? JSONUtilities.format(originalText, as: .twoSpace) {
                    state.updateText(item, to: out)
                }
            }
            Button("Minify") {
                if let out = try? JSONUtilities.format(originalText, as: .minified) {
                    state.updateText(item, to: out)
                }
            }
            Divider()
            Button("Validate") {
                if let msg = JSONUtilities.validate(originalText) {
                    jsonValidationMessage = msg
                    jsonValidatedOK = false
                } else {
                    jsonValidationMessage = nil
                    jsonValidatedOK = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        jsonValidatedOK = false
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "curlybraces").font(.system(size: 11, weight: .medium))
                Text("JSON").font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).padding(.leading, 1)
            }
            .foregroundStyle(Theme.textSecondary(for: scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.chipColor(for: scheme)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Pretty-print, minify, or validate this JSON")
    }
    /// Content stays masked until the user clicks — deliberate friction.
    @State private var revealed = false

    private var sensitiveBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Theme.warn(for: scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sensitive content")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary(for: scheme))
                    Text("Detected as \(item.sensitiveKindLabel ?? "a possible secret") — masked until you reveal it.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary(for: scheme))
                }
                Spacer()
                Button(revealed ? "Hide" : "Reveal") { revealed.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn(for: scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
        .background(Theme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func meta(_ label: String, _ value: String) -> some View {
        Group {
            Text(label).foregroundStyle(Theme.textTertiary(for: scheme))
            Text(value).foregroundStyle(Theme.textSecondary(for: scheme)).monospacedDigit()
        }
        .font(.system(size: 11))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                state.copyBack(item)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold))
                    Text("Copy").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.gradient))
                .shadow(color: Theme.accent.opacity(scheme == .dark ? 0.35 : 0.28), radius: 9, y: 3)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("c", modifiers: .command)
            .help("Copy to clipboard (⌘C)")

            Rectangle().fill(Theme.hairline(for: scheme)).frame(width: 1, height: 22)

            EmberIconButton(systemName: item.isFavorite ? "star.fill" : "star",
                            scheme: scheme,
                            action: { state.toggleFavorite(item) },
                            isOn: item.isFavorite,
                            star: true)
            .help(item.isFavorite ? "Remove from favorites" : "Add to favorites")

            EmberIconButton(systemName: item.isPinned ? "pin.fill" : "pin",
                            scheme: scheme,
                            action: { state.togglePin(item) },
                            isOn: item.isPinned)
            .help(item.isPinned ? "Unpin item" : "Pin to top")

            Spacer()

            if state.isQueuedForPaste(item) {
                Button {
                    state.toggleQueued(item)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "list.number").font(.system(size: 11, weight: .medium))
                        Text("Queued \(state.pasteQueueCount)").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary(for: scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.chipColor(for: scheme)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Remove from paste queue")
            }

            EmberIconButton(systemName: "trash",
                            scheme: scheme,
                            action: { state.remove(item) })
            .help("Delete item")
        }
        .padding(.top, 4)
    }
}
