import XCTest
import KopieCore

/// Regression coverage for issue #4: selecting an item in the main window and
/// copying it back re-sorts the list under the user's cursor.
///
/// The list is ordered by `last_accessed_at DESC`, and `bumpAccessed` stamps
/// that column on every copy-back. Without an anchor, the row the user just
/// clicked jumps to the top, and selection looks broken: the highlight lands
/// back on whatever is now at the top while the row under the pointer is a
/// different item.
final class CopyBackReorderTests: XCTestCase {
    var store: ClipStore!
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("reorder_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// Ages an item by `age` seconds in both the access and creation columns, so
    /// insertion order alone doesn't decide the listing.
    private func seed(_ text: String, age: TimeInterval) -> Int64 {
        let when = Date.now.addingTimeInterval(-age)
        let it = ClipboardItem(id: 0, kind: .text, createdAt: when, lastAccessedAt: when,
                               isFavorite: false, contentHash: "h_\(text)",
                               text: text, imageRelPath: nil, thumbRelPath: nil,
                               fileSize: 0, width: nil, height: nil)
        return store.insert(it)
    }

    /// The ordering the main window's list uses.
    private func listedOrder() -> [Int64] { store.query(.init()).map(\.id) }

    /// Copying an item back must not change the list's order. A reorder here is
    /// what makes a freshly-clicked row appear to refuse selection.
    func test_bumpAccessed_doesNotReorderList() throws {
        let top = seed("top", age: 0)
        let middle = seed("middle", age: 60)
        let bottom = seed("bottom", age: 120)
        XCTAssertEqual(listedOrder(), [top, middle, bottom])

        // Copy the bottom item back, the way MainView.copy(_:) does.
        store.bumpAccessed(bottom)

        XCTAssertEqual(listedOrder(), [top, middle, bottom],
                       "copying an item back re-sorted the list; the row just clicked jumps to the top")
    }

    /// Repeated copy-backs of the same item must be idempotent for ordering.
    func test_repeatedCopyBack_keepsOrder() throws {
        let a = seed("a", age: 0)
        let b = seed("b", age: 60)
        let before = listedOrder()
        for _ in 0..<5 { store.bumpAccessed(b) }
        XCTAssertEqual(listedOrder(), before, "repeated copy-backs reshuffled the list")
        XCTAssertEqual(listedOrder(), [a, b])
    }

    /// Pinning is an explicit user action and is allowed to reorder.
    func test_pinStillReorders() throws {
        let bottom = seed("bottom", age: 120)
        let _ = seed("top", age: 0)
        store.setPinned(bottom, true)
        XCTAssertEqual(listedOrder().first, bottom, "pinning should still move an item to the top")
    }
}
