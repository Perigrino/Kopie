import XCTest
import KopieCore
import AppKit

final class ImageURLTextClassifierTests: XCTestCase {
    func test_imageFileURLs_classified() {
        XCTAssertEqual(ImageURLTextClassifier.classify("https://example.com/photo.png"), .imageURL)
        XCTAssertEqual(ImageURLTextClassifier.classify("https://example.com/a/b/photo.jpeg?w=100#frag"), .imageURL)
        XCTAssertEqual(ImageURLTextClassifier.classify("http://example.com/pic.GIF"), .imageURL)
        XCTAssertEqual(ImageURLTextClassifier.classify("https://cdn.example.com/img/1234.webp?v=2"), .imageURL)
    }

    func test_nonImageText_kept() {
        XCTAssertEqual(ImageURLTextClassifier.classify("hello world"), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("https://example.com/page"), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("https://example.com/img?format=png"), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("ftp://example.com/x.png"), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify(""), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("   "), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("/Users/me/photo.png"), .keep)   // local path, not a URL
    }

    func test_base64DataURI_convertsToData() {
        let png = makePNG()
        let b64 = png.base64EncodedString()
        let uri = "data:image/png;base64,\(b64)"
        guard case .dataImage(let data) = ImageURLTextClassifier.classify(uri) else {
            return XCTFail("expected dataImage")
        }
        XCTAssertEqual(data, png)
    }

    func test_urlSafeAndPercentEncodedBase64_convertsToData() {
        let png = makePNG()
        let b64 = png.base64EncodedString()
        var urlSafe = b64.replacingOccurrences(of: "+", with: "-")
                         .replacingOccurrences(of: "/", with: "_")
        urlSafe = urlSafe.replacingOccurrences(of: "=", with: "%3D")
        let uri = "data:image/png;base64,\(urlSafe)"
        guard case .dataImage(let data) = ImageURLTextClassifier.classify(uri) else {
            return XCTFail("expected dataImage")
        }
        XCTAssertEqual(data, png)
    }

    func test_nonBase64DataURI_kept() {
        XCTAssertEqual(ImageURLTextClassifier.classify("data:image/png,plain-not-base64"), .keep)
        XCTAssertEqual(ImageURLTextClassifier.classify("data:text/plain;base64,aGk="), .keep)
    }

    private func makePNG(_ w: Int = 20, _ h: Int = 20) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemOrange.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}

final class OneTimeCleanupTests: XCTestCase {
    var tmp: URL!
    var store: ClipStore!
    var writer: DiskClipWriter!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("otc_\(UUID().uuidString)")
        store = ClipStore(dir: tmp)
        writer = DiskClipWriter(baseDir: tmp)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    private func insertText(_ s: String, favorite: Bool = false) -> Int64 {
        let item = ClipboardItem(id: 0, kind: .text, createdAt: .now, lastAccessedAt: .now,
                                 isFavorite: favorite, contentHash: "h\(s.hashValue)",
                                 text: s, imageRelPath: nil, thumbRelPath: nil,
                                 fileSize: 0, width: nil, height: nil)
        let id = store.insert(item)
        if favorite { store.setFavorite(id, true) }
        return id
    }

    func test_removesImageURLTextEntries() {
        insertText("https://example.com/photo.png")
        insertText("notes about the design")
        XCTAssertEqual(store.count(), 2)

        let touched = OneTimeCleanup(store: store, writer: writer).run()
        XCTAssertEqual(touched, 1)
        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.query(.init()).first?.text, "notes about the design")
    }

    func test_convertsDataURIToImage() {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 24,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: 24, height: 24).fill()
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:])!
        let id = insertText("data:image/png;base64,\(png.base64EncodedString())")
        _ = OneTimeCleanup(store: store, writer: writer).run()

        let item = store.get(id)!
        XCTAssertEqual(item.kind, .image)
        XCTAssertNil(item.text)
        XCTAssertEqual(item.width, 24)
        XCTAssertEqual(item.height, 24)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(item.imageRelPath!).path))
    }

    func test_keepsFavorites() {
        insertText("https://example.com/photo.png", favorite: true)
        XCTAssertEqual(OneTimeCleanup(store: store, writer: writer).run(), 0)
        XCTAssertEqual(store.count(), 1)
    }

    func test_runsOnlyOnce() {
        insertText("https://example.com/photo.png")
        XCTAssertEqual(OneTimeCleanup(store: store, writer: writer).run(), 1)
        // Marker persisted: a fresh store over the same DB must not re-run.
        let second = ClipStore(dir: tmp)
        XCTAssertEqual(OneTimeCleanup(store: second, writer: writer).run(), 0)
        XCTAssertEqual(second.count(), 0)
    }
}
