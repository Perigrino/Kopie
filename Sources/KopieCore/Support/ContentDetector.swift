import Foundation

/// Detects the type of content for smart paste suggestions (URLs, emails, phone
/// numbers). Code / language detection lives in `CodeLanguageDetector`, so this
/// stays focused and there is a single source of truth for language.
public enum ContentType: Sendable {
    case url
    case email
    case phoneNumber
    case plainText
}

public enum ContentDetector {
    /// Detects the content type of a text string.
    public static func detectContentType(_ text: String) -> ContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .plainText }

        // Check for URL
        if let url = URL(string: trimmed), (url.scheme == "http" || url.scheme == "https") {
            return .url
        }

        // Check for email (simplified RFC 5322)
        let emailPattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        if trimmed.range(of: emailPattern, options: .regularExpression) != nil {
            return .email
        }

        // Check for phone number (common formats)
        let phonePattern = "^[\\+]?[(]?[0-9]{1,4}[)]?[-\\s\\.]?[0-9]{1,4}[-\\s\\.]?[0-9]{1,9}$"
        if trimmed.range(of: phonePattern, options: .regularExpression) != nil {
            return .phoneNumber
        }

        return .plainText
    }
}
