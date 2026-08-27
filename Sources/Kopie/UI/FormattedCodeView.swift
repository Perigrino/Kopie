import SwiftUI
import AppKit
import KopieCore

/// A universal formatted viewer. Detects the content's language, safely formats
/// it when possible, applies syntax highlighting, and renders it in a compact
/// developer-card: language badge + line count + copy button in a fixed header,
/// and line-numbered, non-wrapping, both-axis scrolling code below.
struct FormattedCodeView: View {
    let content: String
    let language: CodeLanguage

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var copyResetTask: Task<Void, Never>?

    private var formatted: String { CodeFormatter.format(content, language: language) }
    private var theme: SyntaxHighlighter.Theme { colorScheme == .dark ? SyntaxHighlighter.dark : SyntaxHighlighter.light }
    private var lines: [NSAttributedString] { SyntaxHighlighter.highlightedLines(formatted, language: language, theme: theme) }
    private var lineCount: Int { max(formatted.split(separator: "\n", omittingEmptySubsequences: false).count, 1) }

    /// Adaptive card surface that reads well in both light and dark mode.
    private var surfaceColor: Color { colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .controlBackgroundColor) }
    private var fg: Color { colorScheme == .dark ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(fg.opacity(0.12))
            codeArea
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(surfaceColor))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(fg.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .background(Capsule().fill(fg.opacity(0.12)))
                Text(language.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
            }

            Spacer()

            Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(fg)

            Button {
                copy()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(fg.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Copy content")
            .animation(.easeInOut(duration: 0.15), value: copied)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Code

    private var codeArea: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Line-number gutter
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(1...lineCount, id: \.self) { n in
                        Text("\(n)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(fg.opacity(0.45))
                            .frame(width: 30, alignment: .trailing)
                            .padding(.vertical, 1)
                    }
                }
                .padding(.horizontal, 8)
                .background(fg.opacity(0.06))

                // Code
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(AttributedString(line))
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                            .padding(.vertical, 1)
                    }
                }
                .padding(.horizontal, 12)
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
