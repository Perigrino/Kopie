import XCTest
import KopieCore
import AppKit

final class RestoreServiceTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rs_\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func textItem(_ s: String) -> ClipboardItem {
        ClipboardItem(id: 1, kind: .text, createdAt: .now, lastAccessedAt: .now, isFavorite: false,
                      contentHash: "h", text: s, imageRelPath: nil, thumbRelPath: nil, fileSize: 0,
                      width: nil, height: nil)
    }
    func png(_ w: Int = 30, _ h: Int = 30) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemGreen.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func test_restoreText_setsPasteboard() {
        let svc = RestoreService()
        svc.restore(textItem("restored value"), writer: DiskClipWriter(baseDir: tmp))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "restored value")
    }
    func test_restoreImage_setsPasteboardImage() throws {
        let w = DiskClipWriter(baseDir: tmp)
        let info = try w.writeImage(png(), hashHex: "im1")
        let item = ClipboardItem(id: 2, kind: .image, createdAt: .now, lastAccessedAt: .now, isFavorite: false,
                                 contentHash: "im1", text: nil, imageRelPath: info.imageRelPath,
                                 thumbRelPath: info.thumbRelPath, fileSize: info.byteSize,
                                 width: info.width, height: info.height)
        RestoreService().restore(item, writer: w)
        XCTAssertNotNil(NSPasteboard.general.data(forType: .png) ?? NSPasteboard.general.data(forType: .tiff))
    }
    func test_onAboutToWrite_calledBeforeWrite() {
        let svc = RestoreService()
        var fired = false
        svc.onAboutToWrite = { fired = true }
        svc.restore(textItem("x"), writer: DiskClipWriter(baseDir: tmp))
        XCTAssertTrue(fired)
    }
}
