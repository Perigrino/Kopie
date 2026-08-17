import XCTest
import KopieCore
import AppKit

final class MonitorDebounceTests: XCTestCase {
    var captured: [String] = []
    var monitor: ClipboardMonitor!
    override func setUp() {
        captured = []
        monitor = ClipboardMonitor(reader: {
            NSPasteboard.general.string(forType: .string).map { CapturedContent(kind: .text($0), sourceAppID: nil) }
        }, handler: { [self] c in if let t = c.text { captured.append(t) } })
    }

    func test_changeCaptured() {
        let b = NSPasteboard.general
        b.clearContents(); b.setString("m-test-1", forType: .string)
        monitor.tick()
        XCTAssertEqual(captured, ["m-test-1"])
    }
    func test_suppressionSkipsOwnWrite() {
        let b = NSPasteboard.general
        b.clearContents(); b.setString("first-real", forType: .string)
        monitor.tick()
        XCTAssertEqual(captured, ["first-real"])

        monitor.beginSuppression()
        b.clearContents(); b.setString("own-write", forType: .string)
        monitor.tick() // change detected but suppressed
        XCTAssertEqual(captured, ["first-real"])

        b.clearContents(); b.setString("second-real", forType: .string)
        monitor.tick()
        XCTAssertEqual(captured, ["first-real", "second-real"])
    }
    func test_noChangeDoesNothing() {
        let b = NSPasteboard.general
        b.clearContents(); b.setString("stable", forType: .string)
        monitor.tick()
        monitor.tick() // same changeCount
        XCTAssertEqual(captured, ["stable"])
    }
}
