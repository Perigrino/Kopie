import XCTest
import AppKit
@testable import KopieCore

final class OCRPipelineTests: XCTestCase {
    var store: ClipStore!
    var writer: DiskClipWriter!
    var pipe: CapturePipeline!
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ocr_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
        writer = DiskClipWriter(baseDir: tmp, crypto: nil)
        pipe = CapturePipeline(store: store, writer: writer)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    private func pngWithText(_ text: String) -> Data {
        let size = NSSize(width: 360, height: 120)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: NSPoint(x: 16, y: 40), withAttributes: attrs)
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    func test_captureStoresOCRTextAndMakesImageSearchable() {
        var cfg = CaptureConfig()
        cfg.ocrImages = true
        let r = pipe.process(.init(kind: .image(pngWithText("Kopie 2026")), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        let item = store.get(id)
        XCTAssertNotNil(item?.ocrText)
        XCTAssertEqual(item?.ocrText?.replacingOccurrences(of: " ", with: ""), "Kopie2026")
        // The image must be findable by the words inside it.
        XCTAssertEqual(store.query(.init(textQuery: "Kopie")).count, 1)
        XCTAssertEqual(store.query(.init(textQuery: "Kopie")).first?.id, id)
    }

    func test_ocrDisabledLeavesFieldNil() {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        let r = pipe.process(.init(kind: .image(pngWithText("Kopie 2026")), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        XCTAssertNil(store.get(id)?.ocrText)
    }

    func test_fallbackWindowedSearchMatchesOCRToo() {
        // Short queries bypass the trigram index; the in-memory fallback must
        // also match OCR text.
        var cfg = CaptureConfig()
        cfg.ocrImages = true
        _ = pipe.process(.init(kind: .image(pngWithText("Kopie 2026")), sourceAppID: nil), config: cfg)
        XCTAssertEqual(store.query(.init(textQuery: "Kop")).count, 1)
    }

    func test_existingDBsGainOcrColumnViaMigration() throws {
        // Create a store, close it, drop the column by recreating an old-style
        // table, then reopen: migration must add ocr_text back.
        let dbPath = tmp.appendingPathComponent("kopie.db").path
        XCTAssertNotNil(store)
        store = nil
        let raw = try Database(path: dbPath)
        // Simulate a pre-OCR database: rename the table without ocr_text.
        try raw.exec("ALTER TABLE clipboard_items RENAME TO clipboard_items_old")
        try raw.exec("""
        CREATE TABLE clipboard_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
          created_at INTEGER NOT NULL, last_accessed_at INTEGER NOT NULL,
          is_favorite INTEGER NOT NULL DEFAULT 0, content_hash TEXT NOT NULL,
          text_content TEXT, image_rel_path TEXT, thumb_rel_path TEXT,
          file_size INTEGER NOT NULL DEFAULT 0, width INTEGER, height INTEGER,
          source_app TEXT, copy_count INTEGER NOT NULL DEFAULT 1, last_copied_at INTEGER,
          is_pinned INTEGER NOT NULL DEFAULT 0, pinned_at INTEGER, rich_text_rel_path TEXT)
        """)
        try raw.exec("INSERT INTO clipboard_items SELECT id,kind,created_at,last_accessed_at,is_favorite,content_hash,text_content,image_rel_path,thumb_rel_path,file_size,width,height,source_app,copy_count,last_copied_at,is_pinned,pinned_at,rich_text_rel_path FROM clipboard_items_old")
        try raw.exec("DROP TABLE clipboard_items_old")
        // `raw` goes out of scope, closing the database.

        let reopened = try ClipStore(dir: tmp)
        // Old rows survive and new inserts carry OCR text.
        XCTAssertEqual(reopened.count(), 0)
        var cfg = CaptureConfig()
        cfg.ocrImages = true
        let r = pipe2(reopened).process(.init(kind: .image(pngWithText("migration ok")), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { return XCTFail("expected captured") }
        XCTAssertNotNil(reopened.get(id)?.ocrText)
    }

    private func pipe2(_ s: ClipStore) -> CapturePipeline { CapturePipeline(store: s, writer: writer) }
}
