import Foundation

/// Detects the type of content in a text string for smart paste suggestions.
public enum ContentType: Sendable {
    case url
    case email
    case phoneNumber
    case code(language: String?)
    case richText
    case plainText
}

public enum ContentDetector {
    /// Detects the programming language from code content.
    public static func detectLanguage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("func ") && trimmed.contains("->") { return "swift" }
        if trimmed.contains("def ") || trimmed.contains("__init__") { return "python" }
        if trimmed.contains("function ") || trimmed.contains("=>") { return "javascript" }
        if trimmed.contains("<html") || trimmed.contains("<div") { return "html" }
        if trimmed.contains("color:") || trimmed.contains("margin:") { return "css" }
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return "json" }
        if trimmed.contains("# ") || trimmed.contains("## ") { return "markdown" }
        if trimmed.contains("SELECT ") || trimmed.contains("CREATE TABLE") { return "sql" }
        if trimmed.hasPrefix("#!") || trimmed.contains("echo ") { return "bash" }
        if trimmed.contains("fn ") && trimmed.contains("let mut") { return "rust" }
        if trimmed.contains("package ") && trimmed.contains("func ") { return "go" }
        if trimmed.contains("public class ") { return "java" }
        if trimmed.contains("#include ") || trimmed.contains("std::") { return "cpp" }
        // JavaScript/TypeScript signals: const/let/var bindings, await, arrow
        // functions, and ES module imports.
        if trimmed.contains("const ") || trimmed.contains("await ")
            || trimmed.contains("=>") || trimmed.contains("require(")
            || trimmed.contains("interface ") || trimmed.contains("typeof ")
            || trimmed.contains("console.log(") || trimmed.contains("import ") {
            return "typescript"
        }
        return nil
    }
    
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
            "^const\\s+",            // const bindings
            "^await\\s+",            // await expressions
            "^async\\s+",            // async functions
            "^export\\s+",           // module exports
            "^return\\s+",           // return statements
            "^if\\s*\\(|^if\\s+.*\\{", // if statements
            "^for\\s*\\(|^for\\s+.*\\{", // for loops
            "^while\\s*\\(|^while\\s+.*\\{", // while loops
            "^switch\\s+",           // switch statements
            "^case\\s+",             // case statements
            "^=>\\s*",               // arrow functions
            "=>",                    // arrow functions (anywhere)
            "^\\w+\\.\\w+\\s*=",     // member assignment (e.g. obj.prop =)
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
            let language = detectLanguage(trimmed)
            return .code(language: language)
        }
        
        return .plainText
    }
}
