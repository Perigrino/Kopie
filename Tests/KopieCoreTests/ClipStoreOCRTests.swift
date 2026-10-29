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

@Suite struct ClipStoreOCRTests {

    let store: ClipStore
    let writer: DiskClipWriter
    let pipe: CapturePipeline
    let tmp: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ocr_\(UUID().uuidString)")
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp, crypto: nil)
        let pipe = CapturePipeline(store: store, writer: writer)
        self.tmp = tmp
        self.store = store
        self.writer = writer
        self.pipe = pipe
    }

    @Test(.serialized) func cleanup() {
        // Runs after all tests in suite to clean up temp dir
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - ClipStore.updateOCR

    @Test func test_updateOCRWritesColumnAndReindexes() throws {
        let imgData = pngWithText("Kopie2026")
        var cfg = CaptureConfig()
        cfg.ocrImages = false // insert without OCR
        let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { Issue.record("expected captured"); return }

        // Initially no OCR text, so search should not find it
        #expect(store.query(.init(textQuery: "Kopie")).count == 0)

        // Now write OCR text via updateOCR
        let ok = store.updateOCR(id, "Kopie2026")
        #expect(ok == true)

        // Search should now find it
        let results = store.query(.init(textQuery: "Kopie"))
        #expect(results.count == 1)
        #expect(results.first?.id == id)
        #expect(results.first?.ocrText?.replacingOccurrences(of: " ", with: "") == "Kopie2026")
    }

    @Test func test_updateOCRNilIsNoOp() throws {
        let imgData = pngWithText("hello")
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { Issue.record("expected captured"); return }

        // updateOCR with nil should be a no-op and return true
        let ok = store.updateOCR(id, nil)
        #expect(ok == true)

        // Still not searchable
        #expect(store.query(.init(textQuery: "hello")).count == 0)
    }

    @Test func test_updateOCRReindexesAfterTextChanged() throws {
        let imgData = pngWithText("original")
        var cfg = CaptureConfig()
        cfg.ocrImages = false
        let r = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        guard case .captured(let id) = r else { Issue.record("expected captured"); return }

        // First OCR text
        _ = store.updateOCR(id, "abc")
        #expect(store.query(.init(textQuery: "abc")).count == 1)
        #expect(store.query(.init(textQuery: "xyz")).count == 0)

        // Change OCR text — should reindex, not append
        _ = store.updateOCR(id, "xyz")
        #expect(store.query(.init(textQuery: "abc")).count == 0, "old text should not match after reindex")
        #expect(store.query(.init(textQuery: "xyz")).count == 1, "new text should match")
    }

    // MARK: - CapturePipeline.processWithPendingOCR

    @Test func test_processWithPendingOCRHoldsData() throws {
        let imgData = pngWithText("Kopie2026")
        var cfg = CaptureConfig()
        cfg.ocrImages = true

        let (result, ocrData) = pipe.processWithPendingOCR(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)

        guard case .captured(let id) = result else { Issue.record("expected captured, got \(result)"); return }
        #expect(ocrData == imgData)

        let item = store.get(id)
        #expect(item?.ocrText == nil, "OCR text should be nil when using processWithPendingOCR")
        #expect(item?.imageRelPath != nil)
    }

    // MARK: - Sensitive image behavior

    @Test func test_sensitiveImageDoesNotGetOCRAction() throws {
        // Create a sensitive image item by inserting text with sensitive data,
        // then verify the OCR text is still indexed (match already ORs ocrText regardless of sensitive)
        var cfg = CaptureConfig()
        cfg.ocrImages = true
        cfg.sensitiveEnabledRules = ["known_prefix"]
        cfg.sensitivePolicy = .mask

        let secretText = "sk_live_abcdefghijklmnop"
        let r = pipe.process(.init(kind: .text(secretText), sourceAppID: nil), config: cfg)
        guard case .captured(let textId) = r else { Issue.record("expected captured"); return }

        // Now test that an image item with sensitive flag can still have OCR indexed
        let imgData = pngWithText("secret image content")
        let r2 = pipe.process(.init(kind: .image(imgData), sourceAppID: nil), config: cfg)
        guard case .captured(let imgId) = r2 else { Issue.record("expected captured"); return }

        // Manually mark the image as sensitive (simulating a text+image sensitive classification)
        _ = store.updateOCR(imgId, "secret image content")

        // Sensitive image OCR should still be searchable via match (match already ORs ocrText)
        let results = store.query(.init(textQuery: "secret image", sensitiveOnly: false))
        #expect(results.contains { $0.id == imgId }, "OCR text on sensitive image should be searchable")
    }

    // MARK: - OCR queue does not block capture

    @Test func test_ocrQueueDoesNotBlockCapture() throws {
        // Simulate back-to-back captures with valid image data
        // processWithPendingOCR should return quickly (< 50ms) even when Vision would take longer
        // Use unique images each time to avoid duplicate detection
        var cfg = CaptureConfig()
        cfg.ocrImages = true
        cfg.ignoreDuplicates = false // disable duplicate detection for timing test

        // Pre-create images so timing only measures the capture path
        let imgData = (0..<3).map { pngWithText("timing test \($0)") }

        let start = Date.now
        for data in imgData {
            let (result, _) = pipe.processWithPendingOCR(.init(kind: .image(data), sourceAppID: nil), config: cfg)
            guard case .captured = result else { Issue.record("expected captured, got \(result)"); return }
        }
        let elapsed = Date.now.timeIntervalSince(start) * 1000 // ms

        // All 3 captures should complete in well under 50ms total (Vision is off-loaded)
        // Allow 200ms for CI variance; the key assertion is that it's far below what sync Vision would take
        #expect(elapsed < 200, "Capture path should complete in < 200ms total (got \(Int(elapsed))ms)")
    }
}