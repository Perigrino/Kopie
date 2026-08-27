import Foundation

/// Detects the type of content in a text string for smart paste suggestions.
public enum ContentType: Sendable {
    case url
    case email
    case phoneNumber
    case code
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
        
        // Check for code (heuristic: contains common code patterns)
        let codePatterns = [
            "^import\\s+",           // import statements
            "^func\\s+",             // function declarations
            "^class\\s+",            // class declarations
            "^struct\\s+",           // struct declarations
            "^enum\\s+",             // enum declarations
            "^let\\s+.*=\\s*",       // let bindings
            "^var\\s+.*=\\s*",       // var bindings
            "^return\\s+",           // return statements
            "^if\\s+.*\\{",          // if statements with braces
            "^for\\s+.*\\{",         // for loops with braces
            "^while\\s+.*\\{",       // while loops with braces
            "^switch\\s+",           // switch statements
            "^case\\s+",             // case statements
            "^=>\\s*",               // arrow functions
            "^\\{\\s*$",             // opening brace
            "^\\}\\s*$",             // closing brace
            "^\\s*//.*$",            // single line comments
            "^\\s*/\\*.*\\*/\\s*$",  // block comments
            "^public\\s+",           // access modifiers
            "^private\\s+",
            "^internal\\s+",
            "^fileprivate\\s+",
            "^open\\s+",
            "^static\\s+",
            "^override\\s+",
            "^func\\s*\\(",          // function calls
            "^self\\.",              // self references
            "^nil\\s*$",             // nil literal
            "^true\\s*$",            // boolean literals
            "^false\\s*$",
        ]
        
        let lines = trimmed.components(separatedBy: .newlines)
        let codeLineCount = lines.filter { line in
            codePatterns.contains { pattern in
                line.range(of: pattern, options: .regularExpression) != nil
            }
        }.count
        
        // If more than 30% of lines match code patterns, consider it code
        if lines.count > 0 && Double(codeLineCount) / Double(lines.count) > 0.3 {
            return .code
        }
        
        return .plainText
    }
}
