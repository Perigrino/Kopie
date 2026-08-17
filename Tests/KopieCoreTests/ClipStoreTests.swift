import XCTest
import KopieCore

final class ClipStoreTests: XCTestCase {
    var store: ClipStore!
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("store_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func item(_ kind: ClipKind, _ text: String? = nil, _ age: TimeInterval = 0, fav: Bool = false) -> ClipboardItem {
        let now = Date.now.addingTimeInterval(-age)
        return ClipboardItem(id: 0, kind: kind, createdAt: now, lastAccessedAt: now,
                             isFavorite: fav, contentHash: "h\(text ?? "img")\(Int(age))",
                             text: text, imageRelPath: nil, thumbRelPath: nil,
                             fileSize: 0, width: nil, height: nil)
    }

    func test_insertAndQuery_count() throws {
        _ = store.insert(item(.text, "older"))
        _ = store.insert(item(.image, nil, 0))
        _ = store.insert(item(.text, "newest"))
        XCTAssertEqual(store.query(.init()).count, 3)
    }
    func test_searchByTypeAndText() throws {
        _ = store.insert(item(.text, "apple pie"))
        _ = store.insert(item(.text, "banana split"))
        _ = store.insert(item(.image))
        XCTAssertEqual(store.query(.init(kind: .image)).count, 1)
        XCTAssertEqual(store.query(.init(textQuery: "apple")).count, 1)
        XCTAssertEqual(store.query(.init(textQuery: "apple")).first?.text, "apple pie")
    }
    func test_favoritesFilter() throws {
        _ = store.insert(item(.text, "fav", fav: true))
        _ = store.insert(item(.text, "notfav"))
        XCTAssertEqual(store.query(.init(favoritesOnly: true)).count, 1)
    }
    func test_latestHash() throws {
        XCTAssertNil(store.latestHash())
        _ = store.insert(item(.text, "first"))
        XCTAssertEqual(store.latestHash(), "hfirst0")
    }
    func test_favoriteAndDeleteAndClear() throws {
        let a = store.insert(item(.text, "a"))
        let b = store.insert(item(.text, "b"))
        store.setFavorite(a, true)
        XCTAssertEqual(store.get(a)?.isFavorite, true)
        store.delete([b])
        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.clearAll(), 1)
        XCTAssertEqual(store.count(), 0)
    }
    func test_bumpAccessed() throws {
        let a = store.insert(item(.text, "a"))
        store.bumpAccessed(a, Date.now.addingTimeInterval(500))
        XCTAssertGreaterThan(store.get(a)!.lastAccessedAt, store.get(a)!.createdAt)
    }
    func test_purgeRespectsFavorites() throws {
        let recent = store.insert(item(.text, "recent"))
        let oldFav = store.insert(item(.text, "oldfav", 8 * 86400, fav: true))
        let old = store.insert(item(.text, "old", 8 * 86400))
        let cutoff = Date.now.addingTimeInterval(-7 * 86400)
        let removed = store.purgeOlder(olderThan: cutoff, deleteFavorites: false)
        XCTAssertEqual(removed, 1)
        XCTAssertNotNil(store.get(recent)); XCTAssertNotNil(store.get(oldFav)); XCTAssertNil(store.get(old))
    }
    func test_trimToMaxKeepsFavoritesAndNewest() throws {
        let ids = (0..<6).map { store.insert(item(.text, "item\($0)", Double(6 - $0))) }
        store.setFavorite(ids[0], true)
        store.trimToMax(4)
        let remaining = store.query(.init(limit: 1000)).map { $0.id }
        XCTAssertEqual(remaining.count, 4)
        XCTAssertTrue(remaining.contains(ids[0]))
    }
}
