import XCTest
@testable import KopieCore

/// End-to-end sentinel behavior through the capture pipeline: policy outcomes,
/// flag persistence, and the one-time-secret expiry flag.
final class SensitivePipelineTests: XCTestCase {
    var store: ClipStore!
    var writer: DiskClipWriter!
    var pipeline: CapturePipeline!
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sentinel_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
        writer = DiskClipWriter(baseDir: tmp)
        pipeline = CapturePipeline(store: store, writer: writer)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    private func capture(_ text: String, config: CaptureConfig) -> CaptureResult {
        pipeline.process(.init(kind: .text(text), sourceAppID: nil), config: config)
    }

    // MARK: - Mask policy (default)

    func test_maskPolicy_storesItemFlagged() throws {
        let r = capture("ghp_ZZZnotarealtokenZZZ0123456789abcdef", config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        let item = try XCTUnwrap(store.get(id))
        XCTAssertTrue(item.isSensitive)
        XCTAssertEqual(item.sensitiveKind, SensitiveMatch.Kind.apiToken.rawValue)
        // Content is still stored — masking is a presentation concern.
        XCTAssertEqual(item.text, "ghp_ZZZnotarealtokenZZZ0123456789abcdef")
    }

    func test_ordinaryText_notFlagged() throws {
        let r = capture("just a normal sentence about meeting notes", config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        let item = try XCTUnwrap(store.get(id))
        XCTAssertFalse(item.isSensitive)
        XCTAssertNil(item.sensitiveKind)
    }

    // MARK: - Skip policy

    func test_skipPolicy_neverStoresSecret() {
        var config = CaptureConfig.default
        config.sensitivePolicy = .skipCapture
        let r = capture("ghp_ZZZnotarealtokenZZZ0123456789abcdef", config: config)
        XCTAssertEqual(r, .sensitiveSkipped)
        XCTAssertEqual(store.count(), 0)
    }

    func test_skipPolicy_stillStoresOrdinaryText() throws {
        var config = CaptureConfig.default
        config.sensitivePolicy = .skipCapture
        let r = capture("nothing sensitive here", config: config)
        guard case .captured = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertEqual(store.count(), 1)
    }

    // MARK: - Rule enablement flows through

    func test_disabledRule_doesNotFlag() throws {
        // A SHORT token only the prefix rule catches (below the entropy
        // rule's 20-char floor), so disabling known_prefix really silences it.
        var config = CaptureConfig.default
        config.sensitiveEnabledRules = SensitiveDataDetector.allRuleIDs.subtracting(["known_prefix"])
        let r = capture("ghp_abc", config: config)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertFalse(try XCTUnwrap(store.get(id)).isSensitive)
    }

    func test_disablingOneRule_otherRulesStillDetect() throws {
        // Defense-in-depth: a long GitHub token also looks like a high-entropy
        // string, so turning off the prefix rule alone must not blind the
        // sentinel to it. Only disabling BOTH rules does.
        var config = CaptureConfig.default
        config.sensitiveEnabledRules = SensitiveDataDetector.allRuleIDs.subtracting(["known_prefix"])
        let r = capture("ghp_ZZZnotarealtokenZZZ0123456789abcdef", config: config)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertTrue(try XCTUnwrap(store.get(id)).isSensitive)

        config.sensitiveEnabledRules = config.sensitiveEnabledRules.subtracting(["entropy"])
        if case .captured(let id2) = capture("gho_16C7e42F292c6912E7710c838347Ae178B4b", config: config) {
            XCTAssertFalse(try XCTUnwrap(store.get(id2)).isSensitive)
        }
    }

    // MARK: - One-time expiry flag (Phase 2)

    func test_otpCapture_flaggedForExpiry() throws {
        let r = capture("482913", config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertTrue(try XCTUnwrap(store.get(id)).expiresAfterUse)
    }

    func test_magicLinkCapture_flaggedForExpiry() throws {
        let r = capture("https://mail.example.com/verify?token=abc123", config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertTrue(try XCTUnwrap(store.get(id)).expiresAfterUse)
    }

    func test_autoExpireOff_leavesFlagClear() throws {
        var config = CaptureConfig.default
        config.autoExpireOneTime = false
        let r = capture("482913", config: config)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        XCTAssertFalse(try XCTUnwrap(store.get(id)).expiresAfterUse)
    }

    func test_expiryFlag_persistsAcrossStoreReopen() throws {
        let r = capture("482913", config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected capture, got \(r)") }
        let reopened = try ClipStore(dir: tmp)
        XCTAssertTrue(try XCTUnwrap(reopened.get(id)).expiresAfterUse)
        // And the manual toggle can clear it.
        reopened.setExpiresAfterUse(id, false)
        XCTAssertFalse(try XCTUnwrap(reopened.get(id)).expiresAfterUse)
    }

    func test_purgeExpiredUnused_deletesOnlyOldFlaggedRows() throws {
        let old = pipeline.process(
            .init(kind: .text("482913"), sourceAppID: nil),
            config: .default,
            now: Date.now.addingTimeInterval(-48 * 3600))
        let fresh = pipeline.process(.init(kind: .text("482914"), sourceAppID: nil), config: .default)
        guard case .captured(let oldID) = old, case .captured(let freshID) = fresh else {
            return XCTFail("expected two captures")
        }
        // One day back: only the 48h-old flagged row goes.
        let cutoff = Date.now.addingTimeInterval(-24 * 3600)
        store.purgeExpiredUnused(olderThan: cutoff)
        XCTAssertNil(store.get(oldID))
        XCTAssertNotNil(store.get(freshID))
    }
}
