import XCTest
import KopieCore
import AppKit

final class ClipboardReaderTests: XCTestCase {
    func png(_ w: Int = 40, _ h: Int = 40) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemRed.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private func withPasteboard(_ body: () -> Void) {
        let b = NSPasteboard.general
        b.clearContents()
        defer { b.clearContents() }
        body()
    }

    func test_pngOnly_isImage() {
        withPasteboard {
            NSPasteboard.general.setData(png(), forType: .png)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .image)
            XCTAssertNotNil(c?.imageData)
        }
    }

    func test_tiffOnly_isImage() {
        withPasteboard {
            let tiff = NSBitmapImageRep(data: png())!.representation(using: .tiff, properties: [:])!
            NSPasteboard.general.setData(tiff, forType: .tiff)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .image)
        }
    }

    /// Copying an image in Safari/Chrome also drops the image URL as plain
    /// text; the image must win so it registers as an image, not a URL.
    func test_pngPlusTextUrl_prefersImage() {
        withPasteboard {
            let b = NSPasteboard.general
            b.setData(png(), forType: .png)
            b.setString("https://example.com/img.png", forType: .string)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .image)
            XCTAssertNotNil(c?.imageData)
        }
    }

    func test_textOnly_isText() {
        withPasteboard {
            NSPasteboard.general.setString("hello", forType: .string)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .text)
            XCTAssertEqual(c?.text, "hello")
        }
    }

    func test_fileURL_isFile() {
        withPasteboard {
            NSPasteboard.general.setString("file:///Users/alice/notes.txt", forType: .fileURL)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .file)
            XCTAssertEqual(c?.filePaths, ["/Users/alice/notes.txt"])
        }
    }

    func test_filenamesType_isFile() {
        withPasteboard {
            let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            NSPasteboard.general.setPropertyList(["/tmp/a.txt", "/tmp/b.txt"], forType: filenames)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .file)
            XCTAssertEqual(c?.filePaths, ["/tmp/a.txt", "/tmp/b.txt"])
        }
    }

    /// A Finder file copy also drops the file's icon as TIFF on the pasteboard.
    /// The file reference must win, otherwise the generic file-type glyph gets
    /// captured as if it were the copied image.
    func test_fileCopyWithIconTiff_prefersFile() {
        withPasteboard {
            let b = NSPasteboard.general
            b.setString("file:///Users/alice/photo.png", forType: .fileURL)
            let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
            b.setPropertyList(["/Users/alice/photo.png"], forType: filenames)
            let tiff = NSBitmapImageRep(data: png())!.representation(using: .tiff, properties: [:])!
            b.setData(tiff, forType: .tiff)
            let c = ClipboardReader.read()
            XCTAssertEqual(c?.clipKind, .file)
            XCTAssertEqual(c?.filePaths, ["/Users/alice/photo.png"])
            XCTAssertNil(c?.imageData)
        }
    }

    func test_emptyPasteboard_isNil() {
        withPasteboard {
            XCTAssertNil(ClipboardReader.read())
        }
    }
}
