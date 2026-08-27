import AppKit
import Foundation

/// Lightweight syntax highlighter for the dark code card. Produces an
/// attributed string coloured with a VS Code Dark+–style palette. Designed
/// for clipboard snippets — it favours simple, reliable token patterns over
/// a real parser.
enum SyntaxHighlighter {
    struct Theme {
        let plain: NSColor
        let keyword: NSColor
        let string: NSColor
        let comment: NSColor
        let number: NSColor
        let type: NSColor
        let function: NSColor
    }

    static let dark = Theme(
        plain:    NSColor(calibratedRed: 0.83, green: 0.83, blue: 0.83, alpha: 1), // #D4D4D4
        keyword:  NSColor(calibratedRed: 0.77, green: 0.52, blue: 0.75, alpha: 1), // #C586C0
        string:   NSColor(calibratedRed: 0.81, green: 0.57, blue: 0.47, alpha: 1), // #CE9178
        comment:  NSColor(calibratedRed: 0.42, green: 0.60, blue: 0.33, alpha: 1), // #6A9955
        number:   NSColor(calibratedRed: 0.71, green: 0.81, blue: 0.66, alpha: 1), // #B5CEA8
        type:     NSColor(calibratedRed: 0.31, green: 0.71, blue: 0.69, alpha: 1), // #4EC9B0
        function: NSColor(calibratedRed: 0.86, green: 0.86, blue: 0.67, alpha: 1)  // #DCDCAA
    )

