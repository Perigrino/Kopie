import XCTest
import AppKit
@testable import KopieCore

final class ImageTextRecognizerTests: XCTestCase {
    /// Renders text into a small PNG so Vision has something real to read.
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

    func test_recognizesRenderedText() {
        let text = ImageTextRecognizer.recognizeText(in: pngWithText("Kopie 2026"))
        XCTAssertNotNil(text)
        XCTAssertEqual(text?.replacingOccurrences(of: " ", with: ""), "Kopie2026")
    }

    func test_blankImageReturnsNil() {
        let img = NSImage(size: NSSize(width: 60, height: 60))
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 60, height: 60).fill()
        img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        XCTAssertNil(ImageTextRecognizer.recognizeText(in: png))
    }

    func test_nonImageDataReturnsNil() {
        XCTAssertNil(ImageTextRecognizer.recognizeText(in: Data("not an image".utf8)))
    }
}
