import Foundation

/// Safe, meaning-preserving formatting for structured content. Only formats
/// when it can do so without risk of changing meaning; otherwise returns the
/// original text untouched.
public enum CodeFormatter {

    public static func format(_ content: String, language: CodeLanguage) -> String {
        switch language {
        case .json:
            return prettyJSON(content) ?? content
        default:
            return content
        }
    }

    /// Pretty-prints JSON with indentation. Returns nil (and the caller keeps
    /// the original) if the content is no longer valid JSON — we never rewrite
    /// something we can't round-trip safely.
    private static func prettyJSON(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return nil }
        return String(data: out, encoding: .utf8)
    }
}
