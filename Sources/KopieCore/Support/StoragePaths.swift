import Foundation

public enum StoragePaths {
    public static func baseDir() -> URL {
        if let env = ProcessInfo.processInfo.environment["KOPIE_STORAGE_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Kopie", isDirectory: true)
    }
    public static func dbURL() -> URL { baseDir().appendingPathComponent("kopie.db") }
    public static func imagesDir() -> URL { baseDir().appendingPathComponent("images", isDirectory: true) }
    public static func thumbsDir() -> URL { baseDir().appendingPathComponent("thumbs", isDirectory: true) }
    public static func makeDirs() throws {
        try FileManager.default.createDirectory(at: baseDir(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDir(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbsDir(), withIntermediateDirectories: true)
    }
}
