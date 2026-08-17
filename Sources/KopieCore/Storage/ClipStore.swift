import Foundation

/// SQLite-backed clipboard metadata store. All methods are synchronous and
/// intended to be called from a single serial queue/thread.
public final class ClipStore {
    private let db: Database
    private let baseDir: URL
    private let crypto: HistoryCrypto?
    public private(set) var bootstrapError: String?
    /// True when at-rest encryption is active (Keychain key available).
    public private(set) var encryptionAvailable: Bool

    private static let schemaSQL = """
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
      height INTEGER);
    CREATE INDEX IF NOT EXISTS idx_ci_created ON clipboard_items(created_at);
    CREATE INDEX IF NOT EXISTS idx_ci_kind ON clipboard_items(kind);
    CREATE INDEX IF NOT EXISTS idx_ci_hash ON clipboard_items(content_hash);
    """

    /// - Parameter crypto: encryption for at-rest text. `nil` auto-selects the
    ///   Keychain-backed key and silently degrades to plaintext if the Keychain
    ///   is unavailable (legacy rows and existing files remain readable).
    public init(dir: URL? = nil, crypto: HistoryCrypto? = nil) {
        let base = dir ?? StoragePaths.baseDir()
        baseDir = base
        let fm = FileManager.default
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        try? fm.createDirectory(at: base.appendingPathComponent("images"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: base.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        var err: String? = nil
        var handle: Database
        do {
            handle = try Database(path: base.appendingPathComponent("kopie.db").path)
            try handle.exec(ClipStore.schemaSQL)
        } catch {
            err = "\(error)"
            handle = try! Database(path: base.appendingPathComponent("kopie_fallback.db").path)
        }
        self.db = handle
        self.bootstrapError = err
        self.crypto = crypto ?? (try? KeychainHistoryCrypto())
        self.encryptionAvailable = self.crypto != nil
        migrateLegacyPlaintext()
    }

    public init(database: Database, baseDir: URL, crypto: HistoryCrypto? = nil) {
        self.db = database
        self.baseDir = baseDir
        self.crypto = crypto ?? (try? KeychainHistoryCrypto())
        self.encryptionAvailable = self.crypto != nil
        migrateLegacyPlaintext()
    }

    private func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
    private func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// Encrypts text before storage when a key is available.
    private func storedText(_ t: String) -> String {
        guard let c = crypto, let enc = try? AtRestText.encode(t, crypto: c) else { return t }
        return enc
    }

    /// Decrypts stored text, passing legacy plaintext through untouched.
    private func plainText(_ t: String) -> String {
        guard let c = crypto else { return t }
        return AtRestText.decode(t, crypto: c)
    }

    /// Converts pre-encryption plaintext rows in place. Idempotent: rows are
    /// already marked `enc:v1:` after the first run, so this is a no-op.
    private func migrateLegacyPlaintext() {
        guard crypto != nil else { return }
        let rows = (try? db.rows(
            "SELECT id, text_content FROM clipboard_items WHERE text_content IS NOT NULL AND text_content NOT LIKE 'enc:v1:%'",
            [])) ?? []
        for r in rows {
            guard let id = r[0] as? Int64, let t = r[1] as? String else { continue }
            _ = try? db.run("UPDATE clipboard_items SET text_content = ? WHERE id = ?",
                            [storedText(t), id])
        }
    }

    @discardableResult
    public func insert(_ item: ClipboardItem) -> Int64 {
        do {
            _ = try db.run(
        "INSERT INTO clipboard_items(kind,created_at,last_accessed_at,is_favorite,content_hash,text_content,image_rel_path,thumb_rel_path,file_size,width,height) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        [item.kind.rawValue, ms(item.createdAt), ms(item.lastAccessedAt), item.isFavorite ? 1 : 0,
         item.contentHash, item.text.map(storedText), item.imageRelPath, item.thumbRelPath, Int64(item.fileSize),
         item.width.flatMap(Int64.init), item.height.flatMap(Int64.init)])
            return db.scalarInt64("SELECT last_insert_rowid()")
        } catch {
            bootstrapError = "\(error)"
            return -1
        }
    }

    private static let cols =
        "id,kind,created_at,last_accessed_at,is_favorite,content_hash,text_content,image_rel_path,thumb_rel_path,file_size,width,height"

    private func map(_ r: [Any?]) -> ClipboardItem {
        ClipboardItem(
            id: r[0] as? Int64 ?? 0,
            kind: ClipKind(rawValue: r[1] as? String ?? "text") ?? .text,
            createdAt: date(r[2] as? Int64 ?? 0),
            lastAccessedAt: date(r[3] as? Int64 ?? 0),
            isFavorite: (r[4] as? Int64) != 0,
            contentHash: r[5] as? String ?? "",
            text: (r[6] as? String).map(plainText),
            imageRelPath: r[7] as? String,
            thumbRelPath: r[8] as? String,
            fileSize: Int(r[9] as? Int64 ?? 0),
            width: r[10].flatMap { Int($0 as? Int64 ?? 0) },
            height: r[11].flatMap { Int($0 as? Int64 ?? 0) })
    }

    public func query(_ f: QueryFilter) -> [ClipboardItem] {
        var whereC = [String](); var params: [Any?] = []
        if let k = f.kind { whereC.append("kind = ?"); params.append(k.rawValue) }
        if f.favoritesOnly { whereC.append("is_favorite = 1") }
        if let b = f.bucket {
            let cal = Calendar.current
            let now = Date.now
            if b == .today {
                whereC.append("created_at >= ?"); params.append(ms(cal.startOfDay(for: now)))
            } else if b == .yesterday {
                let yest = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
                whereC.append("created_at >= ? AND created_at < ?")
                params.append(ms(yest)); params.append(ms(cal.startOfDay(for: now)))
            } else if b == .older {
                whereC.append("created_at < ?"); params.append(ms(cal.startOfDay(for: now)))
            }
        }
        let whereSQL = whereC.isEmpty ? "" : "WHERE " + whereC.joined(separator: " AND ")
        // Text search runs in memory after decryption — SQL LIKE can't match
        // ciphertext. Fetch a generous window when searching so older matches
        // aren't cut off by the row limit.
        let limit = f.textQuery.isEmpty ? f.limit : max(f.limit, 1000)
        let sql = "SELECT \(Self.cols) FROM clipboard_items \(whereSQL) ORDER BY last_accessed_at DESC, id DESC LIMIT ?"
        params.append(limit)
        let rows = (try? db.rows(sql, params)) ?? []
        var items = rows.map { map($0) }
        if !f.textQuery.isEmpty {
            let q = f.textQuery
            items = items.filter { ($0.text ?? "").localizedCaseInsensitiveContains(q) }
        }
        return items
    }

    public func get(_ id: Int64) -> ClipboardItem? {
        let rows = (try? db.rows("SELECT \(Self.cols) FROM clipboard_items WHERE id = ?", [id])) ?? []
        return rows.first.map { map($0) }
    }
    public func latestHash() -> String? {
        (try? db.rows("SELECT content_hash FROM clipboard_items ORDER BY id DESC LIMIT 1", []))?.first?.first as? String
    }
    public func setFavorite(_ id: Int64, _ flag: Bool) {
        _ = try? db.run("UPDATE clipboard_items SET is_favorite = ? WHERE id = ?", [flag ? 1 : 0, id])
    }
    public func bumpAccessed(_ id: Int64, _ now: Date = .now) {
        _ = try? db.run("UPDATE clipboard_items SET last_accessed_at = ? WHERE id = ?", [ms(now), id])
    }
    public func delete(_ ids: [Int64]) {
        for id in ids { _ = try? db.run("DELETE FROM clipboard_items WHERE id = ?", [id]) }
    }
    @discardableResult
    public func clearAll() -> Int64 {
        (try? db.run("DELETE FROM clipboard_items", [])) ?? 0
    }
    public func count() -> Int64 { db.scalarInt64("SELECT COUNT(*) FROM clipboard_items") }

    public func bytesUsed() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0
        for dir in [baseDir.appendingPathComponent("images", isDirectory: true)] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
                for f in files {
                    if let v = try? f.resourceValues(forKeys: [.fileSizeKey]), let b = v.fileSize {
                        total += Int64(b)
                    }
                }
            }
        }
        return total
    }

    public func purgeOlder(olderThan cutoff: Date, deleteFavorites: Bool) -> Int64 {
        let cond = deleteFavorites ? "" : "AND is_favorite = 0"
        return (try? db.run("DELETE FROM clipboard_items WHERE created_at < ? \(cond)", [ms(cutoff)])) ?? 0
    }

    public func trimToMax(_ max: Int) {
        let all = count()
        guard all > Int64(max) else { return }
        // Keep favorites first, then newest; evict the oldest non-favorites beyond the cap.
        // `max` is an Int we control, so inlining is safe.
        _ = try? db.run("""
        DELETE FROM clipboard_items
        WHERE id NOT IN (
          SELECT id FROM clipboard_items
          ORDER BY is_favorite DESC, created_at DESC
          LIMIT \(max)
        )
        """, [])
    }

    // MARK: - One-time cleanups

    /// Schema/cleanup version stamp (SQLite `user_version`). Starts at 0 and
    /// only ever moves forward, so one-time cleanups run exactly once per DB.
    public var cleanupVersion: Int64 {
        db.scalarInt64("PRAGMA user_version")
    }

    public func setCleanupVersion(_ version: Int64) {
        _ = try? db.run("PRAGMA user_version = \(version)", [])
    }

    /// Non-favorite text rows for one-time inspection (e.g. pre-fix image-URL
    /// captures). Favorites are never touched by cleanups. Text is decrypted
    /// so the classifier sees the plain content.
    public func textItemsForCleanup() -> [(id: Int64, text: String)] {
        let rows = (try? db.rows(
            "SELECT id, text_content FROM clipboard_items WHERE kind = 'text' AND is_favorite = 0 AND text_content IS NOT NULL",
            [])) ?? []
        return rows.compactMap { r in
            guard let id = r[0] as? Int64, let t = r[1] as? String else { return nil }
            return (id, plainText(t))
        }
    }

    /// Rewrites a stored text row into a real image row (used when the text
    /// flavor carried the image itself, e.g. a base64 data URI).
    public func convertToImage(id: Int64, imageRelPath: String, thumbRelPath: String?,
                               fileSize: Int, width: Int?, height: Int?) {
        _ = try? db.run("""
        UPDATE clipboard_items
        SET kind = 'image', text_content = NULL,
            image_rel_path = ?, thumb_rel_path = ?, file_size = ?, width = ?, height = ?
        WHERE id = ?
        """, [imageRelPath, thumbRelPath, Int64(fileSize), width.flatMap(Int64.init),
              height.flatMap(Int64.init), id])
    }
}
