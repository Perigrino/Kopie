import XCTest
import KopieCore
import AppKit

final class ThumbnailTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cw_\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    // Builds a PNG with exact pixel dimensions, independent of display scale.
    func png(_ w: Int, _ h: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func test_writeImage_reportsDimensionsAndFiles() throws {
        let writer = DiskClipWriter(baseDir: tmp)
        let info = try writer.writeImage(png(640, 320), hashHex: "abc123")
        let imgURL = tmp.appendingPathComponent(info.imageRelPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imgURL.path))
        XCTAssertEqual(info.width, 640)
        XCTAssertEqual(info.height, 320)
        XCTAssertGreaterThan(info.byteSize, 0)
        let thumb = writer.loadThumb(relPath: info.thumbRelPath)
        XCTAssertNotNil(thumb)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(info.thumbRelPath!).path))
    }

    func test_noThumbForSmallImage() throws {
        let writer = DiskClipWriter(baseDir: tmp)
        let info = try writer.writeImage(png(40, 40), hashHex: "small")
        XCTAssertNil(info.thumbRelPath)
    }

    func test_downscalesLargeImage() throws {
        let writer = DiskClipWriter(baseDir: tmp)
        let info = try writer.writeImage(png(6000, 6000), hashHex: "big")
        XCTAssertLessThanOrEqual(max(info.width, info.height), 4096)
    }

    func test_imageDataRoundtrip() throws {
        let writer = DiskClipWriter(baseDir: tmp)
        let data = png(50, 50)
        let info = try writer.writeImage(data, hashHex: "rt")
        let read = try writer.imageData(relPath: info.imageRelPath)
        XCTAssertFalse(read.isEmpty)
        XCTAssertNotNil(NSImage(data: read))
    }

    func test_unreadableImageThrows() {
        let writer = DiskClipWriter(baseDir: tmp)
        XCTAssertThrowsError(try writer.writeImage(Data([1, 2, 3, 4]), hashHex: "bad")) { err in
            XCTAssertEqual(err as? ClipError, .unreadableImage)
        }
    }

    // MARK: - At-rest encryption

    func test_imageFilesEncryptedAtRest() throws {
        let writer = DiskClipWriter(baseDir: tmp, crypto: InMemoryHistoryCrypto())
        let data = png(40, 40)
        let info = try writer.writeImage(data, hashHex: "enc1")

        // On disk: magic header, no PNG signature, no plaintext bytes.
        let raw = try Data(contentsOf: tmp.appendingPathComponent(info.imageRelPath))
        XCTAssertTrue(raw.starts(with: Data("KPE1".utf8)))
        XCTAssertNil(raw.range(of: Data([0x89, 0x50, 0x4E, 0x47])))

        // Reads decrypt transparently (the PNG is re-encoded on write, so
        // assert it's decodable, not byte-identical).
        let read = try writer.imageData(relPath: info.imageRelPath)
        XCTAssertFalse(read.isEmpty)
        XCTAssertNotNil(NSImage(data: read))
        XCTAssertNotNil(writer.loadThumb(relPath: info.imageRelPath))
    }

    func test_largeImageThumbnailAlsoEncrypted() throws {
        let writer = DiskClipWriter(baseDir: tmp, crypto: InMemoryHistoryCrypto())
        let info = try writer.writeImage(png(640, 320), hashHex: "enc2")
        XCTAssertNotNil(info.thumbRelPath)
        let rawThumb = try Data(contentsOf: tmp.appendingPathComponent(info.thumbRelPath!))
        XCTAssertTrue(rawThumb.starts(with: Data("KPE1".utf8)))
        XCTAssertNotNil(writer.loadThumb(relPath: info.thumbRelPath))
    }

    func test_legacyPlaintextImageFileStillReadable() throws {
        // Pre-encryption PNG on disk (no magic header) must still load.
        let dir = tmp.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plain = png(40, 40)
        try plain.write(to: dir.appendingPathComponent("legacy.png"))
        let writer = DiskClipWriter(baseDir: tmp, crypto: InMemoryHistoryCrypto())
        XCTAssertEqual(try writer.imageData(relPath: "images/legacy.png"), plain)
        XCTAssertNotNil(writer.loadThumb(relPath: "images/legacy.png"))
        // The read-through migration re-encrypts the file in place.
        let migrated = try Data(contentsOf: dir.appendingPathComponent("legacy.png"))
        XCTAssertTrue(migrated.starts(with: Data("KPE1".utf8)))
    }
}
