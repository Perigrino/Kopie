import SwiftUI
import AppKit

/// Renders rich text (RTF or HTML) as formatted text using native SwiftUI
/// `Text`, which paints correctly everywhere — including inside SwiftUI
/// `ScrollView`s, where an `NSTextView`-backed `NSViewRepresentable` fails to
/// lay out and renders blank (the cause of rich items appearing empty on the
/// Formatted tab).
///
/// Parsing happens up front in `resolve(data:isHTML:fallbackText:)` so callers
/// know whether the rich formatting could actually be displayed.
struct RichTextRepresentation: View {
    let attributed: NSAttributedString
    /// True when rendering on an always-dark card: text/link colors are
    /// remapped to light values so content stays readable in light
    /// appearance (the parser normalizes to `labelColor`, which is black).
    let onDark: Bool

    init(attributed: NSAttributedString, onDark: Bool = false) {
        self.attributed = attributed
        self.onDark = onDark
    }

    /// Outcome of resolving stored rich-text data for display. Checked
    /// sendable: the attributed string is fully built (and never mutated)
    /// before it crosses back to the main actor.
    struct Resolved: @unchecked Sendable {
        let text: NSAttributedString
        /// True when the rich formatting (RTF/HTML) could not be parsed and a
        /// plain-text fallback is shown instead.
        let usedFallback: Bool
    }

    /// Parses RTF/HTML clipboard data into an attributed string that is always
    /// safe to display (never empty when the item has text). Fallback chain:
    /// primary format → other format → the item's plain text → UTF-8 decode of
    /// the data. A parse that succeeds but yields only whitespace (some HTML
    /// payloads style-parse to nothing) counts as a failure.
    ///
    /// `nonisolated`: the HTML path blocks on the nsattributedstringagent/
    /// WebKit XPC round-trip and must run OFF the main thread (calling it on
    /// the main thread from view code hangs the app — see AppState.loadRich).
    nonisolated static func resolve(data: Data, isHTML: Bool, fallbackText: String?) -> Resolved {
        var attributed: NSAttributedString?
        if isHTML {
            attributed = NSAttributedString(html: data, documentAttributes: nil)
        } else {
            attributed = NSAttributedString(rtf: data, documentAttributes: nil)
        }
        // Try the other format if the primary one failed.
        if attributed == nil && !isHTML {
            attributed = NSAttributedString(html: data, documentAttributes: nil)
        }
        if attributed == nil && isHTML {
            attributed = NSAttributedString(rtf: data, documentAttributes: nil)
        }

        func isBlank(_ s: NSAttributedString?) -> Bool {
            guard let s else { return true }
            return s.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if let rich = attributed, !isBlank(rich) {
            return Resolved(text: normalized(rich), usedFallback: false)
        }

        // Rich formatting could not be displayed — fall back to plain text so
        // the Formatted tab is never blank.
        if let plain = fallbackText?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return Resolved(text: NSAttributedString(string: fallbackText!), usedFallback: true)
        }
        if let decoded = String(data: data, encoding: .utf8),
           !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Resolved(text: NSAttributedString(string: decoded), usedFallback: true)
        }
        // Truly nothing renderable (empty copy) — keep whatever we parsed.
        return Resolved(text: attributed ?? NSAttributedString(string: ""), usedFallback: true)
    }

    var body: some View {
        // AppKit-scoped attributes (fonts, colors, underline, links) are
        // understood by SwiftUI Text on macOS.
        let shown = onDark
            ? Self.paint(attributed,
                         text: NSColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1),
                         link: NSColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1))
            : attributed
        Text(AttributedString(shown))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    /// Strips hard-coded colors from copied rich text so it stays readable on
    /// the given background. HTML/RTF from other apps often carries explicit
    /// colors (e.g. white text from a dark-mode chat, black text from a web
    /// page) that become invisible against our background. Structure (bold,
    /// italic, lists, headings) is preserved; links are re-styled.
    nonisolated private static func paint(_ source: NSAttributedString,
                                          text: NSColor, link: NSColor) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: source)
        let full = NSRange(0..<m.length)
        m.removeAttribute(.foregroundColor, range: full)
        m.removeAttribute(.backgroundColor, range: full)
        m.addAttribute(.foregroundColor, value: text, range: full)
        m.enumerateAttribute(.link, in: full) { value, range, _ in
            if value != nil {
                m.addAttribute(.foregroundColor, value: link, range: range)
                m.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        return m
    }

    /// Default (light/appearance-adaptive) painting used by the parser.
    nonisolated static func normalized(_ source: NSAttributedString) -> NSAttributedString {
        paint(source, text: NSColor.labelColor, link: NSColor.linkColor)
    }
}
