import Foundation
import AppKit

/// Writes a stored item back onto the system pasteboard.
/// `onAboutToWrite` lets the monitor suppress the resulting (self-created) change.
public final class RestoreService {
    public var onAboutToWrite: (() -> Void)?
    public init() {}

    public func restore(_ item: ClipboardItem, writer: ClipWriter) {
        onAboutToWrite?()
        let board = NSPasteboard.general
        board.clearContents()
        switch item.kind {
        case .text:
            board.setString(item.text ?? "", forType: .string)
        case .image:
            if let rel = item.imageRelPath, let data = try? writer.imageData(relPath: rel) {
                board.setData(data, forType: .png)
                if let img = NSImage(data: data), let tiff = img.tiffRepresentation {
                    board.setData(tiff, forType: .tiff)
                }
            }
        case .file:
            let urls = (item.filePaths ?? []).map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                board.writeObjects(urls as [NSURL])
                // Legacy apps expect the plain-paths flavor; add it alongside.
                let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
                if let paths = item.filePaths {
                    board.setPropertyList(paths, forType: filenames)
                }
            }
        }
        _ = board.changeCount
    }
}
