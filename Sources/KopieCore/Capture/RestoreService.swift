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
        }
        _ = board.changeCount
    }
}
