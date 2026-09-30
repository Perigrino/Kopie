import XCTest
import KopieCore

/// Regression coverage for the Formatted viewer's syntax highlighting.
///
/// `SyntaxHighlighter` concatenates its token patterns into one alternation and
/// maps the matched capture-group index back to a token kind by position. That
/// mapping silently breaks whenever a pattern contributes more than one capture
/// group: every later token kind then gets the wrong color, so markdown code
/// spans, headings and italics all rendered as plain text.
final class SyntaxHighlighterTests: XCTestCase {

    /// Colors the first character of `needle` as the renderer would see it.
    private func colorHex(of text: String, language: CodeLanguage, needle: String) -> String? {
        let ns = text as NSString
        let range = ns.range(of: needle)
        guard range.location != NSNotFound else { return nil }
        let out = SyntaxHighlighter.highlight(text, language: language, theme: SyntaxHighlighter.dark)
        var hex: String?
        out.enumerateAttribute(.foregroundColor, in: NSRange(location: range.location, length: 1)) { value, _, _ in
            guard let c = value as? NSColor else { return }
            hex = c.hexString
        }
        return hex
    }

    /// The color covering the whole `needle` span, or nil if the span isn't
    /// uniformly colored (i.e. it didn't tokenize as a single kind).
    private func uniformColorHex(of text: String, language: CodeLanguage, needle: String) -> String? {
        let ns = text as NSString
        let range = ns.range(of: needle)
        guard range.location != NSNotFound else { return nil }
        let out = SyntaxHighlighter.highlight(text, language: language, theme: SyntaxHighlighter.dark)
        var hexes = Set<String>()
        out.enumerateAttribute(.foregroundColor, in: range) { value, _, _ in
            guard let c = value as? NSColor else { return }
            hexes.insert(c.hexString)
        }
        return hexes.count == 1 ? hexes.first : nil
    }

    private func distinctColors(in text: String, language: CodeLanguage) -> Set<String> {
        let out = SyntaxHighlighter.highlight(text, language: language, theme: SyntaxHighlighter.dark)
        var seen = Set<String>()
        out.enumerateAttribute(.foregroundColor, in: NSRange(0..<out.length)) { value, _, _ in
            guard let c = value as? NSColor else { return }
            seen.insert(c.hexString)
        }
        return seen
    }

    /// Every token pattern must add exactly one capture group, because the
    /// combined alternation is mapped back to token kinds positionally.
    func test_everyTokenPatternAddsExactlyOneCaptureGroup() throws {
        for language in CodeLanguage.allCases {
            let parts = SyntaxHighlighter.tokenPatternsForTesting(language: language)
            for part in parts {
                let count = try NSRegularExpression(pattern: part.pattern).numberOfCaptureGroups
                XCTAssertEqual(count, 0,
                               "\(language.rawValue) pattern '\(part.pattern)' has \(count) inner "
                               + "capture groups; the combined regex maps group index -> token kind, "
                               + "so inner groups must be non-capturing (?:…)")
            }
        }
    }

    /// A markdown line must light up more than the three colors it produced when
    /// the link pattern's inner group shadowed the inline-code token.
    func test_markdown_tokenKindsGetDistinctColors() throws {
        // Realistic markdown: a heading must start its own line, so each token
        // kind is probed on a line where that kind actually applies.
        let bold = "**bold** and `code` and [link](http://x)"
        let heading = "# Heading with `code`"

        let plain = SyntaxHighlighter.dark.plain.hexString

        // Probed over the whole span: a heading must not start with the space
        // that belongs to the previous token.
        let codeSpan = try XCTUnwrap(uniformColorHex(of: bold, language: .markdown, needle: "`code`"))
        XCTAssertNotEqual(codeSpan, plain,
                          "inline code rendered as plain text — its token was shadowed by a "
                          + "neighbouring pattern's capture group")

        let boldColor = try XCTUnwrap(uniformColorHex(of: bold, language: .markdown, needle: "**bold**"))
        XCTAssertNotEqual(boldColor, plain, "bold rendered as plain text")

        let link = try XCTUnwrap(uniformColorHex(of: bold, language: .markdown, needle: "[link](http://x)"))
        XCTAssertNotEqual(link, plain, "markdown link rendered as plain text")

        let headingColor = try XCTUnwrap(uniformColorHex(of: heading, language: .markdown, needle: "# Heading with `code`"))
        XCTAssertNotEqual(headingColor, plain, "heading rendered as plain text")

        // Distinct token kinds must be visually distinct from each other.
        XCTAssertNotEqual(headingColor, boldColor, "heading and bold share a color")
        XCTAssertNotEqual(codeSpan, boldColor, "inline code and bold share a color")
    }

    /// The languages called out in the README viewer should each produce a
    /// genuinely multi-colored result, not a near-flat block of one color.
    func test_codeLanguagesProduceMultipleColors() throws {
        let samples: [(CodeLanguage, String)] = [
            (.json, #"{"name":"Kopie","version":2,"private":true,"tags":["mac"]}"#),
            (.swift, "import SwiftUI\nlet count: Int = 42\nfunc run() -> String { return \"x\" }"),
            (.sql, "-- c\nSELECT id, name FROM users WHERE age > 21;"),
            (.html, "<!-- c --><div class=\"main\">Text</div>"),
            (.css, "/* c */ .main { color: #fff; margin: 10px; }"),
            (.python, "# c\nimport os\ndef greet(name, count=3):\n    return name * count"),
            (.yaml, "# c\nname: Kopie\nport: 8080"),
        ]
        for (language, sample) in samples {
            let colors = distinctColors(in: sample, language: language)
            XCTAssertGreaterThanOrEqual(colors.count, 3,
                                        "\(language.rawValue) rendered with only \(colors.count) color(s): "
                                        + "a code editor look needs the token kinds distinguished")
        }
    }
}

private extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "?" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
