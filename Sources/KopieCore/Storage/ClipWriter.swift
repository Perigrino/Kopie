import Foundation
import AppKit

public enum ClipError: Error, Equatable {
    case unreadableImage
    case writeFailed(String)
}

public struct ImageStorageInfo: Sendable {
    public let imageRelPath: String
    public let thumbRelPath: String?
    public let width: Int
    public let height: Int
    public let byteSize: Int
    public init(imageRelPath: String, thumbRelPath: String?, width: Int, height: Int, byteSize: Int) {
        self.imageRelPath = imageRelPath
        self.thumbRelPath = thumbRelPath
        self.width = width
        self.height = height
        self.byteSize = byteSize
    }
}

/// Abstracts where clipboard image data is persisted (disk in production,
/// in-memory in tests).
public protocol ClipWriter {
    @discardableResult
    func writeImage(_ data: Data, hashHex: String) throws -> ImageStorageInfo
    func imageData(relPath: String) throws -> Data
    func loadThumb(relPath: String?) -> NSImage?
    func fileSize(relPath: String) -> Int
}
