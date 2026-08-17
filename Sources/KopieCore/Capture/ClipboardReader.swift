import Foundation
import AppKit

/// Reads the current system pasteboard into a `CapturedContent`.
/// Text is preferred over image when both are present.
public enum ClipboardReader {
    public static func read(sourceAppID: String? = nil) -> CapturedContent? {
        let board = NSPasteboard.general
        let app = sourceAppID ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let s = board.string(forType: .string) {
            return CapturedContent(kind: .text(s), sourceAppID: app)
        }
        if let png = board.data(forType: .png) {
            return CapturedContent(kind: .image(png), sourceAppID: app)
        }
        if let tiff = board.data(forType: .tiff) {
            return CapturedContent(kind: .image(tiff), sourceAppID: app)
        }
        return nil
    }
}
