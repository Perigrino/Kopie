import Foundation
import AppKit

/// Reads the current system pasteboard into a `CapturedContent`.
///
/// Priority: file references > image data > text.
/// - File references win because a Finder file copy also drops the file's icon
///   (often a generic file-type glyph) as TIFF on the pasteboard; capturing the
///   icon instead of the file is why copied images looked like placeholder
///   thumbnails. The pipeline resolves single image files to their real content.
/// - Image data wins over text: copying an image in Safari/Chrome/Mail also
///   drops a text representation (usually the image URL), which would otherwise
///   be stored instead of the image.
public enum ClipboardReader {
    public static func read(sourceAppID: String? = nil) -> CapturedContent? {
        let board = NSPasteboard.general
        let app = sourceAppID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let paths = filePaths(from: board) {
            return CapturedContent(kind: .files(paths), sourceAppID: app)
        }
        if let png = board.data(forType: .png) {
            return CapturedContent(kind: .image(png), sourceAppID: app)
        }
        if let tiff = board.data(forType: .tiff) {
            return CapturedContent(kind: .image(tiff), sourceAppID: app)
        }
        if let s = board.string(forType: .string) {
            return CapturedContent(kind: .text(s), sourceAppID: app)
        }
        return nil
    }

    /// Extracts copied file paths (Finder-style copies). `public.file-url`
    /// carries `file://` URL strings; the legacy `NSFilenamesPboardType`
    /// carries plain paths. Returns nil when no file reference is present.
    private static func filePaths(from board: NSPasteboard) -> [String]? {
        let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let paths = board.propertyList(forType: filenames) as? [String], !paths.isEmpty {
            return paths
        }
        guard let plist = board.propertyList(forType: .fileURL) else { return nil }
        if let s = plist as? String {
            let path = path(fromFileURL: s)
            return path.isEmpty ? nil : [path]
        }
        if let urls = plist as? [String] {
            let paths = urls.map(path(fromFileURL:)).filter { !$0.isEmpty }
            return paths.isEmpty ? nil : paths
        }
        return nil
    }

    private static func path(fromFileURL s: String) -> String {
        guard let url = URL(string: s) else { return s }
        let path = url.standardizedFileURL.path
        return path.isEmpty ? s : path
    }
}
