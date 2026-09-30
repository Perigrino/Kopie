import AppKit
import Foundation

/// Tokenizing syntax highlighter. Produces an attributed string coloured for a
/// given `CodeLanguage` and a light/dark theme. Deliberately simple: it favours
/// reliable, cheap token patterns over a real parser, which is fine for
/// clipboard-sized snippets and large responses.
public enum SyntaxHighlighter {

    /// Immutable color set for one appearance; `Sendable` so the shared
    /// `dark`/`light` themes can be public statics.
    public struct Theme: Sendable {
        public let plain: NSColor
        public let keyword: NSColor
        public let string: NSColor
        public let number: NSColor
        public let comment: NSColor
        public let type: NSColor
        public let function: NSColor
        public let key: NSColor
    }

    public static let dark = Theme(
        plain:    NSColor(calibratedRed: 0.83, green: 0.83, blue: 0.83, alpha: 1), // #D4D4D4
        keyword:  NSColor(calibratedRed: 0.77, green: 0.52, blue: 0.75, alpha: 1), // #C586C0
        string:   NSColor(calibratedRed: 0.81, green: 0.57, blue: 0.47, alpha: 1), // #CE9178
        number:   NSColor(calibratedRed: 0.71, green: 0.81, blue: 0.66, alpha: 1), // #B5CEA8
        comment:  NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.33, alpha: 1), // #6A9955
        type:     NSColor(calibratedRed: 0.31, green: 0.71, blue: 0.69, alpha: 1), // #4EC9B0
        function: NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.67, alpha: 1), // #DCDCAA
        key:      NSColor(calibratedRed: 0.55, green: 0.76, blue: 0.85, alpha: 1)  // #8CD4E0
    )

    public static let light = Theme(
        plain:    NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.26, alpha: 1), // #383A42
        keyword:  NSColor(calibratedRed: 0.65, green: 0.15, blue: 0.64, alpha: 1), // #A626A4
        string:   NSColor(calibratedRed: 0.31, green: 0.60, blue: 0.31, alpha: 1), // #50A14F
        number:   NSColor(calibratedRed: 0.60, green: 0.41, blue: 0.01, alpha: 1), // #986801
        comment:  NSColor(calibratedRed: 0.63, green: 0.63, blue: 0.67, alpha: 1), // #A0A1A7
        type:     NSColor(calibratedRed: 0.00, green: 0.52, blue: 0.74, alpha: 1), // #0184BC
        function: NSColor(calibratedRed: 0.25, green: 0.47, blue: 0.94, alpha: 1), // #4078F2
        key:      NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.64, alpha: 1)  // #0D6AA3
    )

    // MARK: - Public

    /// Tokenizes `text` for `language`, colouring each match.
    ///
    /// Every token pattern in `tokens(for:theme:)` MUST contribute exactly one
    /// capture group: the parts are concatenated into a single alternation and
    /// the match's group index is mapped back to the owning part by position
    /// (`parts[idx - 1]`). A pattern with an extra group shifts that mapping and
    /// silently mis-colours every later token kind, so `assertTokenGroups` fails
    /// the build instead. Use non-capturing `(?:…)` for any inner group.
    public static func highlight(_ text: String, language: CodeLanguage, theme: Theme) -> NSAttributedString {
        let out = NSMutableAttributedString(string: text)
        let full = NSRange(0..<(text as NSString).length)
        out.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: theme.plain
        ], range: full)

        let parts = tokens(for: language, theme: theme)
        guard !parts.isEmpty, !text.isEmpty else { return out }
        assertTokenGroups(parts, language: language)
        let pattern = parts.map { "(\($0.pattern))" }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return out }

        re.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match else { return }
            for idx in 1...parts.count where match.range(at: idx).location != NSNotFound {
                out.addAttribute(.foregroundColor, value: parts[idx - 1].color, range: match.range)
                break
            }
        }
        return out
    }

    /// Precondition for `highlight`'s positional group mapping: exactly one
    /// capture group per token part, in the same order as `parts`.
    private static func assertTokenGroups(
        _ parts: [(pattern: String, color: NSColor)], language: CodeLanguage
    ) {
        for part in parts {
            let count = (try? NSRegularExpression(pattern: part.pattern).numberOfCaptureGroups) ?? 0
            precondition(count == 0,
                         "\(language.rawValue) token pattern contributes \(count) capture groups; "
                         + "each part must add exactly one — use (?:…) for inner groups")
        }
    }

    /// The raw token patterns for `language`, for tests that assert the
    /// one-capture-group-per-part invariant `highlight` relies on.
    public static func tokenPatternsForTesting(language: CodeLanguage) -> [(pattern: String, color: NSColor)] {
        tokens(for: language, theme: dark)
    }

    /// Splits a highlighted string into per-line attributed strings so a view can
    /// render a numbered gutter aligned exactly with each line.
    public static func highlightedLines(_ text: String, language: CodeLanguage, theme: Theme) -> [NSAttributedString] {
        let highlighted = highlight(text, language: language, theme: theme)
        let src = highlighted.string as NSString
        guard src.length > 0 else { return [] }
        var lines: [NSAttributedString] = []
        var start = 0
        while start < src.length {
            let idx = src.range(of: "\n", options: [], range: NSRange(location: start, length: src.length - start))
            if idx.location == NSNotFound {
                lines.append(highlighted.attributedSubstring(from: NSRange(location: start, length: src.length - start)))
                break
            }
            lines.append(highlighted.attributedSubstring(from: NSRange(location: start, length: idx.location - start)))
            start = idx.location + 1
        }
        return lines
    }

    // MARK: - Token rules

    private static func tokens(for language: CodeLanguage, theme: Theme) -> [(pattern: String, color: NSColor)] {
        var p: [(String, NSColor)] = []

        switch language {
        case .json:
            p.append(("\"(?:\\\\.|[^\"\\\\])*\"(?=\\s*:)", theme.key))
            p.append(("\"(?:\\\\.|[^\"\\\\])*\"", theme.string))
            p.append(("-?\\b\\d(?:[\\d.]|e[+-]?\\d+)*\\b", theme.number))
            p.append(("\\b(?:true|false|null)\\b", theme.keyword))
        case .html, .xml:
            if language == .xml { p.append(("<\\?xml[^>]*\\?>", theme.comment)) }
            p.append(("<!--[\\s\\S]*?-->", theme.comment))
            p.append(("</?[a-zA-Z][^<>]*?/?>", theme.type))
            p.append(("\"[^\"]*\"", theme.string))
        case .css:
            p.append(("/\\*[\\s\\S]*?\\*/", theme.comment))
            p.append(("@[a-zA-Z-]+", theme.keyword))
            p.append(("\\b[.#]?[a-zA-Z-][\\w-]*\\s*(?=\\{)", theme.type))
            p.append(("[a-zA-Z-]+(?=\\s*:)", theme.function))
            p.append(("\"[^\"]*\"|'[^']*'", theme.string))
            p.append(("\\b\\d+(?:\\.\\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg)?\\b", theme.number))
        case .yaml:
            p.append(("^[\\s-]*[A-Za-z0-9_.\\-/]+(?=\\s*:)", theme.key))
            p.append(("(?:^|\\s)#[^\\n]*", theme.comment))
            p.append(("\"[^\"]*\"|'[^']*'", theme.string))
            p.append(("\\b\\d+(?:\\.\\d+)?\\b", theme.number))
        case .markdown:
            p.append(("^#{1,6}\\s+.*$", theme.type))
            p.append(("\\*\\*[^*]+\\*\\*|__[^_]+__", theme.keyword))
            // Non-capturing inner group: every token pattern must contribute
            // exactly ONE capture group (see `highlight`'s index mapping).
            p.append(("\\[(?:[^\\]]+)\\]\\([^)]*\\)", theme.function))
            p.append(("`[^`]+`", theme.string))
        case .sql:
            p.append(("--[^\\n]*|/\\*[\\s\\S]*?\\*/", theme.comment))
            p.append(("\\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|ALTER|DROP|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|BY|ORDER|HAVING|LIMIT|OFFSET|AND|OR|NOT|NULL|IN|IS|LIKE|INDEX|PRIMARY|KEY|FOREIGN|REFERENCES|DISTINCT|AS|ASC|DESC|UNION|ALL|CASE|WHEN|THEN|ELSE|END)\\b", theme.keyword))
            p.append(("'[^']*'|\"[^\"]*\"", theme.string))
            p.append(("\\b\\d+(?:\\.\\d+)?\\b", theme.number))
        case .plainText:
            break
        case .shell:
            p.append(("#[^\\n]*", theme.comment))
            p.append(("\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'", theme.string))
            p.append(("\\$\\{[^}]*\\}|\\$[A-Za-z_][A-Za-z0-9_]*", theme.key))
            p.append(("\\b\\d+(?:\\.\\d+)?\\b", theme.number))
        default:
            appendCodeTokens(&p, language: language, theme: theme)
        }
        return p
    }

    private static func appendCodeTokens(_ p: inout [(String, NSColor)], language: CodeLanguage, theme: Theme) {
        switch language {
        case .python, .ruby, .shell:
            p.append(("#[^\\n]*", theme.comment))
        case .c, .cpp, .java, .csharp, .swift, .kotlin, .go, .rust:
            p.append(("//[^\\n]*|/\\*[\\s\\S]*?\\*/", theme.comment))
        default:
            p.append(("//[^\\n]*|/\\*[\\s\\S]*?\\*/", theme.comment))
        }

        if language == .python {
            p.append(("(?:[rubf]{0,2})\"(?:\\\\.|[^\"\\\\])*\"|(?:[rubf]{0,2})'(?:\\\\.|[^'\\\\])*'", theme.string))
        } else if language == .rust {
            p.append(("(?:r#*)\"(?:\\\\.|[^\"\\\\])*\"", theme.string))
        } else if language == .go {
            p.append(("`[^`]*`|\"(?:\\\\.|[^\"\\\\])*\"", theme.string))
        } else if language == .csharp {
            p.append(("(?:\\$\"?)\"(?:\\\\.|[^\"\\\\])*\"", theme.string))
        } else if language == .swift {
            p.append(("\"(?:[^\"]|\\\\.)*\"", theme.string))
        } else {
            p.append(("\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'", theme.string))
        }

        let kw = keywords(for: language)
        if !kw.isEmpty {
            let alt = kw.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            p.append(("\\b(?:\(alt))\\b", theme.keyword))
        }
        p.append(("\\b\\d[\\d_]*(?:\\.\\d+)?\\b", theme.number))
        p.append(("[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", theme.function))
        p.append(("\\b[A-Z][A-Za-z0-9_]*\\b", theme.type))
    }

    // MARK: - Keyword sets

    private static func keywords(for language: CodeLanguage) -> Set<String> {
        switch language {
        case .typescript, .javascript:
            return ["const", "let", "var", "function", "return", "if", "else", "for", "while",
                    "import", "export", "from", "default", "class", "interface", "type",
                    "extends", "implements", "new", "this", "async", "await", "try", "catch",
                    "finally", "throw", "yield", "static", "get", "set", "public", "private",
                    "protected", "switch", "case", "break", "continue", "do", "of", "in",
                    "void", "null", "undefined", "true", "false", "typeof", "instanceof",
                    "delete", "super", "as", "readonly", "enum", "namespace", "declare",
                    "abstract", "constructor"]
        case .swift:
            return ["func", "let", "var", "class", "struct", "enum", "protocol", "extension",
                    "import", "return", "if", "else", "for", "while", "guard", "switch",
                    "case", "default", "break", "continue", "where", "in", "as", "is", "try",
                    "catch", "throw", "defer", "init", "deinit", "self", "static", "public",
                    "private", "internal", "fileprivate", "open", "override", "final", "lazy",
                    "weak", "unowned", "optional", "nil", "true", "false", "some", "any",
                    "async", "await", "actor", "typealias", "associatedtype", "mutating",
                    "nonmutating", "didSet", "willSet", "subscript", "throws", "rethrows"]
        case .kotlin:
            return ["fun", "val", "var", "data", "class", "object", "interface", "when", "if",
                    "else", "for", "while", "return", "null", "true", "false", "this", "super",
                    "import", "package", "internal", "private", "public", "protected", "open",
                    "override", "final", "abstract", "sealed", "companion", "init", "constructor"]
        case .python:
            return ["def", "class", "return", "if", "elif", "else", "for", "while", "import",
                    "from", "as", "try", "except", "finally", "raise", "with", "lambda",
                    "yield", "global", "nonlocal", "pass", "break", "continue", "in", "is",
                    "not", "and", "or", "None", "True", "False", "async", "await", "self",
                    "del", "assert"]
        case .go:
            return ["func", "package", "import", "return", "if", "else", "for", "range",
                    "switch", "case", "default", "break", "continue", "go", "defer", "chan",
                    "map", "struct", "interface", "type", "var", "const", "nil", "true",
                    "false", "select", "fallthrough", "goto"]
        case .rust:
            return ["fn", "let", "mut", "pub", "use", "mod", "struct", "enum", "impl", "trait",
                    "match", "if", "else", "for", "while", "loop", "return", "move", "ref",
                    "where", "in", "as", "crate", "self", "Self", "super", "unsafe", "async",
                    "await", "dyn", "type", "const", "static", "true", "false", "break",
                    "continue"]
        case .cpp, .c:
            return ["#include", "#define", "if", "else", "for", "while", "return", "class",
                    "struct", "enum", "namespace", "using", "typedef", "const", "static",
                    "void", "int", "char", "bool", "float", "double", "long", "short",
                    "unsigned", "signed", "new", "delete", "public", "private", "protected",
                    "virtual", "override", "template", "typename", "this", "nullptr", "true",
                    "false", "try", "catch", "throw", "switch", "case", "default", "break",
                    "continue", "auto", "extern", "sizeof"]
        case .java:
            return ["class", "interface", "public", "private", "protected", "static", "void",
                    "new", "return", "if", "else", "for", "while", "try", "catch", "finally",
                    "throw", "throws", "import", "package", "extends", "implements", "final",
                    "this", "super", "abstract", "null", "true", "false", "switch", "case",
                    "default", "break", "continue", "int", "long", "double", "float",
                    "boolean", "char", "byte", "short"]
        case .csharp:
            return ["using", "namespace", "class", "interface", "public", "private",
                    "protected", "internal", "static", "void", "new", "return", "if", "else",
                    "for", "foreach", "while", "try", "catch", "finally", "throw", "async",
                    "await", "var", "readonly", "const", "string", "int", "bool", "object",
                    "null", "true", "false", "switch", "case", "default", "break", "continue",
                    "get", "set", "value", "this", "base", "override", "virtual", "abstract",
                    "sealed", "partial", "enum", "struct"]
        case .ruby:
            return ["def", "end", "class", "module", "return", "if", "elsif", "else", "unless",
                    "for", "while", "until", "do", "begin", "rescue", "ensure", "require",
                    "include", "extend", "puts", "print", "nil", "true", "false", "self",
                    "yield", "case", "when", "break", "next"]
        case .shell:
            return ["echo", "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "function", "return", "exit", "export", "local", "read",
                    "source", "cd", "sudo", "mkdir", "rm", "cp", "mv", "grep", "cat", "true",
                    "false"]
        default:
            return []
        }
    }
}
