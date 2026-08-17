import XCTest
import KopieCore

final class StoragePathsTests: XCTestCase {
    /// Points `KOPIE_STORAGE_DIR` at an isolated temp dir for the duration of
    /// the test. This MUST be used by every test here: `ProcessInfo.environment`
    /// is read-only, and without a real env override these tests would resolve
    /// — and worse, delete — the user's actual `~/Library/Application Support/Kopie`.
    private func withIsolatedStorageDir(_ body: (URL) throws -> Void) rethrows {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp_\(UUID().uuidString)")
        setenv("KOPIE_STORAGE_DIR", tmp.path, 1)
        defer {
            unsetenv("KOPIE_STORAGE_DIR")
            try? FileManager.default.removeItem(at: tmp)
        }
        try body(tmp)
    }

    func test_envOverride_isResolved() throws {
        try withIsolatedStorageDir { tmp in
            // Build the expected URL the same way StoragePaths does (isDirectory: true).
            let expected = URL(fileURLWithPath: tmp.path, isDirectory: true).standardizedFileURL
            XCTAssertEqual(StoragePaths.baseDir().standardizedFileURL, expected)
        }
    }
    func test_makeDirs_createsStructure() throws {
        try withIsolatedStorageDir { tmp in
            try StoragePaths.makeDirs()
            XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.imagesDir().path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.thumbsDir().path))
            // The structure must live inside the isolated dir, never the real one.
            XCTAssertTrue(StoragePaths.baseDir().standardizedFileURL.path.hasPrefix(tmp.standardizedFileURL.path))
        }
    }
}
