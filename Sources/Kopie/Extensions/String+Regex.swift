import Foundation

extension String {
    /// Checks if the string is a valid regular expression pattern.
    var isValidRegex: Bool {
        do {
            _ = try NSRegularExpression(pattern: self, options: [])
            return true
        } catch {
            return false
        }
    }
}
