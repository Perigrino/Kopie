import Foundation

/// Detects secrets (passwords, API keys, tokens) in copied text so the app can
/// mask or skip them instead of filing credentials into the permanent history.
///
/// Pure Foundation — no AppKit — and fully unit-tested. Rules run strongest
/// first and the first match wins. Callers decide the *policy* (mask vs skip);
/// this type only classifies.
public enum SensitiveDataPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    public var id: String { rawValue }

    /// Store everything as-is (feature disabled).
    case off
    /// Store the item but flag it: rows render masked, content hidden until
    /// explicitly revealed in the details panel (default).
    case mask
    /// Never store matched content at all.
    case skipCapture

    public var label: String {
        switch self {
        case .off: return "Off"
        case .mask: return "Mask"
        case .skipCapture: return "Don't Save"
        }
    }
}

public struct SensitiveMatch: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case apiToken
        case jwt
        case privateKey
        case credentialURL
        case bearerHeader
        case highEntropy
        case seedPhrase
        case paymentCard

        /// Human label shown in the details panel ("Detected as …").
        public var label: String {
            switch self {
            case .apiToken: return "API key or token"
            case .jwt: return "JSON Web Token"
            case .privateKey: return "Private key"
            case .credentialURL: return "URL with credentials"
            case .bearerHeader: return "Authorization header"
            case .highEntropy: return "High-entropy secret"
            case .seedPhrase: return "Wallet seed phrase"
            case .paymentCard: return "Payment card number"
            }
        }

        /// SF Symbol for the row badge.
        public var symbol: String {
            switch self {
            case .apiToken: return "key.fill"
            case .jwt: return "key.horizontal.fill"
            case .privateKey: return "lock.fill"
            case .credentialURL: return "link.badge.plus" // unused fallback; badge stays a key
            case .bearerHeader: return "key.fill"
            case .highEntropy: return "questionmark.key.fill"
            case .seedPhrase: return "banknote.fill"
            case .paymentCard: return "creditcard.fill"
            }
        }
    }

    public let kind: Kind
    /// Identifier of the rule that fired (for per-rule Settings toggles).
    public let ruleID: String
}

public enum SensitiveDataDetector {

    /// One disableable rule, surfaced in Settings → Privacy.
    public struct Rule: Identifiable, Equatable, Sendable {
        public let id: String
        public let label: String
        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// All rules in evaluation priority order.
    public static let allRules: [Rule] = [
        Rule(id: "known_prefix", label: "Known API key prefixes"),
        Rule(id: "jwt", label: "JSON Web Tokens"),
        Rule(id: "private_key", label: "Private key blocks"),
        Rule(id: "credential_url", label: "URLs with embedded passwords"),
        Rule(id: "bearer_header", label: "Authorization headers"),
        Rule(id: "entropy", label: "High-entropy tokens"),
        Rule(id: "seed_phrase", label: "Wallet seed phrases"),
        Rule(id: "card", label: "Payment card numbers"),
    ]

    public static let allRuleIDs: Set<String> = Set(allRules.map { $0.id })

    /// Classifies `text`. Returns the first matching rule (priority order),
    /// skipping rules whose ids are not in `enabledRules`.
    public static func detect(in text: String,
                              enabledRules: Set<String> = allRuleIDs) -> SensitiveMatch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 10_000 else { return nil }

        if enabledRules.contains("known_prefix"), matchesKnownPrefix(trimmed) {
            return SensitiveMatch(kind: .apiToken, ruleID: "known_prefix")
        }
        if enabledRules.contains("jwt"), matchesJWT(trimmed) {
            return SensitiveMatch(kind: .jwt, ruleID: "jwt")
        }
        if enabledRules.contains("private_key"), trimmed.contains("-----BEGIN"),
           trimmed.contains("PRIVATE KEY-----") {
            return SensitiveMatch(kind: .privateKey, ruleID: "private_key")
        }
        if enabledRules.contains("credential_url"), matchesCredentialURL(trimmed) {
            return SensitiveMatch(kind: .credentialURL, ruleID: "credential_url")
        }
        if enabledRules.contains("bearer_header"), matchesBearer(trimmed) {
            return SensitiveMatch(kind: .bearerHeader, ruleID: "bearer_header")
        }
        if enabledRules.contains("seed_phrase"), matchesSeedPhrase(trimmed) {
            return SensitiveMatch(kind: .seedPhrase, ruleID: "seed_phrase")
        }
        if enabledRules.contains("card"), matchesPaymentCard(trimmed) {
            return SensitiveMatch(kind: .paymentCard, ruleID: "card")
        }
        if enabledRules.contains("entropy"), matchesHighEntropy(trimmed) {
            return SensitiveMatch(kind: .highEntropy, ruleID: "entropy")
        }
        return nil
    }

    // MARK: - Rule implementations

