import XCTest
@testable import KopieCore

/// Coverage for the sensitive-data sentinel: each rule fires on real-world
/// secret shapes and stays silent on ordinary content. The false-positive
/// table is as important as the true-positive one — the mask-not-drop
/// guarantee depends on the detector being conservative.
final class SensitiveDataDetectorTests: XCTestCase {

    // MARK: - Known prefixes

    /// FIXTURE NOTE: these are deliberately fake shapes (pattern-true,
    /// checksum/prefix-false) so GitHub push protection never mistakes the
    /// test suite for a real leaked credential. They must still satisfy the
    /// detector's regexes — that is the contract under test.
    func test_knownPrefixes_fire() {
        let secrets = [
            "ghp_ZZZnotarealtokenZZZ0123456789abcdef",
            "github_pat_ZZ11ABCDEFG0abcdefghij_ABCDEFGHIJKLMNOPQRSTUVWX",
            "gho_ZZZnotarealtokenZZZ0123456789abcdef",
            "sk-proj-ZZZZnotarealkey0123456789abcdef",
            "sk-ant-api03-ZZZZnotarealkey0123456789",
            "xoxb-ZZZ-not-a-real-slack-token-at-all",
            "AKIAZZZZZZZZZZZZZZZZ",
            "AIzaSyA-ZZZZnotarealgooglekey012345678",
            "SG.ZZZZZZZZZZnotarealsendgridkey.ZZZZZZZZZZnotarealsendgridsecret",
            "npm_ZZZZnotarealnpmtoken0123456789abcd",
            "glpat-ZZZnotarealgitlabtoken",
            "gsk_ZZZZnotarealgroqkey0123456789",
            "hf_ZZZZnotarealhuggingfacetoken012345",
        ]
        for s in secrets {
            XCTAssertEqual(detect(s)?.ruleID, "known_prefix", "should flag: \(s)")
            XCTAssertEqual(detect(s)?.kind, .apiToken)
        }
    }

    func test_knownPrefixes_wordAnchored() {
        // A prose word that merely starts with prefix-ish letters must not fire.
        XCTAssertNil(detect("skiing lessons tomorrow"))
        XCTAssertNil(detect("the skunk ran across the yard"))
    }

    // MARK: - JWT

    func test_jwt_fires() {
        XCTAssertEqual(detect("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c")?.kind, .jwt)
    }

    func test_truncatedJWT_stillCaughtByEntropyRule() {
        // A two-segment eyJ string is a corrupted/truncated JWT — not the JWT
        // rule's shape, but exactly what the entropy catch-all exists for.
        // Masking a maybe-secret is the conservative, correct outcome.
        let m = detect("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0")
        XCTAssertNotEqual(m?.ruleID, "jwt")
        XCTAssertEqual(m?.ruleID, "entropy")
    }

    // MARK: - Private keys

