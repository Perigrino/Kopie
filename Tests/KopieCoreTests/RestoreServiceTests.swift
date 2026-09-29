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
    func test_restoreFile_setsFileURLOnPasteboard() {
        let b = NSPasteboard.general
        b.clearContents()
        defer { b.clearContents() }
        let item = ClipboardItem(id: 3, kind: .file, createdAt: .now, lastAccessedAt: .now, isFavorite: false,
                                 contentHash: "f1", text: "/tmp/kopie-file.txt", imageRelPath: nil,
                                 thumbRelPath: nil, fileSize: 0, width: nil, height: nil)
        RestoreService().restore(item, writer: DiskClipWriter(baseDir: tmp))
        let url = b.propertyList(forType: .fileURL) as? String
        XCTAssertEqual(url, "file:///tmp/kopie-file.txt")
    }
    func test_onAboutToWrite_calledBeforeWrite() {
        let svc = RestoreService()
        var fired = false
        svc.onAboutToWrite = { fired = true }
        svc.restore(textItem("x"), writer: DiskClipWriter(baseDir: tmp))
        XCTAssertTrue(fired)
    }

    func richItem(_ w: DiskClipWriter, plainOnly: Bool) -> ClipboardItem {
        let rtf = Data("{\\rtf1\\ansi Hello \\b Rich \\b0 World}".utf8)
        let rel = try! w.writeRichText(rtf, hashHex: "rich1")
        return ClipboardItem(id: 9, kind: .text, createdAt: .now, lastAccessedAt: .now, isFavorite: false,
                             contentHash: "rich1", text: "Hello Rich World", imageRelPath: nil,
                             thumbRelPath: nil, fileSize: 0, width: nil, height: nil,
                             richTextRelPath: rel)
    }

    func test_restoreRichText_stagesRTFFlavor() throws {
        let w = DiskClipWriter(baseDir: tmp)
        RestoreService().restore(richItem(w, plainOnly: false), writer: w)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello Rich World")
        XCTAssertNotNil(NSPasteboard.general.data(forType: .rtf))
    }

    func test_restorePlainTextOnly_stripsRichFlavor() throws {
        let w = DiskClipWriter(baseDir: tmp)
        RestoreService().restore(richItem(w, plainOnly: true), writer: w, plainTextOnly: true)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Hello Rich World")
        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))
    }
}
