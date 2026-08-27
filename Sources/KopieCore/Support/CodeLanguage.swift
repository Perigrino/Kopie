import Foundation

/// A detected language/format for the universal "Formatted" viewer.
public enum CodeLanguage: String, Sendable, CaseIterable {
    case json, xml, html, css, javascript, typescript, swift, kotlin, java
    case csharp, c, cpp, python, ruby, go, rust, sql, yaml, markdown, shell, plainText

    public var displayName: String {
        switch self {
        case .json: return "JSON"
        case .xml: return "XML"
        case .html: return "HTML"
        case .css: return "CSS"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .swift: return "Swift"
        case .kotlin: return "Kotlin"
        case .java: return "Java"
        case .csharp: return "C#"
        case .c: return "C"
        case .cpp: return "C++"
        case .python: return "Python"
        case .ruby: return "Ruby"
        case .go: return "Go"
        case .rust: return "Rust"
        case .sql: return "SQL"
        case .yaml: return "YAML"
        case .markdown: return "Markdown"
        case .shell: return "Shell"
        case .plainText: return "Plain Text"
        }
    }

    /// Compact header badge glyph (e.g. `{ }` for JSON, `JS`, `TS`).
    public var glyph: String {
        switch self {
        case .json: return "{ }"
        case .xml, .html, .plainText: return "</>"
        case .css: return "#"
        case .javascript: return "JS"
        case .typescript: return "TS"
        case .swift: return "SWIFT"
        case .kotlin: return "KT"
        case .java: return "JAVA"
        case .csharp: return "C#"
        case .c: return "C"
        case .cpp: return "C++"
        case .python: return "PY"
        case .ruby: return "RB"
        case .go: return "GO"
        case .rust: return "RS"
        case .sql: return "SQL"
        case .yaml: return "YAML"
        case .markdown: return "MD"
        case .shell: return "$"
        }
    }
}
