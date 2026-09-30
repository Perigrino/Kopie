import SwiftUI
import AppKit
import KopieCore

/// Fixed always-dark code-card palette (independent of appearance), shared by
/// every card that renders on the near-black surface.
enum CodeCardPalette {
    static let surface = Color(red: 0.118, green: 0.118, blue: 0.125) // ~#1E1E20
    static let fg = Color(red: 0.83, green: 0.83, blue: 0.84)          // ~#D4D4D6
    static let gutter = Color(red: 0.43, green: 0.46, blue: 0.51)      // ~#6E7681
}

/// Always-dark code-block card chrome: near-black surface, hairline border,
/// header row, divider. Reused by `FormattedCodeView` and the rich-text
/// Formatted tab so both read as the same kind of object.
struct DarkCodeCard<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            Divider().overlay(CodeCardPalette.fg.opacity(0.12))
            content
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CodeCardPalette.surface))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CodeCardPalette.fg.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A universal formatted viewer. Detects the content's language, safely formats
/// it when possible, applies syntax highlighting, and renders it as a dark
/// code-block card (GitHub/IDE style): near-black surface, syntax-coloured
/// monospace text and a dim line-number gutter — always dark, in both light
/// and dark appearance, so code always reads like code.
struct FormattedCodeView: View {
    let content: String
    let language: CodeLanguage

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    // Cache highlighted lines so large content isn't re-tokenized on every body
    // pass (hover, layout, the copy animation). Keyed by content + language + mode.
    private static let highlightCache = NSCache<NSString, NSArray>()

    private var formatted: String { CodeFormatter.format(content, language: language) }
    // The code block is always dark (like GitHub's code cards), so highlighting
    // always uses the dark theme regardless of the app's appearance.
    private var theme: SyntaxHighlighter.Theme { SyntaxHighlighter.dark }
    private var lines: [NSAttributedString] {
        let key = "\(formatted)\u{1}\(language.rawValue)" as NSString
        if let cached = Self.highlightCache.object(forKey: key) as? [NSAttributedString] { return cached }
        let computed = SyntaxHighlighter.highlightedLines(formatted, language: language, theme: theme)
        Self.highlightCache.setObject(computed as NSArray, forKey: key)
        return computed
    }
    private var lineCount: Int { max(formatted.split(separator: "\n", omittingEmptySubsequences: false).count, 1) }

    // Fixed dark code-block palette (independent of appearance).
    private var surfaceColor: Color { CodeCardPalette.surface }
    private var fg: Color { CodeCardPalette.fg }
    private var gutterColor: Color { CodeCardPalette.gutter }

    var body: some View {
        DarkCodeCard(header: { header }, content: { codeArea })
            .onDisappear { copyResetTask?.cancel() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(language.glyph)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(fg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                Text(language.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(fg)
            }

            Spacer()

            Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(gutterColor)

            Button {
                copy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.42, green: 0.62, blue: 1.0))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.42, green: 0.62, blue: 1.0).opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Copy content")
            .animation(.easeInOut(duration: 0.15), value: copied)
        }
        // Padding comes from DarkCodeCard's header slot.
    }

    // MARK: - Code

    private var codeArea: some View {
        // Vertical scroll only so text wraps to the panel width (responsive).
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Each logical line is a row: a dim number gutter + the wrapping
                // line. Wrapped continuation lines flow under the number's row.
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(gutterColor)
                            .frame(width: 30, alignment: .trailing)
                            .padding(.trailing, 12)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.03))
                        Text(AttributedString(line))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .padding(.leading, 12)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        copied = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