    func test_privateKeyBlock_fires() {
        let pem = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEpAIBAAKCAQEA7v9X pretend body line
        -----END RSA PRIVATE KEY-----
        """
        XCTAssertEqual(detect(pem)?.kind, .privateKey)
        let openssh = "-----BEGIN OPENSSH PRIVATE KEY-----"
        XCTAssertEqual(detect(openssh)?.kind, .privateKey)
    }

    // MARK: - Credential URLs

    func test_credentialURL_fires() {
        XCTAssertEqual(detect("postgres://admin:s3cret@db.internal:5432/prod")?.kind, .credentialURL)
        XCTAssertEqual(detect("https://example.com/reset?token=abcdef123456")?.kind, .credentialURL)
        XCTAssertEqual(detect("https://api.example.com/v1?key=abcdefgh1234")?.kind, .credentialURL)
    }

    func test_plainURL_doesNotFire() {
        XCTAssertNil(detect("https://github.com/p0deje/Maccy"))
        XCTAssertNil(detect("postgres://db.internal:5432/prod"))
    }

    // MARK: - Bearer headers

    func test_bearerHeader_fires() {
        XCTAssertEqual(detect("Authorization: Bearer abc123def456ghi789")?.kind, .bearerHeader)
        XCTAssertEqual(detect("authorization='bearer ABCDEF1234567890'")?.kind, .bearerHeader)
    }

    // MARK: - Seed phrases

    func test_seedPhrase_fires() {
        let twelve = Array(repeating: "word", count: 11).joined(separator: " ") + " vendor"
        XCTAssertEqual(detect(twelve)?.kind, .seedPhrase)
        let twentyFour = Array(repeating: "abandon", count: 24).joined(separator: " ")
        XCTAssertEqual(detect(twentyFour)?.kind, .seedPhrase)
    }

    func test_otherWordCounts_doNotFireAsSeedPhrase() {
        XCTAssertNil(detect("eleven words only here are not enough yet to trip"))
        XCTAssertNil(detect("The quick brown fox jumps over the lazy dog near the riverbank"))
    }

    // MARK: - Payment cards

    func test_validCardNumber_fires() {
        // 4242 4242 4242 4242 passes Luhn.
        XCTAssertEqual(detect("4242 4242 4242 4242")?.kind, .paymentCard)
        XCTAssertEqual(detect("4242424242424242")?.kind, .paymentCard)
    }

    func test_luhnFailingDigits_doNotFire() {
        XCTAssertNil(detect("4242 4242 4242 4241"))
    }

    // MARK: - Entropy heuristic

    func test_highEntropyToken_fires() {
        XCTAssertEqual(detect("Zx9Q2wR7vN4kL8pM3jT6yH1f")?.kind, .highEntropy)
    }

    func test_entropy_falsePositives_staySilent() {
        let ordinary = [
            "hello world this is a normal sentence with words",
            "d41d8cd98f00b204e9800998ecf8427e",                 // hex MD5
            "f6c3a83e6ae06bea1d4a9c7f2d2e8b9a1c4d5e6f7a8b9c0d", // long hex
            "https://example.com/very/long/path/to/somewhere",
            "123e4567-e89b-12d3-a456-426614174000",             // UUID
            "meeting notes from the quarterly planning session",
        ]
        for t in ordinary {
            XCTAssertNil(detect(t), "should NOT flag: \(t)")
        }
    }

    // MARK: - Rule enablement

    func test_disabledRules_areSkipped() {
        let token = "ghp_ZZZnotarealtokenZZZ0123456789abcdef"
        XCTAssertNil(detect(token, enabledRules: []))
        XCTAssertEqual(detect(token, enabledRules: ["known_prefix"])?.ruleID, "known_prefix")
        // Disabling the entropy rule alone silences only entropy matches.
        XCTAssertNil(detect("Zx9Q2wR7vN4kL8pM3jT6yH1f", enabledRules: allRulesWithout("entropy")))
    }

    func test_allRuleIDs_coverEveryRule() {
        XCTAssertEqual(SensitiveDataDetector.allRuleIDs.count, SensitiveDataDetector.allRules.count)
        XCTAssertEqual(SensitiveDataDetector.allRules.map(\.id).count,
                       Set(SensitiveDataDetector.allRules.map(\.id)).count,
                       "rule ids must be unique")
    }

    func test_emptyAndHugeInput_areIgnored() {
        XCTAssertNil(detect(""))
        XCTAssertNil(detect("   \n  "))
        XCTAssertNil(detect(String(repeating: "x", count: 10_001)))
    }

    // MARK: - OTP / magic-link shapes

    func test_oneTimeShapes_detected() {
        XCTAssertTrue(SensitiveDataDetector.looksLikeOneTimeSecret("482913"))
        XCTAssertTrue(SensitiveDataDetector.looksLikeOneTimeSecret("G-482913"))
        XCTAssertTrue(SensitiveDataDetector.looksLikeOneTimeSecret("https://mail.example.com/verify?token=abc123"))
        XCTAssertTrue(SensitiveDataDetector.looksLikeOneTimeSecret("https://app.example.com/login?otp=482913"))
    }

    func test_ordinaryContent_notOneTime() {
        XCTAssertFalse(SensitiveDataDetector.looksLikeOneTimeSecret("call me at 482913 extension 5"))
        XCTAssertFalse(SensitiveDataDetector.looksLikeOneTimeSecret("1234567890"))
        XCTAssertFalse(SensitiveDataDetector.looksLikeOneTimeSecret("https://example.com/blog/posts"))
    }

    // MARK: - Entropy helper

    func test_shannonEntropy_bounds() {
        XCTAssertEqual(SensitiveDataDetector.shannonEntropy(""), 0)
        XCTAssertGreaterThan(SensitiveDataDetector.shannonEntropy("aB3xZ9"), 2.0)
        XCTAssertEqual(SensitiveDataDetector.shannonEntropy("aaaa"), 0, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func detect(_ s: String,
                        enabledRules: Set<String> = SensitiveDataDetector.allRuleIDs) -> SensitiveMatch? {
        SensitiveDataDetector.detect(in: s, enabledRules: enabledRules)
    }

    private func allRulesWithout(_ id: String) -> Set<String> {
        SensitiveDataDetector.allRuleIDs.subtracting([id])
    }
}
