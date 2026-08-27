import XCTest
import KopieCore
import AppKit

final class HistoryExporterTests: XCTestCase {
    var store: ClipStore!
    var writer: DiskClipWriter!
    var pipe: CapturePipeline!
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("he_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        store = try ClipStore(dir: tmp)
        writer = DiskClipWriter(baseDir: tmp)
        pipe = CapturePipeline(store: store, writer: writer)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_roundTrip_PreservesRichTextFormat() throws {
        // Capture a plain-text item and an HTML rich-text item.
        _ = pipe.process(.init(kind: .text("plain hello"), sourceAppID: nil), config: .default)
        let html = "<html><body><b>Bold</b> text</body></html>".data(using: .utf8)!
        _ = pipe.process(.init(kind: .textWithHTML("Bold text", html), sourceAppID: nil), config: .default)

        let url = tmp.appendingPathComponent("history.json")
        try HistoryExporter(store: store, writer: writer).export(to: url)

        // Import into a fresh, empty store.
        let importDir = tmp.appendingPathComponent("import")
        let store2 = try ClipStore(dir: importDir)
        let writer2 = DiskClipWriter(baseDir: importDir)
        let count = try HistoryExporter(store: store2, writer: writer2).import(from: url)
        XCTAssertEqual(count, 2, "both items imported")

        let items = store2.query(.init(limit: 100))
        XCTAssertEqual(items.count, 2)

        let htmlItem = items.first { $0.text == "Bold text" }
        XCTAssertNotNil(htmlItem, "html item present")
        XCTAssertEqual(htmlItem?.richTextRelPath?.hasSuffix(".html"), true,
                       "HTML item must round-trip as .html, not be re-stored as .rtf")
        XCTAssertEqual(htmlItem?.isRichText, true)
    }

    func test_import_SkipsDuplicatesByHash() throws {
        _ = pipe.process(.init(kind: .text("dupe"), sourceAppID: nil), config: .default)
        let url = tmp.appendingPathComponent("history.json")
        try HistoryExporter(store: store, writer: writer).export(to: url)

        // Import the same file twice into a fresh store: second import is a no-op.
        let importDir = tmp.appendingPathComponent("import2")
        let store2 = try ClipStore(dir: importDir)
        let writer2 = DiskClipWriter(baseDir: importDir)
        let exporter = HistoryExporter(store: store2, writer: writer2)
        let first = try exporter.import(from: url)
        let second = try exporter.import(from: url)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0, "duplicate content hash skipped")
        XCTAssertEqual(store2.count(), 1)
    }

    func test_import_InvalidFormatThrows() throws {
        let url = tmp.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: url)
        let exporter = HistoryExporter(store: store, writer: writer)
        XCTAssertThrowsError(try exporter.import(from: url)) { error in
            XCTAssertEqual(error as? HistoryExporter.ImportError, .invalidFormat)
        }
    }

    func test_import_UnsupportedVersionThrows() throws {
        let url = tmp.appendingPathComponent("future.json")
        let bad: [String: Any] = ["version": 999, "items": []]
        let data = try JSONSerialization.data(withJSONObject: bad)
        try data.write(to: url)
        let exporter = HistoryExporter(store: store, writer: writer)
        XCTAssertThrowsError(try exporter.import(from: url)) { error in
            XCTAssertEqual(error as? HistoryExporter.ImportError, .unsupportedVersion)
        }
    }
}
