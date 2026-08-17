import XCTest
import KopieCore

final class RetentionJobTests: XCTestCase {
    var store: ClipStore!
    var job: RetentionJob!
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rt_\(UUID().uuidString)")
        store = try ClipStore(dir: tmp)
        job = RetentionJob(store: store)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func add(_ text: String, _ daysOld: Double, fav: Bool = false) {
        let t = Date.now.addingTimeInterval(-daysOld * 86400)
        _ = store.insert(.init(id: 0, kind: .text, createdAt: t, lastAccessedAt: t, isFavorite: fav,
                               contentHash: "r\(text)\(daysOld)", text: text, imageRelPath: nil,
                               thumbRelPath: nil, fileSize: 0, width: nil, height: nil))
    }

    func test_cutoff() {
        let now = Date.now
        XCTAssertNil(RetentionPolicy.cutoff(for: .never, now: now))
        let c = RetentionPolicy.cutoff(for: .daySeven, now: now)!
        XCTAssertEqual(c.timeIntervalSince(now), -7 * 86400, accuracy: 1)
    }
    func test_neverDeletesNothing() {
        add("old", 999)
        XCTAssertEqual(job.run(config: .init(period: .never, deleteFavorites: false), now: .now), 0)
        XCTAssertEqual(store.count(), 1)
    }
    func test_sevenDayDeletesOldKeepsRecent() {
        add("recent", 1); add("old", 8)
        XCTAssertEqual(job.run(config: .init(period: .daySeven, deleteFavorites: false), now: .now), 1)
        XCTAssertEqual(store.count(), 1)
    }
    func test_favoritesProtectedUnlessOptIn() {
        add("favOld", 10, fav: true); add("old", 10)
        XCTAssertEqual(job.run(config: .init(period: .daySeven, deleteFavorites: false), now: .now), 1)
        XCTAssertEqual(store.count(), 1)
        add("favOld2", 20, fav: true)
        XCTAssertEqual(job.run(config: .init(period: .daySeven, deleteFavorites: true), now: .now), 2)
        XCTAssertEqual(store.count(), 0)
    }
}
