import Foundation

/// Parses color literals out of copied text so color-only items can present
/// as swatches. Pure Foundation; the UI turns `ColorValue` into NSColor/SwiftUI
/// colors. Only whole-content matches count — a hex string inside a longer
/// sentence is not a color copy.
public enum ColorParser {

    public struct ColorValue: Equatable, Sendable {
        /// 0–1 normalized components.
        public let red: Double
        public let green: Double
        public let blue: Double
        /// Nil for RGB/hex sources.
        public let hue: Double?
        /// Nil for RGB/hex sources.
        public let saturation: Double?
        public let lightness: Double?
        public let alpha: Double

        /// Upper-case hex without `#`, e.g. `4F46E5`.
        public var hexString: String {
            let r = Int(round(red * 255))
            let g = Int(round(green * 255))
            let b = Int(round(blue * 255))
            return String(format: "%02X%02X%02X", r, g, b)
        }

        public var rgbString: String {
            let r = Int(round(red * 255))
            let g = Int(round(green * 255))
            let b = Int(round(blue * 255))
            return alpha < 1 ? "rgba(\(r), \(g), \(b), \(formatted(alpha)))"
                             : "rgb(\(r), \(g), \(b))"
        }

        public var hslString: String {
            guard let h = hue, let s = saturation, let l = lightness else {
                let conv = rgbToHsl(red, green, blue)
                return alpha < 1
                    ? "hsla(\(Int(conv.h)), \(Int(conv.s * 100))%, \(Int(conv.l * 100))%, \(formatted(alpha)))"
                    : "hsl(\(Int(conv.h)), \(Int(conv.s * 100))%, \(Int(conv.l * 100))%)"
            }
            return alpha < 1
                ? "hsla(\(Int(h)), \(Int(s * 100))%, \(Int(l * 100))%, \(formatted(alpha)))"
                : "hsl(\(Int(h)), \(Int(s * 100))%, \(Int(l * 100))%)"
        }

        private func formatted(_ v: Double) -> String {
            String(format: "%.2f", v)
        }
    }

    /// Returns nil unless the WHOLE trimmed content is a color literal:
    /// `#4F46E5`, `4F46E5`, `#4F46E5CC`, `rgb(79 70 229)`, `rgba(79, 70, 229, 0.5)`,
    /// `hsl(243, 75%, 59%)`, `hsla(243 75% 59% / 0.4)`.
    public static func parse(_ text: String) -> ColorValue? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 64 else { return nil }
        if let v = parseHex(t) { return v }
        if let v = parseRGB(t) { return v }
        if let v = parseHSL(t) { return v }
        return nil
    }

    // MARK: - Hex

    private static func parseHex(_ t: String) -> ColorValue? {
        let hasHash = t.hasPrefix("#")
        var s = t
        if hasHash { s.removeFirst() }
        // Bare 6-digit hex is a common dev copy; bare 8-digit (with alpha) is
        // too ambiguous — phone numbers and IDs live there — so it needs the #.
        guard s.count == 6 || (s.count == 8 && hasHash),
              s.allSatisfy({ $0.isHexDigit }) else { return nil }
        func comp(_ str: Substring) -> Double {
            Double(strtol(String(str), nil, 16)) / 255.0
        }
        let r = comp(s.prefix(2))
        let g = comp(s.dropFirst(2).prefix(2))
        let b = comp(s.dropFirst(4).prefix(2))
        let a: Double = s.count == 8 ? comp(s.dropFirst(6)) : 1
        return ColorValue(red: r, green: g, blue: b, hue: nil, saturation: nil, lightness: nil, alpha: a)
    }

    // MARK: - rgb()/rgba()

    private static func parseRGB(_ t: String) -> ColorValue? {
        let lower = t.lowercased()
        let numbers = matches(of: #"\d*\.?\d+"#, in: lower)
        let hasPrefix = lower.hasPrefix("rgb(") || lower.hasPrefix("rgba(")
        let hasSuffix = lower.hasSuffix(")")
        guard hasPrefix, hasSuffix, numbers.count == 3 || numbers.count == 4 else { return nil }
        let comps = numbers.compactMap(Double.init)
        guard comps.count == numbers.count else { return nil }
        let rgb = comps.prefix(3)
        guard rgb.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return nil }
        let r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
        var a = 1.0
        if comps.count == 4 {
            guard comps[3] >= 0, comps[3] <= 1 else { return nil }
            a = comps[3]
        }
        return ColorValue(red: r, green: g, blue: b, hue: nil, saturation: nil, lightness: nil, alpha: a)
    }

    // MARK: - hsl()/hsla()

    private static func parseHSL(_ t: String) -> ColorValue? {
        let lower = t.lowercased()
        guard lower.hasPrefix("hsl"), lower.hasSuffix(")") else { return nil }
        let numbers = matches(of: #"\d*\.?\d+"#, in: lower)
        guard numbers.count == 3 || numbers.count == 4 else { return nil }
        let comps = numbers.compactMap(Double.init)
        guard comps.count == numbers.count else { return nil }
        let h = comps[0]
        let s = comps[1] / 100
        let l = comps[2] / 100
        guard (0...360).contains(h), (0...1).contains(s), (0...1).contains(l) else { return nil }
        var a = 1.0
        if comps.count == 4 {
            guard comps[3] >= 0, comps[3] <= 1 else { return nil }
            a = comps[3]
        }
        let rgb = hslToRgb(h: h, s: s, l: l)
        return ColorValue(red: rgb.r, green: rgb.g, blue: rgb.b,
                          hue: h, saturation: s, lightness: l, alpha: a)
    }

    // MARK: - Conversions

    static func hslToRgb(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default:   (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return (r1 + m, g1 + m, b1 + m)
    }

    static func rgbToHsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        guard maxV != minV else { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if maxV == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }
}
