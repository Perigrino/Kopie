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
        case .files: if !config.saveFiles { return .disabledKind }
        }
        if let app = content.sourceAppID, config.excludedAppIDs.contains(app) { return .excludedApp }

        if let t = content.text, t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if content.imageData == nil && content.text == nil && content.filePaths == nil { return .empty }

        let hash = Hashing.sha256(content.canonicalData)
        if config.ignoreDuplicates, let latest = store.latestHash(), latest == hash { return .duplicate }

        var item = ClipboardItem(id: 0, kind: content.clipKind, createdAt: now, lastAccessedAt: now,
                                 isFavorite: false, contentHash: hash,
                                 text: content.text ?? content.filePaths?.joined(separator: "\n"),
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
        } else if let paths = content.filePaths {
            // A single copied image file becomes a real image item so it
            // displays with a thumbnail (Finder copies don't put image bytes
            // on the pasteboard — just the file reference). Multi-file copies
            // and non-image files stay file items.
            if let single = paths.count == 1 ? paths.first : nil,
               Self.isImageFile(single),
               let data = try? Data(contentsOf: URL(fileURLWithPath: single)),
               let info = try? writer.writeImage(data, hashHex: hash) {
                item.kind = .image
                item.imageRelPath = info.imageRelPath
                item.thumbRelPath = info.thumbRelPath
                item.width = info.width
                item.height = info.height
                item.fileSize = info.byteSize
            } else {
                item.fileSize = Self.totalFileSize(paths)
            }
        } else if let t = content.text {
            item.fileSize = t.utf8.count
        }

        let id = store.insert(item)
        store.trimToMax(config.maxItems)
        return id > 0 ? .captured(id) : .writeError("insert failed")
    }

    /// True when a path points at a file whose extension is a known image type.
    private static func isImageFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ImageURLTextClassifier.imageExtensions.contains(ext)
    }

    /// Total size of the copied files, so the UI can show a meaningful size.
    /// Unreadable or moved files simply contribute 0.
    private static func totalFileSize(_ paths: [String]) -> Int {
        let fm = FileManager.default
        return paths.reduce(0) { total, p in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir) else { return total }
            if isDir.boolValue {
                let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
                let url = URL(fileURLWithPath: p)
                let size = (try? url.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0
                return total + size
            }
            let size = (try? fm.attributesOfItem(atPath: p)[.size] as? Int) ?? 0
            return total + size
        }
    }
}