    static func keywords(for language: String?) -> Set<String> {
        switch language?.lowercased() {
        case "ts", "typescript", "javascript", "js", "jsx", "tsx":
            return ["const", "let", "var", "function", "return", "if", "else", "for",
                    "while", "import", "export", "from", "default", "class", "interface",
                    "type", "extends", "implements", "new", "this", "async", "await",
                    "try", "catch", "finally", "throw", "yield", "static", "get", "set",
                    "public", "private", "protected", "switch", "case", "break", "continue",
                    "do", "of", "in", "void", "null", "undefined", "true", "false",
                    "typeof", "instanceof", "delete", "super", "as", "readonly", "enum",
                    "namespace", "declare", "abstract", "constructor"]
        case "swift":
            return ["func", "let", "var", "class", "struct", "enum", "protocol",
                    "extension", "import", "return", "if", "else", "for", "while",
                    "guard", "switch", "case", "default", "break", "continue", "where",
                    "in", "as", "is", "try", "catch", "throw", "defer", "init", "deinit",
                    "self", "static", "public", "private", "internal", "fileprivate",
                    "open", "override", "final", "lazy", "weak", "unowned", "optional",
                    "nil", "true", "false", "some", "any", "async", "await", "actor",
                    "typealias", "associatedtype", "mutating", "nonmutating", "didSet",
                    "willSet", "subscript", "throws", "rethrows"]
        case "python":
            return ["def", "class", "return", "if", "elif", "else", "for", "while",
                    "import", "from", "as", "try", "except", "finally", "raise", "with",
                    "lambda", "yield", "global", "nonlocal", "pass", "break", "continue",
                    "in", "is", "not", "and", "or", "None", "True", "False", "async",
                    "await", "self", "del", "assert"]
        case "go", "golang":
            return ["func", "package", "import", "return", "if", "else", "for", "range",
                    "switch", "case", "default", "break", "continue", "go", "defer",
                    "chan", "map", "struct", "interface", "type", "var", "const", "nil",
                    "true", "false", "select", "fallthrough", "goto"]
        case "rust":
            return ["fn", "let", "mut", "pub", "use", "mod", "struct", "enum", "impl",
                    "trait", "match", "if", "else", "for", "while", "loop", "return",
                    "move", "ref", "where", "in", "as", "crate", "self", "Self", "super",
                    "unsafe", "async", "await", "dyn", "type", "const", "static",
                    "true", "false", "break", "continue"]
        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                    "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "JOIN", "LEFT",
                    "RIGHT", "INNER", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING",
                    "LIMIT", "OFFSET", "AND", "OR", "NOT", "NULL", "IN", "IS", "LIKE",
                    "INDEX", "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DISTINCT"]
        case "cpp", "c", "c++":
            return ["#include", "#define", "if", "else", "for", "while", "return",
                    "class", "struct", "enum", "namespace", "using", "typedef", "const",
                    "static", "void", "int", "char", "bool", "float", "double", "long",
                    "short", "unsigned", "signed", "new", "delete", "public", "private",
                    "protected", "virtual", "override", "template", "typename", "this",
                    "nullptr", "true", "false", "try", "catch", "throw", "switch",
                    "case", "default", "break", "continue", "auto", "extern", "sizeof"]
        case "java":
            return ["class", "interface", "public", "private", "protected", "static",
                    "void", "new", "return", "if", "else", "for", "while", "try", "catch",
                    "finally", "throw", "throws", "import", "package", "extends",
                    "implements", "final", "this", "super", "abstract", "null", "true",
                    "false", "switch", "case", "default", "break", "continue", "int",
                    "long", "double", "float", "boolean", "char", "byte", "short"]
        case "bash", "sh", "zsh", "shell":
            return ["echo", "if", "then", "else", "elif", "fi", "for", "while", "do",
                    "done", "case", "esac", "function", "return", "exit", "export",
                    "local", "read", "source", "cd", "sudo", "mkdir", "rm", "cp", "mv",
                    "grep", "cat", "true", "false"]
        default:
            guard let l = language?.lowercased(), !l.isEmpty else { return [] }
            return ["import", "function", "return", "if", "else", "for", "while",
                    "class", "struct", "enum", "var", "let", "const", "new", "static",
                    "public", "private", "default", "try", "catch", "switch", "case",
                    "break", "continue", "true", "false", "nil", "null", "self", "this"]
        }
    }

    private static func usesHashComment(_ language: String?) -> Bool {
        switch language?.lowercased() {
        case "python", "bash", "sh", "zsh", "shell", "ruby", "yaml", "toml": return true
        default: return false
        }
    }

    /// Highlights `code` and returns the result as a single attributed string
    /// (multi-line constructs such as block comments are handled correctly).
    static func highlight(_ code: String, language: String?) -> NSAttributedString {
        let theme = dark
        let out = NSMutableAttributedString(string: code)
        let full = NSRange(0..<(code as NSString).length)
        out.addAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: theme.plain
        ], range: full)

        let kw = keywords(for: language)
        guard !code.isEmpty, !kw.isEmpty else { return out }
        let kwAlt = kw.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")

        var parts: [(pattern: String, color: NSColor)] = []
        parts.append(("\\/\\*[\\s\\S]*?\\*\\/", theme.comment)) // block comment
        parts.append(("//[^\\n]*", theme.comment))               // line comment
        if usesHashComment(language) { parts.append(("#[^\\n]*", theme.comment)) }
        parts.append(("\"(?:\\\\.|[^\"\\\\])*\"", theme.string)) // double-quoted string
        parts.append(("'(?:\\\\.|[^'\\\\])*'", theme.string))    // single-quoted string
        if !kwAlt.isEmpty { parts.append(("\\b(?:\(kwAlt))\\b", theme.keyword)) }
        parts.append(("\\b\\d[\\d_]*(?:\\.\\d+)?\\b", theme.number))
        parts.append(("[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", theme.function)) // foo(
        parts.append(("\\b[A-Z][A-Za-z0-9_]*\\b", theme.type))              // Capitalised

        let pattern = parts.map { "(\($0.pattern))" }.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return out }

        re.enumerateMatches(in: code, options: [], range: full) { match, _, _ in
            guard let match else { return }
            for idx in 1...parts.count where match.range(at: idx).location != NSNotFound {
                out.addAttribute(.foregroundColor, value: parts[idx - 1].color, range: match.range)
                break
            }
        }
        return out
    }

    /// Splits the highlighted string into per-line attributed strings so a view
    /// can render a numbered gutter that aligns exactly with each line.
    static func highlightedLines(_ code: String, language: String?) -> [NSAttributedString] {
        let highlighted = highlight(code, language: language)
        let src = highlighted.string as NSString
        guard src.length > 0 else { return [] }
        var lines: [NSAttributedString] = []
        var start = 0
        while start < src.length {
            let idx = src.range(of: "\n", options: [],
                                range: NSRange(location: start, length: src.length - start))
            if idx.location == NSNotFound {
                lines.append(highlighted.attributedSubstring(from: NSRange(location: start, length: src.length - start)))
                break
            }
            lines.append(highlighted.attributedSubstring(from: NSRange(location: start, length: idx.location - start)))
            start = idx.location + 1
        }
        return lines
    }
}
