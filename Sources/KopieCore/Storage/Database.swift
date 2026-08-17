import Foundation
import SQLite3

/// Thin wrapper around the system libsqlite3. Not thread-safe; use from a
/// single thread or guard externally.
public final class Database {
    public struct Error: Swift.Error { public let message: String; public init(_ m: String) { message = m } }
    private var db: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        if rc != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let h = handle { sqlite3_close(h) }
            throw Error("sqlite open \(path): \(msg)")
        }
        db = handle
        sqlite3_busy_timeout(handle, 1500)
        _ = try? run("PRAGMA journal_mode=WAL", [])
        _ = try? run("PRAGMA synchronous=NORMAL", [])
        _ = try? run("PRAGMA foreign_keys=ON", [])
    }
    deinit { if let db { sqlite3_close(db) } }

    private func check(_ rc: Int32, _ ctx: String) throws {
        if rc != SQLITE_OK && rc != SQLITE_DONE && rc != SQLITE_ROW {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw Error("\(ctx): \(msg) (rc=\(rc))")
        }
    }

    private func bind(_ stmt: OpaquePointer, _ idx: Int32, _ value: Any?) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        switch value {
        case nil: sqlite3_bind_null(stmt, idx)
        case let i as Int: sqlite3_bind_int64(stmt, idx, Int64(i))
        case let i as Int64: sqlite3_bind_int64(stmt, idx, i)
        case let d as Double: sqlite3_bind_double(stmt, idx, d)
        case let s as String: sqlite3_bind_text(stmt, idx, (s as NSString).utf8String, -1, transient)
        case let data as Data:
            data.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(raw.count), transient)
            }
        default: sqlite3_bind_text(stmt, idx, String(describing: value!), -1, transient)
        }
    }

    public func exec(_ sql: String) throws { _ = try run(sql, []) }

    @discardableResult
    public func run(_ sql: String, _ params: [Any?]) throws -> Int64 {
        guard let db else { throw Error("db closed") }
        var stmt: OpaquePointer?
        var rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            let m = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw Error("prepare: \(m)")
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() { bind(stmt!, Int32(i + 1), p) }
        rc = sqlite3_step(stmt)
        try check(rc, "step")
        return Int64(sqlite3_changes(db))
    }

    public func rows(_ sql: String, _ params: [Any?]) throws -> [[Any?]] {
        guard let db else { throw Error("db closed") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let m = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(stmt)
            throw Error("prepare: \(m)")
        }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() { bind(stmt!, Int32(i + 1), p) }
        var out: [[Any?]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                let m = String(cString: sqlite3_errmsg(db))
                throw Error("row: \(m)")
            }
            let cols = Int(sqlite3_column_count(stmt))
            var row: [Any?] = []
            for c in 0..<cols {
                switch sqlite3_column_type(stmt, Int32(c)) {
                case SQLITE_INTEGER: row.append(Int64(sqlite3_column_int64(stmt, Int32(c))))
                case SQLITE_FLOAT: row.append(Double(sqlite3_column_double(stmt, Int32(c))))
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(stmt, Int32(c))))
                case SQLITE_BLOB:
                    if let b = sqlite3_column_blob(stmt, Int32(c)) {
                        row.append(Data(bytes: b, count: Int(sqlite3_column_bytes(stmt, Int32(c)))))
                    } else {
                        row.append(Data())
                    }
                default: row.append(nil)
                }
            }
            out.append(row)
        }
        return out
    }

    public func scalarInt64(_ sql: String, _ params: [Any?] = []) -> Int64 {
        (try? rows(sql, params).first)?.first as? Int64 ?? 0
    }
}
