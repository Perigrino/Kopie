import XCTest
import KopieCore
import AppKit

final class ThumbnailGeneratorTests: XCTestCase {
    var tmp: URL!
    var writer: DiskClipWriter!
    var gen: ThumbnailGenerator!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        writer = DiskClipWriter(baseDir: tmp)
        gen = ThumbnailGenerator(baseDir: tmp)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func bigImageData(_ w: Int = 512, _ h: Int = 512) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func test_generatesThumbnail() throws {
        let data = bigImageData()
        let hash = Hashing.sha256(data)
        let info = try writer.writeImage(data, hashHex: hash)

        let rel = gen.generateThumbnailIfNeeded(imageRelPath: info.imageRelPath, hashHex: hash)
        XCTAssertEqual(rel, "thumbs/\(hash).png")
        let exists = FileManager.default.fileExists(atPath: tmp.appendingPathComponent(rel!).path)
        XCTAssertTrue(exists, "thumbnail file written")
    }

    func test_isIdempotent() throws {
        let data = bigImageData()
        let hash = Hashing.sha256(data)
        let info = try writer.writeImage(data, hashHex: hash)

        let first = gen.generateThumbnailIfNeeded(imageRelPath: info.imageRelPath, hashHex: hash)
        let second = gen.generateThumbnailIfNeeded(imageRelPath: info.imageRelPath, hashHex: hash)
        XCTAssertEqual(first, second)
    }

    func test_corruptedImageReturnsNil() throws {
        // A corrupted/missing image file must not generate a thumbnail.
        let missing = "images/does-not-exist.png"
        let rel = gen.generateThumbnailIfNeeded(imageRelPath: missing, hashHex: "deadbeef")
        XCTAssertNil(rel)
    }
}
