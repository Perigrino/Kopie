import Foundation

/// Detects the language/format of an arbitrary text snippet without relying on
/// a file extension. Falls back to `.plainText` when confidence is low.
public enum CodeLanguageDetector {

    public static func detect(content: String, filename: String? = nil) -> CodeLanguage {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .plainText }

        // Filename is only a hint — never the sole basis.
        if let ext = filename.map({ URL(fileURLWithPath: $0).pathExtension.lowercased() }), !ext.isEmpty {
            if let lang = fromExtension(ext) { return lang }
        }

        if isJSON(text) { return .json }
        if isXMLOrHTML(text) { return text.lowercased().contains("<?xml") && !text.lowercased().contains("<!doctype html") ? .xml : .html }
        if isYAML(text) { return .yaml }

        if text.hasPrefix("#!") { return text.lowercased().contains("python") ? .python : .shell }
        if isSQL(text) { return .sql }
        if isCSS(text) { return .css }
        if isMarkdown(text) { return .markdown }
        if let lang = keywordLanguage(text) { return lang }

        return .plainText
    }

    // MARK: - Extension hints

    private static func fromExtension(_ ext: String) -> CodeLanguage? {
        switch ext {
        case "json": return .json
        case "xml", "plist", "svg": return .xml
        case "html", "htm": return .html
        case "css": return .css
        case "js", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "swift": return .swift
        case "kt", "kts": return .kotlin
        case "java": return .java
        case "cs": return .csharp
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "py": return .python
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "sql": return .sql
        case "yaml", "yml": return .yaml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        default: return nil
        }
    }

    // MARK: - Structured formats

    private static func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return false }
        return obj is [String: Any] || obj is [Any]
    }

    private static func isXMLOrHTML(_ text: String) -> Bool {
        let lower = text.lowercased()
        let opener = lower.contains("<?xml") || lower.contains("<!doctype") || lower.contains("<html")
            || lower.contains("<div") || lower.contains("<body") || lower.contains("<head")
        guard opener else { return false }
        return lower.contains("</") || lower.contains("/>")
    }

    private static func isYAML(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return false }
        // Prose guard: sentences with ending punctuation and few colons are not YAML.
        if text.contains(".") && text.count > 60 && text.filter({ $0 == ":" }).count < 2 { return false }
        let keyPattern = "^[A-Za-z0-9_.\\-/]+:\\s*(.*)$"
        let listPattern = "^-\\s+"
        let matches = lines.filter {
            $0.range(of: keyPattern, options: .regularExpression) != nil
                || $0.range(of: listPattern, options: .regularExpression) != nil
        }.count
        guard matches >= 1 else { return false }
        return Double(matches) / Double(lines.count) >= 0.6 || (matches >= 2 && lines.count <= 4)
    }

    private static func isSQL(_ text: String) -> Bool {
        let upper = text.uppercased()
        let strong = ["SELECT ", "INSERT ", "UPDATE ", "DELETE FROM", "CREATE TABLE",
                      "ALTER TABLE", "DROP TABLE", "GROUP BY", "ORDER BY", " JOIN ", "HAVING "]
        if strong.contains(where: { upper.contains($0) }) { return true }
        let weak = ["WHERE ", "LIMIT ", "FROM ", "SET ", "VALUES "]
        return weak.filter { upper.contains($0) }.count >= 2
    }

    private static func isCSS(_ text: String) -> Bool {
        guard text.contains("{") && text.contains("}") else { return false }
        let hasDecl = text.range(of: "\\s*[a-zA-Z-]+\\s*:\\s*[^;{}]+;", options: .regularExpression) != nil
        guard hasDecl else { return false }
        // Prose guard: a colon-semicolon pair inside braces is a strong CSS signal.
        return true
    }

    private static func isMarkdown(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let heading = lines.contains { $0.hasPrefix("# ") || $0.hasPrefix("## ") || $0.hasPrefix("### ") }
        let bold = text.contains("**") || text.contains("__")
        let list = lines.contains { $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("1. ") }
        if heading && lines.count >= 2 { return true }
        if bold && list { return true }
        return false
    }

    // MARK: - Keyword / syntax based

    private static func keywordLanguage(_ text: String) -> CodeLanguage? {
        let lower = text.lowercased()

        // Most distinctive first. C# signals only — C++ shares `namespace` and
        // `class X : Y`, so those alone must not be claimed as C#.
        if lower.contains("using system") || lower.contains("console.writeline")
            || lower.contains("[apicontroller") || lower.contains("[apicontrollertemplate")
            || (lower.contains("get; set;") && lower.contains("public ")) { return .csharp }

        if lower.contains("import swiftui") || lower.contains("struct ") && text.contains("let ") && text.contains("{")
            || lower.contains("import foundation") { return .swift }

        if lower.contains("fun ") && lower.contains("val ") || lower.contains("data class ") { return .kotlin }

        if lower.contains("package ") && lower.contains("func ") { return .go }

        // Ruby before Python: both use `def`, but Ruby bodies end in `end`.
        if (lower.contains("def ") && (lower.contains("\nend") || lower.contains(" end")))
            || lower.contains("require '") || lower.contains("require \"")
            || lower.contains("class ") && lower.contains(" < ") && text.contains("end")
            || lower.contains("puts ") && text.contains("end") { return .ruby }

        if lower.contains("def ") || lower.contains("__init__") { return .python }

        if lower.contains("fn ") && lower.contains("let mut") || lower.contains("impl ") { return .rust }

        // C vs C++: `std::`, `namespace`, `class`, `template`, `using namespace`
        // are C++-only. Bare `#include` with C primitives (`printf`, `malloc`,
        // `int main`, `typedef struct`) and no `::` is C.
        let isCPP = lower.contains("std::") || lower.contains("namespace") || lower.contains("template <")
            || lower.contains("using namespace") || lower.contains("::")
        if isCPP { return .cpp }
        if lower.contains("#include") {
            if lower.contains("cout") || lower.contains("cin") || lower.contains("string ")
                || lower.contains("vector") || lower.contains("iostream") { return .cpp }
            return .c
        }

        if lower.contains("public class ") || lower.contains("public static void main")
            || lower.contains("import java.") || lower.contains("system.out.println") { return .java }

        if lower.contains("interface ") || lower.contains("type ") && lower.contains("= ")
            || lower.contains("export default") || lower.contains("=>") || lower.contains("await ") { return .typescript }
        if lower.contains("const ") || lower.contains("console.log(") || lower.contains("require(") { return .typescript }

        return nil
    }
}
