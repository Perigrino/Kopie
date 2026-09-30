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
      height INTEGER,
      source_app TEXT,
      copy_count INTEGER NOT NULL DEFAULT 1,
      last_copied_at INTEGER,
      is_pinned INTEGER NOT NULL DEFAULT 0,
      pinned_at INTEGER,
      rich_text_rel_path TEXT,
      ocr_text TEXT);
    CREATE INDEX IF NOT EXISTS idx_ci_created ON clipboard_items(created_at);
    CREATE INDEX IF NOT EXISTS idx_ci_kind ON clipboard_items(kind);
    CREATE INDEX IF NOT EXISTS idx_ci_hash ON clipboard_items(content_hash);
    -- Encrypted search index: keyed hashes of text trigram shingles. No
    -- plaintext is stored; searches match candidate ids by hash, then verify
    -- by decrypting only those rows.
    CREATE TABLE IF NOT EXISTS search_index(
      item_id INTEGER NOT NULL,
      token BLOB NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_search_token ON search_index(token);
    CREATE INDEX IF NOT EXISTS idx_search_item ON search_index(item_id);
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
        self.crypto = CryptoSelection.resolve(crypto)
        self.encryptionAvailable = self.crypto != nil
        migrateSchema()
        migrateLegacyPlaintext()
        backfillSearchIndex()
    }

    public init(database: Database, baseDir: URL, crypto: HistoryCrypto? = nil) {
        self.db = database
        self.baseDir = baseDir
        self.crypto = CryptoSelection.resolve(crypto)
        self.encryptionAvailable = self.crypto != nil
        migrateSchema()
        migrateLegacyPlaintext()
        backfillSearchIndex()
    }

    /// Adds new columns to existing databases that were created before the
    /// metadata feature was added. Uses PRAGMA table_info to detect which
    /// columns already exist.
    private func migrateSchema() {
        let existingColumns: Set<String> = {
            let rows = (try? db.rows("PRAGMA table_info(clipboard_items)", [])) ?? []
            return Set(rows.compactMap { $0[1] as? String })
        }()
        
        if !existingColumns.contains("source_app") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN source_app TEXT", [])
        }
        if !existingColumns.contains("copy_count") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN copy_count INTEGER NOT NULL DEFAULT 1", [])
        }
        if !existingColumns.contains("last_copied_at") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN last_copied_at INTEGER", [])
        }
        if !existingColumns.contains("is_pinned") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0", [])
        }
        if !existingColumns.contains("pinned_at") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN pinned_at INTEGER", [])
        }
        if !existingColumns.contains("rich_text_rel_path") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN rich_text_rel_path TEXT", [])
        }
        if !existingColumns.contains("ocr_text") {
            _ = try? db.run("ALTER TABLE clipboard_items ADD COLUMN ocr_text TEXT", [])
        }
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

    /// Indexes any rows (legacy or newer) that lack search-index entries. Runs
    /// at open; a no-op once the whole history is indexed.
    private func backfillSearchIndex() {
        guard crypto != nil else { return }
        let rows = (try? db.rows("""
        SELECT id, text_content FROM clipboard_items
        WHERE text_content IS NOT NULL
          AND id NOT IN (SELECT DISTINCT item_id FROM search_index)
        """, [])) ?? []
        for r in rows {
            guard let id = r[0] as? Int64, let t = r[1] as? String else { continue }
            if let tokens = crypto?.searchTokens(for: plainText(t)), !tokens.isEmpty {
                indexTokens(tokens, for: id)
            }
        }
    }

    /// Search tokens for an item: its text plus any OCR text recognized
    /// inside an image, so screenshots are findable by their content.
    private func searchTokens(for item: ClipboardItem) -> [Data] {
        var sources: [String] = []
        if let text = item.text { sources.append(text) }
        if let ocr = item.ocrText { sources.append(ocr) }
        var all: Set<Data> = []
        for s in sources {
            if let tokens = crypto?.searchTokens(for: s) { all.formUnion(tokens) }
        }
        return Array(all)
    }

    /// Inserts the token set for one item as a single batched statement.
    private func indexTokens(_ tokens: [Data], for id: Int64) {
        guard !tokens.isEmpty else { return }
        let values = tokens.map { _ in "(?,?)" }.joined(separator: ",")
        var params: [Any?] = []
        for t in tokens { params.append(id); params.append(t) }
        _ = try? db.run("INSERT INTO search_index(item_id, token) VALUES \(values)", params)
    }

    /// Removes index rows that point at items that no longer exist.
    private func sweepOrphanIndex() {
        _ = try? db.run("DELETE FROM search_index WHERE item_id NOT IN (SELECT id FROM clipboard_items)", [])
    }

    @discardableResult
    public func insert(_ item: ClipboardItem) -> Int64 {
        do {
            _ = try db.run(
        "INSERT INTO clipboard_items(kind,created_at,last_accessed_at,is_favorite,content_hash,text_content,image_rel_path,thumb_rel_path,file_size,width,height,source_app,copy_count,last_copied_at,is_pinned,pinned_at,rich_text_rel_path,ocr_text) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        [item.kind.rawValue, ms(item.createdAt), ms(item.lastAccessedAt), item.isFavorite ? 1 : 0,
         item.contentHash, item.text.map(storedText), item.imageRelPath, item.thumbRelPath, Int64(item.fileSize),
         item.width.flatMap(Int64.init), item.height.flatMap(Int64.init),
         item.sourceApp, Int64(item.copyCount), item.lastCopiedAt.map(ms),
         item.isPinned ? 1 : 0, item.pinnedAt.map(ms), item.richTextRelPath, item.ocrText])
            let id = db.scalarInt64("SELECT last_insert_rowid()")
            let tokens = searchTokens(for: item)
            if !tokens.isEmpty {
                indexTokens(tokens, for: id)
            }
            return id
        } catch {
            bootstrapError = "\(error)"
            return -1
        }
    }

    private static let cols =
        "id,kind,created_at,last_accessed_at,is_favorite,content_hash,text_content,image_rel_path,thumb_rel_path,file_size,width,height,source_app,copy_count,last_copied_at,is_pinned,pinned_at,rich_text_rel_path,ocr_text"

    /// History ordering, newest first, behind the pinned-first prefixes.
    ///
    /// Deliberately keyed on `created_at` (with `id` breaking ties) rather than
    /// `last_accessed_at`: copy-back stamps that column, so ordering by it moved
    /// the row the user had just clicked to the top and reshuffled the list under
    /// the cursor — a freshly selected row then looked like it refused to select.
    /// `last_accessed_at` is still recorded and exported; it just no longer
    /// drives the list. Pinning (an explicit user action) still reorders.
    private static let listOrder = "created_at DESC, id DESC"

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
            height: r[11].flatMap { Int($0 as? Int64 ?? 0) },
            sourceApp: r[12] as? String,
            copyCount: Int(r[13] as? Int64 ?? 1),
            lastCopiedAt: (r[14] as? Int64).map(date),
            isPinned: (r[15] as? Int64 ?? 0) != 0,
            pinnedAt: (r[16] as? Int64).map(date),
            richTextRelPath: r[17] as? String,
            ocrText: r[18] as? String)
    }

    public func query(_ f: QueryFilter) -> [ClipboardItem] {
        // Bypass trigram index for regex queries
        if !f.textQuery.isEmpty, !f.useRegex, let indexed = searchIndexMatches(f) {
            return indexed
        }
        var whereC = [String](); var params: [Any?] = []
        if let k = f.kind { whereC.append("kind = ?"); params.append(k.rawValue) }
        if f.favoritesOnly { whereC.append("is_favorite = 1") }
        if f.pinnedOnly { whereC.append("is_pinned = 1") }
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
        // No index available (no key, or query shorter than a trigram): fetch a
        // generous window and filter in memory after decryption.
        let limit = f.textQuery.isEmpty ? f.limit : max(f.limit, 1000)
        let sql = "SELECT \(Self.cols) FROM clipboard_items \(whereSQL) ORDER BY is_pinned DESC, pinned_at DESC, \(Self.listOrder) LIMIT ?"
        params.append(limit)
        let rows = (try? db.rows(sql, params)) ?? []
        var items = rows.map { map($0) }
        if !f.textQuery.isEmpty {
            items = match(items, query: f.textQuery, isRegex: f.useRegex)
        }
        return items
    }

    /// Index-backed text search: matches token hashes in SQL, then decrypts and
    /// verifies only the candidate rows. Returns nil when the index can't be
    /// used, so the caller falls back to the windowed path.
    private func searchIndexMatches(_ f: QueryFilter) -> [ClipboardItem]? {
        guard let search = crypto else { return nil }
        let tokens = search.searchTokens(for: f.textQuery)
        guard !tokens.isEmpty else { return nil }
        let distinct = Array(Set(tokens))

        var whereC = [String](); var params: [Any?] = []
        if let k = f.kind { whereC.append("kind = ?"); params.append(k.rawValue) }
        if f.favoritesOnly { whereC.append("is_favorite = 1") }
        if f.pinnedOnly { whereC.append("is_pinned = 1") }
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
        let placeholders = distinct.map { _ in "?" }.joined(separator: ",")
        whereC.append("id IN (SELECT item_id FROM search_index WHERE token IN (\(placeholders)) " +
                      "GROUP BY item_id HAVING COUNT(DISTINCT token) = ?)")
        params += distinct.map { $0 as Any? }
        params.append(Int64(distinct.count))

        let sql = "SELECT \(Self.cols) FROM clipboard_items " +
                  "WHERE \(whereC.joined(separator: " AND ")) " +
                  "ORDER BY is_pinned DESC, pinned_at DESC, \(Self.listOrder) LIMIT ?"
        params.append(max(f.limit, 1000))
        let rows = (try? db.rows(sql, params)) ?? []
        var items = rows.map { map($0) }
        items = match(items, query: f.textQuery, isRegex: f.useRegex)
        return items
    }

    /// Applies the search filter in memory. In regex mode an invalid pattern is
    /// treated as a failure and we fall back to a literal substring match rather
    /// than silently returning nothing.
    private func match(_ items: [ClipboardItem], query: String, isRegex: Bool) -> [ClipboardItem] {
        guard !query.isEmpty else { return items }
        if isRegex, let regex = try? NSRegularExpression(pattern: query, options: []) {
            return items.filter { item in
                guard let text = item.text else { return false }
                let range = NSRange(text.startIndex..., in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            }
        }
        return items.filter { item in
            if (item.text ?? "").localizedCaseInsensitiveContains(query) { return true }
            // Image items match by the words recognized inside them (OCR).
            if let ocr = item.ocrText, ocr.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
    }

    public func get(_ id: Int64) -> ClipboardItem? {
        let rows = (try? db.rows("SELECT \(Self.cols) FROM clipboard_items WHERE id = ?", [id])) ?? []
        return rows.first.map { map($0) }
    }
    
    /// Returns existing item with matching content hash, if any.
    public func getByHash(_ hash: String) -> ClipboardItem? {
        let rows = (try? db.rows("SELECT \(Self.cols) FROM clipboard_items WHERE content_hash = ? LIMIT 1", [hash])) ?? []
        return rows.first.map { map($0) }
    }
    
    /// Updates an existing item when the same content is re-copied.
    /// Increments copy count, updates timestamps, and updates source app.
    public func updateRecopy(_ id: Int64, sourceApp: String?, now: Date) {
        _ = try? db.run("""
            UPDATE clipboard_items 
            SET copy_count = copy_count + 1,
                last_copied_at = ?,
                last_accessed_at = ?,
                source_app = ?
            WHERE id = ?
        """, [ms(now), ms(now), sourceApp, id])
    }
    
    public func setFavorite(_ id: Int64, _ flag: Bool) {
        _ = try? db.run("UPDATE clipboard_items SET is_favorite = ? WHERE id = ?", [flag ? 1 : 0, id])
    }
    public func setPinned(_ id: Int64, _ flag: Bool) {
        _ = try? db.run("UPDATE clipboard_items SET is_pinned = ?, pinned_at = ? WHERE id = ?",
                        [flag ? 1 : 0, flag ? ms(.now) : nil, id])
    }

    /// Replaces the text of a text item and refreshes everything derived from
    /// it: the content hash (so re-copying the edited text dedupes against this
    /// row), the byte size, and the encrypted search-index tokens. Returns
    /// false when the row is missing or not a text item.
    @discardableResult
    public func updateText(_ id: Int64, _ newText: String) -> Bool {
        guard let item = get(id), item.kind == .text else { return false }
        let newHash = Hashing.sha256(Data(newText.utf8))
        guard (try? db.run(
            "UPDATE clipboard_items SET text_content = ?, content_hash = ?, file_size = ? WHERE id = ?",
            [storedText(newText), newHash, Int64(newText.utf8.count), id])) != nil else { return false }
        // Rebuild the search index for this row from the new text.
        _ = try? db.run("DELETE FROM search_index WHERE item_id = ?", [id])
        if let tokens = crypto?.searchTokens(for: newText), !tokens.isEmpty {
            indexTokens(tokens, for: id)
        }
        return true
    }
    public func bumpAccessed(_ id: Int64, _ now: Date = .now) {
        _ = try? db.run("UPDATE clipboard_items SET last_accessed_at = ? WHERE id = ?", [ms(now), id])
    }
    /// Deletes the given items and returns the relative paths of their content
    /// files (image, thumbnail, rich text) that are no longer referenced by any
    /// surviving row. Files are hash-named and can be shared between rows, so a
    /// path is only reported when every reference to it is going away.
    @discardableResult
    public func delete(_ ids: [Int64]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let placeholder = ids.map { _ in "?" }.joined(separator: ",")
        let params: [Any?] = ids.map { $0 as Any? }
        var paths = Set<String>()
        if let rows = try? db.rows("SELECT image_rel_path, thumb_rel_path, rich_text_rel_path FROM clipboard_items WHERE id IN (\(placeholder))", params) {
            for r in rows {
                for i in 0..<3 {
                    if let p = r[i] as? String { paths.insert(p) }
                }
            }
        }
        for id in ids {
            _ = try? db.run("DELETE FROM clipboard_items WHERE id = ?", [id])
            _ = try? db.run("DELETE FROM search_index WHERE item_id = ?", [id])
        }
        // Drop paths still referenced by surviving rows (a re-copy bumps an
        // existing row, but a re-captured hash re-inserts and shares the file).
        paths.subtract(stillReferencedPaths())
        return Array(paths)
    }

    /// Relative paths referenced by at least one surviving row.
    private func stillReferencedPaths() -> Set<String> {
        var out = Set<String>()
        if let rows = try? db.rows(
            "SELECT image_rel_path FROM clipboard_items WHERE image_rel_path IS NOT NULL " +
            "UNION SELECT thumb_rel_path FROM clipboard_items WHERE thumb_rel_path IS NOT NULL " +
            "UNION SELECT rich_text_rel_path FROM clipboard_items WHERE rich_text_rel_path IS NOT NULL", []) {
            for r in rows {
                if let p = r[0] as? String { out.insert(p) }
            }
        }
        return out
    }

    /// Returns the relative paths referenced by ALL rows (used by clearAll),
    /// then clears the table.
    @discardableResult
    public func clearAll() -> [String] {
        let paths = stillReferencedPaths()
        _ = try? db.run("DELETE FROM search_index", [])
        _ = try? db.run("DELETE FROM clipboard_items", [])
        return Array(paths)
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

    /// Result of a retention purge: how many rows went away plus the relative
    /// paths of content files that are no longer referenced by any survivor.
    public struct PurgeResult: Sendable, Equatable {
        public let deleted: Int64
        public let orphanedPaths: [String]
        public init(deleted: Int64, orphanedPaths: [String]) {
            self.deleted = deleted
            self.orphanedPaths = orphanedPaths
        }
    }

    /// Purges stale items, returning the deleted row count plus the relative
    /// paths of content files that are no longer referenced by any surviving row.
    public func purgeOlder(olderThan cutoff: Date, deleteFavorites: Bool) -> PurgeResult {
        // Collect file paths of rows about to be purged, before they're gone.
        let cond = (deleteFavorites ? "" : "AND is_favorite = 0") + " AND is_pinned = 0"
        var stalePaths = Set<String>()
        if let rows = try? db.rows("SELECT image_rel_path, thumb_rel_path, rich_text_rel_path FROM clipboard_items WHERE created_at < ? \(cond)", [ms(cutoff)]) {
            for r in rows {
                for i in 0..<3 {
                    if let p = r[i] as? String { stalePaths.insert(p) }
                }
            }
        }
        let n = (try? db.run("DELETE FROM clipboard_items WHERE created_at < ? \(cond)", [ms(cutoff)])) ?? 0
        sweepOrphanIndex()
        guard n > 0 else { return PurgeResult(deleted: 0, orphanedPaths: []) }
        stalePaths.subtract(stillReferencedPaths())
        return PurgeResult(deleted: n, orphanedPaths: Array(stalePaths))
    }

    public func trimToMax(_ max: Int) {
        let all = count()
        guard all > Int64(max) else { return }
        // Keep pinned first, then favorites, then newest; evict the oldest non-pinned non-favorites beyond the cap.
        // `max` is an Int we control, so inlining is safe.
        _ = try? db.run("""
        DELETE FROM clipboard_items
        WHERE id NOT IN (
          SELECT id FROM clipboard_items
          ORDER BY is_pinned DESC, is_favorite DESC, created_at DESC
          LIMIT \(max)
        )
        """, [])
        sweepOrphanIndex()
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
        _ = try? db.run("DELETE FROM search_index WHERE item_id = ?", [id])
    }
}
