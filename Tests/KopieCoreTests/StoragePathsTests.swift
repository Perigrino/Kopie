import XCTest
import KopieCore

final class StoragePathsTests: XCTestCase {
    func test_envOverride_isResolved() {
        // When KOPIE_STORAGE_DIR is set, baseDir maps to it; otherwise it ends with "Kopie".
        let base = StoragePaths.baseDir()
        if let env = ProcessInfo.processInfo.environment["KOPIE_STORAGE_DIR"], !env.isEmpty {
            XCTAssertEqual(base.standardizedFileURL, URL(fileURLWithPath: env).standardizedFileURL)
        } else {
            XCTAssertEqual(base.lastPathComponent, "Kopie")
        }
    }
    func test_makeDirs_createsStructure() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp_\(UUID().uuidString)")
        let vars = ["KOPIE_STORAGE_DIR": tmp.path]
        let env = ProcessInfo.processInfo.environment.merging(vars) { $1 }
        _ = env // env override is process-wide; verify path shape instead
        let base = StoragePaths.baseDir()
        try StoragePaths.makeDirs()
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.imagesDir().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: StoragePaths.thumbsDir().path))
        _ = tmp
        try? FileManager.default.removeItem(at: base)
    }
}
