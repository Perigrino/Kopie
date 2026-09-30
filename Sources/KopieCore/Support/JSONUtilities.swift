import Foundation

/// Pure JSON text utilities for the details panel: pretty-print, minify,
/// validate. `JSONSerialization` reorders keys semantically (it sorts them),
/// which is documented behavior — Pretty is for readability, not byte-faithful
/// round-trips.
public enum JSONUtilities {

    public enum OutputFormat: String, CaseIterable, Sendable {
        case twoSpace, fourSpace, tab, minified
    }

    public enum JSONError: Error, Equatable {
        /// Human-readable serialization error including position when available.
        case invalidJSON(String)
        case empty
    }

    /// Re-formats valid JSON text. Throws `JSONError.invalidJSON` with the
    /// underlying message when the input doesn't parse.
    public static func format(_ text: String, as style: OutputFormat) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JSONError.empty }
        guard let data = trimmed.data(using: .utf8) else { throw JSONError.empty }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw JSONError.invalidJSON(prettyError(error))
        }
        // Top-level scalars (RFC 8259 fragments like `42` or `"hi"`) are
        // already canonical — JSONSerialization refuses to WRITE them, and
        // re-formatting would change nothing anyway.
        if obj is NSNull || obj is NSNumber || obj is NSString || obj is Bool {
            return style == .minified ? trimmed : trimmed
        }
        switch style {
        case .minified:
            guard let out = try? JSONSerialization.data(withJSONObject: obj) else {
                throw JSONError.invalidJSON("could not serialize")
            }
            return String(data: out, encoding: .utf8) ?? ""
        default:
            let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            guard let out = try? JSONSerialization.data(withJSONObject: obj, options: options) else {
                throw JSONError.invalidJSON("could not serialize")
            }
            let pretty = String(data: out, encoding: .utf8) ?? ""
            switch style {
            case .fourSpace: return reindent(pretty, unit: "    ")
            case .tab: return reindent(pretty, unit: "\t")
            default: return pretty
            }
        }
    }

    /// Validates without reformatting; returns nil when valid, else the error.
    public static func validate(_ text: String) -> String? {
        do { _ = try format(text, as: .twoSpace); return nil }
        catch let e as JSONError {
            if case .invalidJSON(let msg) = e { return msg }
            return "empty input"
        } catch { return "\(error)" }
    }

    /// JSONSerialization's default indentation is two spaces per level.
    private static func reindent(_ pretty: String, unit: String) -> String {
        pretty.components(separatedBy: "\n").map { line in
            var count = 0
            for c in line {
                if c == " " { count += 1 } else { break }
            }
            let level = count / 2
            return String(repeating: unit, count: level) + line.dropFirst(count)
        }.joined(separator: "\n")
    }

    private static func prettyError(_ error: Error) -> String {
        let desc = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? "\(error)"
        // Cocoa reports odd character offsets; surface the line number instead.
        if let range = desc.range(of: #"character \d+"#, options: .regularExpression) {
            return String(desc[range])
        }
        return desc
    }
}
