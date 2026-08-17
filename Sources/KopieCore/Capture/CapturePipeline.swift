import Foundation

public enum CaptureResult: Equatable {
    case captured(Int64)
    case paused
    case disabledKind
    case excludedApp
    case duplicate
    case empty
    case writeError(String)
}

/// Pure decision logic for a freshly-read clipboard payload. No AppKit; fully testable.
public final class CapturePipeline {
    private let store: ClipStore
    private let writer: ClipWriter
    public init(store: ClipStore, writer: ClipWriter) {
        self.store = store
        self.writer = writer
    }

    @discardableResult
    public func process(_ content: CapturedContent, config: CaptureConfig, now: Date = .now) -> CaptureResult {
        if config.paused { return .paused }
        switch content.kind {
        case .text: if !config.saveText { return .disabledKind }
        case .image: if !config.saveImages { return .disabledKind }
        }
        if let app = content.sourceAppID, config.excludedAppIDs.contains(app) { return .excludedApp }

        if let t = content.text, t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if content.imageData == nil && content.text == nil { return .empty }

        let hash = Hashing.sha256(content.canonicalData)
        if config.ignoreDuplicates, let latest = store.latestHash(), latest == hash { return .duplicate }

        var item = ClipboardItem(id: 0, kind: content.clipKind, createdAt: now, lastAccessedAt: now,
                                 isFavorite: false, contentHash: hash, text: content.text,
                                 imageRelPath: nil, thumbRelPath: nil, fileSize: 0,
                                 width: nil, height: nil)
        if let data = content.imageData {
            do {
                let info = try writer.writeImage(data, hashHex: hash)
                item.imageRelPath = info.imageRelPath
                item.thumbRelPath = info.thumbRelPath
                item.width = info.width
                item.height = info.height
                item.fileSize = info.byteSize
            } catch {
                return .writeError("\(error)")
            }
        } else if let t = content.text {
            item.fileSize = t.utf8.count
        }

        let id = store.insert(item)
        store.trimToMax(config.maxItems)
        return id > 0 ? .captured(id) : .writeError("insert failed")
    }
}
