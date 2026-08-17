import XCTest
import KopieCore

final class ModelsTests: XCTestCase {
    func test_retentionDays() {
        XCTAssertNil(RetentionPeriod.never.days)
        XCTAssertEqual(RetentionPeriod.day7.days, 7)
        XCTAssertEqual(RetentionPeriod.ninetyDays.days, 90)
    }
    func test_retentionLabel() {
        XCTAssertEqual(RetentionPeriod.never.label, "Never")
        XCTAssertEqual(RetentionPeriod.daySeven.label, "7 days")
    }
    func test_capturedContentAccessors() {
        let t = CapturedContent(kind: .text("hey"), sourceAppID: "com.apple.Safari")
        XCTAssertEqual(t.clipKind, .text)
        XCTAssertEqual(t.text, "hey")
        XCTAssertNil(t.imageData)
        XCTAssertEqual(t.sourceAppID, "com.apple.Safari")
        XCTAssertEqual(t.canonicalData, Data("hey".utf8))
    }
    func test_capturedContentImageAccessors() {
        let i = CapturedContent(kind: .image(Data([7, 8])), sourceAppID: nil)
        XCTAssertEqual(i.clipKind, .image)
        XCTAssertEqual(i.imageData, Data([7, 8]))
        XCTAssertNil(i.text)
    }
    func test_dimensionLabel() {
        var m = ClipboardItem(id: 1, kind: .image, createdAt: .now, lastAccessedAt: .now,
                              isFavorite: false, contentHash: "h", text: nil,
                              imageRelPath: nil, thumbRelPath: nil, fileSize: 0, width: 1920, height: 1080)
        XCTAssertEqual(m.dimensionLabel, "1920 × 1080")
        m.kind = .text; m.text = "abc"; m.width = nil; m.height = nil
        XCTAssertEqual(m.charCount, 3)
        XCTAssertEqual(m.typeLabel, "Text")
        XCTAssertNil(m.dimensionLabel)
    }
    func test_previewTruncatesLongText() {
        var m = ClipboardItem(id: 1, kind: .text, createdAt: .now, lastAccessedAt: .now,
                              isFavorite: false, contentHash: "h", text: String(repeating: "a", count: 300),
                              imageRelPath: nil, thumbRelPath: nil, fileSize: 0, width: nil, height: nil)
        XCTAssertTrue(m.preview.hasSuffix("…"))
        m.text = "short"
        XCTAssertEqual(m.preview, "short")
    }
}
