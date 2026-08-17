import XCTest
import KopieCore

final class DatabaseTests: XCTestCase {
    var path: String = ""
    override func setUpWithError() throws {
        path = NSTemporaryDirectory() + "/db_\(UUID().uuidString).sqlite"
        try Database(path: path).exec("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT, n INTEGER, d BLOB)")
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: path) }

    func test_runAndRows_roundtrip() throws {
        let db = try Database(path: path)
        let changes = try db.run("INSERT INTO t(name,n,d) VALUES(?,?,?)", ["copie", 5, Data([9, 9, 9])])
        XCTAssertEqual(changes, 1)
        let rows = try db.rows("SELECT name,n,d FROM t ORDER BY id", [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][0] as? String, "copie")
        XCTAssertEqual(rows[0][1] as? Int64, 5)
        XCTAssertEqual(rows[0][2] as? Data, Data([9, 9, 9]))
    }
    func test_nullHandling() throws {
        let db = try Database(path: path)
        _ = try db.run("INSERT INTO t(name,n) VALUES(NULL, NULL)", [])
        let rows = try db.rows("SELECT name,n FROM t", [])
        XCTAssertNil(rows[0][0])
        XCTAssertNil(rows[0][1])
    }
    func test_int64Params() throws {
        let db = try Database(path: path)
        _ = try db.run("INSERT INTO t(name,n) VALUES(?,?)", ["big", Int64(9_223_372_036_854_775_000)])
        let rows = try db.rows("SELECT n FROM t", [])
        XCTAssertEqual(rows[0][0] as? Int64, Int64(9_223_372_036_854_775_000))
    }
    func test_scalarInt64() throws {
        let db = try Database(path: path)
        _ = try db.run("INSERT INTO t(name) VALUES(?)", ["x"])
        _ = try db.run("INSERT INTO t(name) VALUES(?)", ["y"])
        XCTAssertEqual(db.scalarInt64("SELECT COUNT(*) FROM t", []), 2)
    }
}
