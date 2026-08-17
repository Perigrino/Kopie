import XCTest
import KopieCore
import AppKit

final class CapturePipelineTests: XCTestCase {
    var store: ClipStore!
    var writer: DiskClipWriter!
    var pipe: CapturePipeline!
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cp_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
        writer = DiskClipWriter(baseDir: tmp)
        pipe = CapturePipeline(store: store, writer: writer)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func png(_ w: Int = 40, _ h: Int = 40) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemRed.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func test_capturesText() {
        let r = pipe.process(.init(kind: .text("hello"), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        XCTAssertEqual(store.get(id)?.text, "hello")
    }
    func test_pausedDrops() {
        var c = CaptureConfig(); c.paused = true
        XCTAssertEqual(pipe.process(.init(kind: .text("x"), sourceAppID: nil), config: c), .paused)
        XCTAssertEqual(store.count(), 0)
    }
    func test_disabledKindDrops() {
        var c = CaptureConfig(); c.saveText = false
        XCTAssertEqual(pipe.process(.init(kind: .text("x"), sourceAppID: nil), config: c), .disabledKind)
    }
    func test_excludedAppDrops() {
        var c = CaptureConfig(); c.excludedAppIDs = ["com.1password"]
        XCTAssertEqual(pipe.process(.init(kind: .text("sec"), sourceAppID: "com.1password"), config: c), .excludedApp)
    }
    func test_emptyTextDrops() {
        XCTAssertEqual(pipe.process(.init(kind: .text("   "), sourceAppID: nil), config: .default), .empty)
    }
    func test_duplicateSkipped() {
        _ = pipe.process(.init(kind: .text("same"), sourceAppID: nil), config: .default)
        XCTAssertEqual(pipe.process(.init(kind: .text("same"), sourceAppID: nil), config: .default), .duplicate)
        XCTAssertEqual(store.count(), 1)
    }
    func test_duplicateDisabledWhenOff() {
        var c = CaptureConfig(); c.ignoreDuplicates = false
        _ = pipe.process(.init(kind: .text("same"), sourceAppID: nil), config: c)
        _ = pipe.process(.init(kind: .text("same"), sourceAppID: nil), config: c)
        XCTAssertEqual(store.count(), 2)
    }
    func test_capturesImage_writesFilesAndDims() {
        let r = pipe.process(.init(kind: .image(png()), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        let it = store.get(id)!
        XCTAssertEqual(it.kind, .image)
        XCTAssertEqual(it.width, 40)
        XCTAssertNotNil(it.imageRelPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(it.imageRelPath!).path))
    }
    func test_trimEnforced() {
        var c = CaptureConfig(); c.maxItems = 3
        for i in 0..<5 { _ = pipe.process(.init(kind: .text("t\(i)"), sourceAppID: nil), config: c) }
        XCTAssertEqual(store.count(), 3)
    }
    func test_capturesFiles_storesPathsAndSize() throws {
        let a = tmp.appendingPathComponent("file-a.txt")
        let b = tmp.appendingPathComponent("file-b.txt")
        try Data("hello".utf8).write(to: a)
        try Data("world!".utf8).write(to: b)
        let r = pipe.process(.init(kind: .files([a.path, b.path]), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        let it = store.get(id)!
        XCTAssertEqual(it.kind, .file)
        XCTAssertEqual(it.filePaths, [a.path, b.path])
        XCTAssertEqual(it.fileSize, 11)
    }
    func test_singleImageFileCopy_becomesImage() throws {
        // Finder copies don't put image bytes on the pasteboard — only the file
        // reference. A single copied image file must register as a real image
        // item so the app can display a thumbnail.
        let imgURL = tmp.appendingPathComponent("photo.png")
        try png().write(to: imgURL)
        let r = pipe.process(.init(kind: .files([imgURL.path]), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        let it = store.get(id)!
        XCTAssertEqual(it.kind, .image)
        XCTAssertEqual(it.width, 40)
        XCTAssertNotNil(it.imageRelPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(it.imageRelPath!).path))
        XCTAssertEqual(it.filePaths, nil)
    }
    func test_multiFileCopyWithImage_staysFile() throws {
        let imgURL = tmp.appendingPathComponent("a.png")
        let txtURL = tmp.appendingPathComponent("b.txt")
        try png().write(to: imgURL)
        try Data("x".utf8).write(to: txtURL)
        let r = pipe.process(.init(kind: .files([imgURL.path, txtURL.path]), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        let it = store.get(id)!
        XCTAssertEqual(it.kind, .file)
        XCTAssertEqual(it.filePaths?.count, 2)
    }
    func test_nonImageFileCopy_staysFile() throws {
        let a = tmp.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: a)
        let r = pipe.process(.init(kind: .files([a.path]), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        XCTAssertEqual(store.get(id)?.kind, .file)
    }
    func test_unreadableImageFileCopy_fallsBackToFile() {
        // A .png path that no longer exists (or can't be decoded) must still
        // register as a file item instead of erroring out.
        let missing = tmp.appendingPathComponent("gone.png").path
        let r = pipe.process(.init(kind: .files([missing]), sourceAppID: nil), config: .default)
        guard case .captured(let id) = r else { return XCTFail("expected captured, got \(r)") }
        XCTAssertEqual(store.get(id)?.kind, .file)
    }
    func test_filesDisabledWhenOff() {
        var c = CaptureConfig(); c.saveFiles = false
        XCTAssertEqual(pipe.process(.init(kind: .files(["/tmp/x"]), sourceAppID: nil), config: c), .disabledKind)
    }
    func test_differentTextThenImageBothCaptured() {
        _ = pipe.process(.init(kind: .text("some text"), sourceAppID: nil), config: .default)
        let r = pipe.process(.init(kind: .image(png()), sourceAppID: nil), config: .default)
        guard case .captured = r else { return XCTFail("expected captured, got \(r)") }
        XCTAssertEqual(store.count(), 2)
    }
}
