import Testing
import Foundation
import AppKit
@testable import KopieCore

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

@Suite struct OcrBackfillTests {

    let store: ClipStore
    let writer: DiskClipWriter
    let pipe: CapturePipeline
    let tmp: URL

    init() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ocr_backfill_\(UUID().uuidString)")
        let store = ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp, crypto: nil)
        let pipe = CapturePipeline(store: store, writer: writer)
        self.tmp = tmp
        self.store = store
        self.writer = writer
        self.pipe = pipe
    }

    @Test(.serialized) func cleanup() {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - ClipStore.imagesNeedingOCR

    @Test func test_imagesNeedingOCRReturnsImagesWithoutOCR() throws {
        // Insert 3 image items without OCR (ocrImages = false)
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        var ids: [Int64] = []
        for i in 0..<3 {
            let imgData = pngWithText("test image \(i)")
            let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
            guard case .captured(let id) = r else { Issue.record("expected captured"); return }
            ids.append(id)
        }

        let needing = store.imagesNeedingOCR(limit: 10)
        #expect(needing.count == 3)
        // Should be ordered by created_at ASC
        #expect(needing.map { $0.0 } == ids)
        // Each should have an imageRelPath
        for (_, relPath) in needing {
            #expect(!relPath.isEmpty)
        }
    }

    @Test func test_imagesNeedingOCRRespectsLimit() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        for i in 0..<5 {
            let imgData = pngWithText("limit test \(i)")
            _ = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        }

        let needing = store.imagesNeedingOCR(limit: 2)
        #expect(needing.count == 2)
    }

    @Test func test_imagesNeedingOCRExcludesAlreadyOCRed() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        // Insert 2 without OCR
        let img1 = pngWithText("no ocr 1")
        let r1 = pipe.process(.init(kind: .image(img1), sourceAppID: nil), config: cfg)
        guard case .captured(let id1) = r1 else { Issue.record("expected captured"); return }

        let img2 = pngWithText("no ocr 2")
        let r2 = pipe.process(.init(kind: .image(img2), sourceAppID: nil), config: cfg)
        guard case .captured(let id2) = r2 else { Issue.record("expected captured"); return }

        // Insert 1 with OCR already set
        let img3 = pngWithText("has ocr")
        let r3 = pipe.process(.init(kind: .image(img3), sourceAppID: nil), config: cfg)
        guard case .captured(let id3) = r3 else { Issue.record("expected captured"); return }
        _ = store.updateOCR(id3, "already has ocr")

        let needing = store.imagesNeedingOCR(limit: 10)
        #expect(needing.count == 2)
        #expect(Set(needing.map { $0.0 }) == Set([id1, id2]))
    }

    @Test func test_imagesNeedingOCRExcludesSensitiveImages() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false
        cfg.sensitiveEnabledRules = ["known_prefix"]
        cfg.sensitivePolicy = .mask

        // Regular image
        let img1 = pngWithText("regular image")
        let r1 = pipe.process(.init(kind: .image(img1), sourceAppID: nil), config: cfg)
        guard case .captured(let id1) = r1 else { Issue.record("expected captured"); return }

        // Sensitive image — mark as sensitive after insert
        let img2 = pngWithText("secret image")
        let r2 = pipe.process(.init(kind: .image(img2), sourceAppID: nil), config: cfg)
        guard case .captured(let id2) = r2 else { Issue.record("expected captured"); return }
        _ = store.setSensitive(id2, true)

        let needing = store.imagesNeedingOCR(limit: 10)
        #expect(needing.count == 1)
        #expect(needing.first?.0 == id1)
    }

    @Test func test_imagesNeedingOCRExcludesNonImageKinds() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        // Insert text item
        _ = pipe.process(.init(kind: .text("just text"), sourceAppID: nil), config: cfg)

        // Insert image item
        let img = pngWithText("an image")
        let r = pipe.process(.init(kind: .image(img), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { Issue.record("expected captured"); return }

        let needing = store.imagesNeedingOCR(limit: 10)
        #expect(needing.count == 1)
        #expect(needing.first?.0 == id)
    }

    // MARK: - OcrBackfill.backfill

    @Test func test_backfillIndexesAllImagesInBatch() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        let ids = (0..<3).map { i -> Int64 in
            let imgData = pngWithText("backfill test item \(i)")
            let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
            guard case .captured(let id) = r else { Issue.record("expected captured"); return -1 }
            return id
        }

        // Initially not searchable
        for _ in ids {
            #expect(store.query(.init(textQuery: "backfill")).count == 0)
        }

        // Run backfill
        let result = OcrBackfill.backfill(store: store, writer: writer, batchSize: 10, now: Date())

        // All should be processed
        #expect(result.done == 3)
        #expect(result.total == 3)
        #expect(result.isComplete == true)
        #expect(result.error == nil)

        // All should now be searchable by "item" (substring that Vision recognizes in all)
        #expect(store.query(.init(textQuery: "item")).count == 3)
        // And each should be uniquely searchable by their index (Vision reads "item 0" as "item O" etc.)
        // So we search for "item" and verify we get 3 results
        let allResults = store.query(.init(textQuery: "item"))
        #expect(allResults.count == 3)
    }

    @Test func test_backfillIsIdempotent() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        let imgData = pngWithText("idempotent test")
        let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { Issue.record("expected captured"); return }

        // First backfill run
        let result1 = OcrBackfill.backfill(store: store, writer: writer, batchSize: 10, now: Date())
        #expect(result1.done == 1)
        #expect(result1.total == 1)
        #expect(result1.isComplete == true)

        // Second backfill run — should do nothing
        let result2 = OcrBackfill.backfill(store: store, writer: writer, batchSize: 10, now: Date())
        #expect(result2.done == 0)
        #expect(result2.total == 1) // Total still reflects the scanned row
        #expect(result2.isComplete == true)
        #expect(result2.error == nil)

        // Still searchable
        #expect(store.query(.init(textQuery: "idempotent")).count == 1)
    }

    @Test func test_backfillReachesCompletionAndReportsProgress() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        // Create 100 images
        for i in 0..<100 {
            let imgData = pngWithText("progress test \(i)")
            _ = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        }

        // Run with small batch size to test progress
        let result = OcrBackfill.backfill(store: store, writer: writer, batchSize: 25, now: Date())

        #expect(result.done == 100)
        #expect(result.total == 100)
        #expect(result.isComplete == true)
        #expect(result.error == nil)

        // All searchable
        #expect(store.query(.init(textQuery: "progress test")).count == 100)
    }

    @Test func test_backfillSkipsAlreadyOCRed() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        // Pre-tag 2 rows with OCR text
        var preOCRIds: [Int64] = []
        for i in 0..<2 {
            let imgData = pngWithText("pre ocr item \(i)")
            let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
            guard case .captured(let id) = r else { Issue.record("expected captured"); return }
            _ = store.updateOCR(id, "pre ocr item \(i)")
            preOCRIds.append(id)
        }

        // Leave 3 null
        var nullIds: [Int64] = []
        for i in 0..<3 {
            let imgData = pngWithText("null ocr item \(i)")
            let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
            guard case .captured(let id) = r else { Issue.record("expected captured"); return }
            nullIds.append(id)
        }

        let result = OcrBackfill.backfill(store: store, writer: writer, batchSize: 10, now: Date())

        #expect(result.done == 3) // Only the 3 without OCR
        #expect(result.total == 5) // But total includes all 5 scanned
        #expect(result.isComplete == true)

        // Pre-OCR items still searchable
        for i in 0..<2 {
            #expect(store.query(.init(textQuery: "pre ocr item \(i)")).count == 1)
        }
        // Null items now searchable by "item" substring
        #expect(store.query(.init(textQuery: "null ocr item")).count == 3)
    }

    @Test func test_backfillDoesNotOCRDeleteFiles() throws {
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        cfg.ignoreDuplicates = false

        var relPaths: [String] = []
        for i in 0..<5 {
            let imgData = pngWithText("file test \(i)")
            let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
            guard case .captured(let id) = r else { Issue.record("expected captured"); return }
            if let item = store.get(id), let rel = item.imageRelPath {
                relPaths.append(rel)
            }
        }

        // All image files should exist before backfill
        for rel in relPaths {
            let data = try writer.imageData(relPath: rel)
            #expect(data.count > 0)
        }

        _ = OcrBackfill.backfill(store: store, writer: writer, batchSize: 10, now: Date())

        // All image files should still exist after backfill
        for rel in relPaths {
            let data = try writer.imageData(relPath: rel)
            #expect(data.count > 0)
        }
    }
}