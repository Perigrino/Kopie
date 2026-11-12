import Foundation

public enum CaptureResult: Equatable {
    case captured(Int64)
    case recopied(Int64)
    case paused
    case disabledKind
    case excludedApp
    case empty
    /// Content matched a secret rule under the `skipCapture` policy.
    case sensitiveSkipped
    case writeError(String)

    /// Returns the captured item ID if this result represents a successful capture.
    public var capturedID: Int64? {
        if case .captured(let id) = self { return id }
        return nil
    }
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
        let (result, ocrData) = processWithPendingOCR(content, config: config, now: now)
        // Synchronous OCR path for backward compatibility (existing callers, tests)
        if config.ocrImages, let data = ocrData {
            let text = ImageTextRecognizer.recognizeText(in: data)
            if let id = result.capturedID {
                _ = store.updateOCR(id, text)
            }
        }
        return result
    }

    /// Processes a capture and returns the result along with any image data that
    /// should be OCR'd asynchronously. The returned `CaptureResult` has `ocrText = nil`
    /// — the caller is responsible for running Vision off the hot path and writing
    /// the result back via `store.updateOCR(id, text)`.
    public func processWithPendingOCR(_ content: CapturedContent, config: CaptureConfig, now: Date = .now) -> (CaptureResult, Data?) {
        if config.paused { return (.paused, nil) }
        switch content.kind {
        case .text, .textWithRichText, .textWithHTML: if !config.saveText { return (.disabledKind, nil) }
        case .image: if !config.saveImages { return (.disabledKind, nil) }
        case .files: if !config.saveFiles { return (.disabledKind, nil) }
        }
        if let app = content.sourceAppID, config.excludedAppIDs.contains(app) { return (.excludedApp, nil) }

        // Check for empty content
        switch content.kind {
        case .text(let t) where t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             .textWithRichText(let t, _) where t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             .textWithHTML(let t, _) where t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return (.empty, nil)
        default:
            if content.imageData == nil && content.text == nil && content.filePaths == nil { return (.empty, nil) }
        }

        let hash = Hashing.sha256(content.canonicalData)
        
        // Check for re-copy of existing content
        if config.ignoreDuplicates, let existing = store.getByHash(hash) {
            let sourceApp = config.trackSourceApp ? content.sourceAppID : nil
            store.updateRecopy(existing.id, sourceApp: sourceApp, now: now)
            return (.recopied(existing.id), nil)
        }

        let sourceApp = config.trackSourceApp ? content.sourceAppID : nil
        var item = ClipboardItem(id: 0, kind: content.clipKind, createdAt: now, lastAccessedAt: now,
                                 isFavorite: false, contentHash: hash,
                                 text: content.text ?? content.filePaths?.joined(separator: "\n"),
                                 imageRelPath: nil, thumbRelPath: nil, fileSize: 0,
                                 width: nil, height: nil,
                                 sourceApp: sourceApp, copyCount: 1, lastCopiedAt: nil,
                                 richTextRelPath: nil)
        var ocrData: Data?   // deferred: recognized after the image is decoded below
        if let data = content.imageData {
            do {
                let info = try writer.writeImage(data, hashHex: hash)
                item.imageRelPath = info.imageRelPath
                item.thumbRelPath = info.thumbRelPath
                item.width = info.width
                item.height = info.height
                item.fileSize = info.byteSize
                ocrData = data
            } catch {
                return (.writeError("\(error)"), nil)
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
                ocrData = data
            } else {
                item.fileSize = Self.totalFileSize(paths)
            }
        } else if let t = content.text {
            item.fileSize = t.utf8.count
        }
        
        // Write rich text (RTF or HTML) if available
        if let richData = content.richText {
            switch content.kind {
            case .textWithHTML:
                // Write HTML content
                if let htmlRel = try? writer.writeHTML(richData, hashHex: hash) {
                    item.richTextRelPath = htmlRel
                }
            default:
                // Write RTF content
                if let rtfRel = try? writer.writeRichText(richData, hashHex: hash) {
                    item.richTextRelPath = rtfRel
                }
            }
        }

        // Sensitive-data sentinel: classify once, then apply the policy.
        // Mask-not-drop: only `skipCapture` discards, and only for text
        // content (images/files have no reliable text classifier yet).
        if let text = content.text {
            if let match = SensitiveDataDetector.detect(in: text, enabledRules: config.sensitiveEnabledRules) {
                if case .skipCapture = config.sensitivePolicy {
                    return (.sensitiveSkipped, nil)
                }
                item.isSensitive = true
                item.sensitiveKind = match.kind.rawValue
            }
            // One-time codes and magic links ask to be deleted after their
            // next paste (see RestoreService hook in the app target).
            if config.autoExpireOneTime, SensitiveDataDetector.looksLikeOneTimeSecret(text) {
                item.expiresAfterUse = true
            }
        }

        // Note: item.ocrText is intentionally left nil — caller handles async OCR
        let id = store.insert(item)
        store.trimToMax(config.maxItems)
        return (id > 0 ? .captured(id) : .writeError("insert failed"), ocrData)
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
