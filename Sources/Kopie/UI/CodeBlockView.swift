import SwiftUI
import AppKit

/// A code snippet rendered as a dark editor-style card: a coloured language
/// badge and line-count with a Copy button in the header, and line-numbered,
/// syntax-highlighted monospaced code below.
struct CodeBlockView: View {
    let code: String
    let language: String?

    private var lines: [NSAttributedString] {
        SyntaxHighlighter.highlightedLines(code, language: language)
    }

    private var lineCount: Int { max(code.split(separator: "\n", omittingEmptySubsequences: false).count, 1) }

    private var badgeLabel: String { (language ?? "code").uppercased() }

    private var badgeColor: Color {
        switch language?.lowercased() {
        case "ts", "typescript", "js", "javascript", "jsx", "tsx": return Color(red: 0.19, green: 0.47, blue: 0.78)
        case "swift": return Color(red: 0.93, green: 0.41, blue: 0.32)
        case "python": return Color(red: 0.25, green: 0.54, blue: 0.73)
        case "go", "golang": return Color(red: 0.18, green: 0.72, blue: 0.85)
        case "rust": return Color(red: 0.82, green: 0.45, blue: 0.44)
        case "html", "css": return Color(red: 0.84, green: 0.32, blue: 0.44)
        case "sql": return Color(red: 0.90, green: 0.56, blue: 0.34)
        case "c", "cpp", "c++", "java": return Color(red: 0.50, green: 0.50, blue: 0.57)
        case "bash", "sh", "zsh", "shell": return Color(red: 0.35, green: 0.70, blue: 0.42)
        default: return Color(red: 0.61, green: 0.47, blue: 0.84)
        }
    }

    private let card = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)

    private var onCard: Color { Color(nsColor: card) }
    private var fgPrimary: Color { Color(white: 0.88, opacity: 0.92) }
    private var fgSecondary: Color { Color(white: 0.88, opacity: 0.55) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color(white: 1, opacity: 0.08))
            codeBody
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(onCard))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(fgSecondary.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(badgeColor).frame(width: 7, height: 7)
                Text(badgeLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(fgPrimary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(white: 1, opacity: 0.08)))

            Spacer()

            Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(fgSecondary)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.system(size: 11))
                .foregroundStyle(fgPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(fgSecondary.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var codeBody: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color(white: 1, opacity: 0.32))
                            .frame(width: 26, alignment: .trailing)
                            .padding(.trailing, 12)
                        Text(AttributedString(line))
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                            .padding(.vertical, 1)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
        }
    }
}
