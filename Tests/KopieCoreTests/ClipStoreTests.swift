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

    // MARK: - At-rest encryption

    func test_textEncryptedAtRestAndDecryptedOnRead() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        _ = s.insert(item(.text, "top secret password"))

        // Raw SQL must carry the marker and never contain the plaintext.
        let db = try Database(path: tmp.appendingPathComponent("kopie.db").path)
        let stored = (try db.rows("SELECT text_content FROM clipboard_items", [])).first?.first as? String
        XCTAssertNotNil(stored)
        XCTAssertTrue(AtRestText.isEncrypted(stored!))
        XCTAssertFalse(stored!.contains("top secret password"))

        // Reads return the plaintext.
        XCTAssertEqual(s.get(1)?.text, "top secret password")
        XCTAssertEqual(s.query(.init()).first?.text, "top secret password")
    }

    func test_searchWorksOnEncryptedText() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        _ = s.insert(item(.text, "Apple Pie Recipe"))
        _ = s.insert(item(.text, "banana bread"))
        XCTAssertEqual(s.query(.init(textQuery: "apple")).count, 1)
        XCTAssertEqual(s.query(.init(textQuery: "apple")).first?.text, "Apple Pie Recipe")
        XCTAssertEqual(s.query(.init(textQuery: "recipe")).first?.text, "Apple Pie Recipe")
    }

    func test_legacyPlaintextRowMigratedOnOpen() throws {
        // Seed a plaintext row directly (pre-encryption era), then open the
        // store with a crypto key — the row must stay readable and be
        // converted to encrypted in place.
        let db = try Database(path: tmp.appendingPathComponent("kopie.db").path)
        try db.exec("""
        CREATE TABLE IF NOT EXISTS clipboard_items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          last_accessed_at INTEGER NOT NULL,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          content_hash TEXT NOT NULL,
          text_content TEXT,
          image_rel_path TEXT,
          thumb_rel_path TEXT,
          file_size INTEGER NOT NULL DEFAULT 0,
          width INTEGER,
          height INTEGER)
        """)
        _ = try db.run("""
        INSERT INTO clipboard_items(kind,created_at,last_accessed_at,is_favorite,content_hash,text_content)
        VALUES('text',0,0,0,'h','old plaintext')
        """, [])

        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        XCTAssertEqual(s.get(1)?.text, "old plaintext")

        let stored = (try db.rows("SELECT text_content FROM clipboard_items", [])).first?.first as? String
        XCTAssertTrue(AtRestText.isEncrypted(stored!))
        // The migration backfills the search index, so the row is searchable.
        XCTAssertEqual(s.query(.init(textQuery: "old plaintext")).count, 1)
    }

    // MARK: - Encrypted search index

    func test_indexSearchFindsRowsBeyondWindow() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        // Insert >1000 items: a windowed search (1000 newest) could never find
        // the oldest one, but the index covers the whole history.
        for i in 0..<1010 { _ = s.insert(item(.text, "unique-payload-\(i)")) }
        XCTAssertEqual(s.query(.init(textQuery: "unique-payload-0")).count, 1)
        XCTAssertEqual(s.query(.init(textQuery: "unique-payload-0")).first?.text, "unique-payload-0")
    }

    func test_shortQueryFallsBackToWindowedSearch() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        _ = s.insert(item(.text, "abracadabra"))
        // 2 chars — no trigrams — must still match via the fallback path.
        XCTAssertEqual(s.query(.init(textQuery: "ab")).count, 1)
        // 4 chars — index path.
        XCTAssertEqual(s.query(.init(textQuery: "abra")).count, 1)
    }

    func test_indexContainsNoPlaintext() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        _ = s.insert(item(.text, "pineapple secret"))
        let db = try Database(path: tmp.appendingPathComponent("kopie.db").path)
        let tokens = (try db.rows("SELECT token FROM search_index", [])).compactMap { $0[0] as? Data }
        XCTAssertFalse(tokens.isEmpty)
        // Tokens are HMAC output — never valid UTF-8 trigram strings.
        for t in tokens { XCTAssertNil(String(data: t, encoding: .utf8)) }
    }

    func test_deleteCleansIndexEntries() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        let id = s.insert(item(.text, "deletable text here"))
        s.delete([id])
        let db = try Database(path: tmp.appendingPathComponent("kopie.db").path)
        let n = (try db.rows("SELECT COUNT(*) FROM search_index", [])).first?.first as? Int64 ?? -1
        XCTAssertEqual(n, 0)
        // And the row itself is gone from search results.
        XCTAssertEqual(s.query(.init(textQuery: "deletable")).count, 0)
    }

    func test_indexSearchRespectsKindFilter() throws {
        let s = try ClipStore(dir: tmp, crypto: InMemoryHistoryCrypto())
        _ = s.insert(item(.text, "shared token here"))
        _ = s.insert(item(.file, "shared token here"))
        XCTAssertEqual(s.query(.init(textQuery: "shared token")).count, 2)
        XCTAssertEqual(s.query(.init(textQuery: "shared token", kind: .file)).count, 1)
        XCTAssertEqual(s.query(.init(textQuery: "shared token", kind: .file)).first?.kind, .file)
    }
}