    /// Vendor-specific token prefixes. Anchored to word starts so ordinary
    /// words beginning with the same letters don't match.
    private static let prefixPatterns: [String] = [
        #"gh[posur]_"#,
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"sk-ant-"#,
        #"sk-"#,
        #"xox[abprs]-"#,
        #"AKIA[0-9A-Z]{16}"#,
        #"AIza[0-9A-Za-z_-]{30,}"#,
        #"SG\.[A-Za-z0-9_-]{20,}"#,
        #"npm_[A-Za-z0-9]{30,}"#,
        #"glpat-[A-Za-z0-9_-]{15,}"#,
        #"gsk_[A-Za-z0-9]{20,}"#,
        #"hf_[A-Za-z0-9]{30,}"#,
    ]

    private static func matchesKnownPrefix(_ text: String) -> Bool {
        for pattern in prefixPatterns {
            if text.range(of: "\\b" + pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// Three base64url segments, header/payload starting with the `eyJ` of `{"`.
    private static func matchesJWT(_ text: String) -> Bool {
        text.range(of: #"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,
                   options: .regularExpression) != nil
    }

    /// scheme://user:password@… or a credential-bearing query parameter.
    private static func matchesCredentialURL(_ text: String) -> Bool {
        let patterns = [
            #"[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@"#,
            #"[?&](password|passwd|pwd|secret|api_key|apikey|access_token|auth_token|token|key)=[^\s&]{4,}"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// `Authorization: Bearer <token>` (quote variations tolerated).
    private static func matchesBearer(_ text: String) -> Bool {
        text.range(of: #"(?i)authorization["']?\s*[:=]\s*["']?bearer\s+\S{8,}"#,
                   options: .regularExpression) != nil
    }

    /// Exactly 12 or 24 lowercase single words (BIP-39 shape).
    private static func matchesSeedPhrase(_ text: String) -> Bool {
        let words = text.split { $0.isWhitespace || $0 == "\n" || $0 == "\t" }
        guard words.count == 12 || words.count == 24 else { return false }
        return words.allSatisfy { word in
            let w = String(word)
            return w.range(of: #"^[a-z]{3,12}$"#, options: .regularExpression) != nil
        }
    }

    /// 13–19 digits (spaces/dashes allowed) that pass the Luhn checksum.
    private static func matchesPaymentCard(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace && $0 != "-" }
        guard compact.count >= 13, compact.count <= 19, compact.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        let digits = compact.reversed().compactMap { $0.wholeNumberValue }
        for (i, d) in digits.enumerated() {
            if i.isMultiple(of: 2) { sum += d }
            else { sum += d < 5 ? d * 2 : d * 2 - 9 }
        }
        return sum.isMultiple(of: 10)
    }

    /// Catch-all: a long single token of high character-entropy. Guards keep
    /// URLs, hex hashes, UUIDs, and ordinary words out.
    private static func matchesHighEntropy(_ text: String) -> Bool {
        // Candidate tokens: runs that look like base64/base62 with _ = / -.
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9+/=_\-]{20,}"#) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let token = String(text[r])
            if looksLikeSecret(token) { return true }
        }
        return false
    }

    private static func looksLikeSecret(_ token: String) -> Bool {
        guard token.count >= 20, token.count <= 400 else { return false }
        // URLs and paths are not secrets even when long.
        if token.contains("://") { return false }
        // Hex (and dashed hex: UUIDs, commit SHAs, hashes) is copied
        // constantly and never secret.
        if token.range(of: #"^[0-9a-fA-F-]+$"#, options: .regularExpression) != nil { return false }
        // Real entropy gate (Shannon, bits/char): prose and repeated patterns stay low.
        guard shannonEntropy(token) >= 3.5 else { return false }
        // Require letter+digit mix: pure words (even odd ones) are usually prose.
        let hasLetter = token.contains { $0.isLetter }
        let hasDigit = token.contains { $0.isNumber }
        return hasLetter && hasDigit
    }

    /// Shannon entropy in bits per character (max 4 for a 16-symbol alphabet,
    /// ~5.2 for base64, ~5.9 for base62+symbols).
    static func shannonEntropy(_ s: String) -> Double {
        var freq: [Character: Int] = [:]
        for c in s { freq[c, default: 0] += 1 }
        let n = Double(s.count)
        guard n > 0 else { return 0 }
        return freq.values.reduce(0) { total, count in
            let p = Double(count) / n
            return total - p * log2(p)
        }
    }

    // MARK: - OTP / magic-link shapes (drives per-item expiry in Phase 2)

    /// True when the whole content looks like a one-time code or magic link:
    /// a bare 6-digit code, Google's `G-######`, or a URL carrying a
    /// token/verification query parameter. Conservative on purpose — a wrong
    /// guess only means the item asks to be deleted after its next paste.
    public static func looksLikeOneTimeSecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d{6}$"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^G-\d{6}$"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^[a-z][a-z0-9+.-]*://\S+[?&](token|verification_code|verify|confirm|magic|otp|code)="#,
                         options: .regularExpression) != nil { return true }
        return false
    }
}
