import Foundation

/// Export format version for forward compatibility.
private let exportVersion = 1

/// Handles export and import of clipboard history to/from JSON files.
public final class HistoryExporter {
    private let store: ClipStore
    private let writer: DiskClipWriter
    
    public init(store: ClipStore, writer: DiskClipWriter) {
        self.store = store
        self.writer = writer
    }
    
    /// Exports all clipboard items to a JSON file.
    public func export(to url: URL) throws {
        let items = store.query(QueryFilter(limit: 100000))  // Get all items
        var exportItems: [[String: Any]] = []
        
        for item in items {
            var dict: [String: Any] = [
                "id": item.id,
                "kind": item.kind.rawValue,
                "createdAt": item.createdAt.timeIntervalSince1970,
                "lastAccessedAt": item.lastAccessedAt.timeIntervalSince1970,
                "isFavorite": item.isFavorite,
                "isPinned": item.isPinned,
                "contentHash": item.contentHash,
                "fileSize": item.fileSize,
                "copyCount": item.copyCount
            ]
            
            if let text = item.text {
                dict["text"] = text
            }
            
            if let sourceApp = item.sourceApp {
                dict["sourceApp"] = sourceApp
            }
            
            if let lastCopiedAt = item.lastCopiedAt {
                dict["lastCopiedAt"] = lastCopiedAt.timeIntervalSince1970
            }
            
            if let pinnedAt = item.pinnedAt {
                dict["pinnedAt"] = pinnedAt.timeIntervalSince1970
            }
            
            // Export image as base64
            if let imageRel = item.imageRelPath, let imageData = try? writer.imageData(relPath: imageRel) {
                dict["imageData"] = imageData.base64EncodedString()
                dict["width"] = item.width
                dict["height"] = item.height
            }
            
            // Export rich text as base64, recording the original format so the
            // import can restore it as the same kind (RTF vs HTML) it was captured as.
            if let rtfRel = item.richTextRelPath, let rtfData = writer.loadRichText(relPath: rtfRel) {
                dict["richTextData"] = rtfData.base64EncodedString()
                dict["richTextFormat"] = rtfRel.hasSuffix(".html") ? "html" : "rtf"
            }
            
            exportItems.append(dict)
        }
        
        let export: [String: Any] = [
            "version": exportVersion,
            "exportedAt": Date().timeIntervalSince1970,
            "items": exportItems
        ]
        
        let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
    
    /// Imports clipboard items from a JSON file.
    /// Returns the number of items imported (skips duplicates by content hash).
    public func `import`(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        
        guard let version = json["version"] as? Int, version <= exportVersion else {
            throw ImportError.unsupportedVersion
        }
        
        guard let itemsArray = json["items"] as? [[String: Any]] else {
            throw ImportError.invalidFormat
        }
        
        var importedCount = 0
        
        for dict in itemsArray {
            guard let kindRaw = dict["kind"] as? String,
                  let kind = ClipKind(rawValue: kindRaw),
                  let createdAtTimestamp = dict["createdAt"] as? TimeInterval,
                  let contentHash = dict["contentHash"] as? String else {
                continue
            }
            
            // Skip if already exists
            if store.getByHash(contentHash) != nil {
                continue
            }
            
            let createdAt = Date(timeIntervalSince1970: createdAtTimestamp)
            let lastAccessedAt = (dict["lastAccessedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? createdAt
            let isFavorite = dict["isFavorite"] as? Bool ?? false
            let isPinned = dict["isPinned"] as? Bool ?? false
            let fileSize = dict["fileSize"] as? Int ?? 0
            let copyCount = dict["copyCount"] as? Int ?? 1
            let text = dict["text"] as? String
            let sourceApp = dict["sourceApp"] as? String
            let lastCopiedAt = (dict["lastCopiedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            let pinnedAt = (dict["pinnedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            
            // Import image if present
            var imageRelPath: String? = nil
            var thumbRelPath: String? = nil
            var width: Int? = nil
            var height: Int? = nil
            
            if let imageBase64 = dict["imageData"] as? String,
               let imageData = Data(base64Encoded: imageBase64) {
                if let info = try? writer.writeImage(imageData, hashHex: contentHash) {
                    imageRelPath = info.imageRelPath
                    thumbRelPath = info.thumbRelPath
                    width = info.width
                    height = info.height
                }
            }
            
            // Import rich text if present. Honor the exported format so HTML rich
            // text isn't silently re-stored as RTF (which would mis-render).
            var richTextRelPath: String? = nil
            if let rtfBase64 = dict["richTextData"] as? String,
               let rtfData = Data(base64Encoded: rtfBase64) {
                let isHTML = (dict["richTextFormat"] as? String)?.lowercased() == "html"
                let rel = isHTML ? try? writer.writeHTML(rtfData, hashHex: contentHash)
                                 : try? writer.writeRichText(rtfData, hashHex: contentHash)
                richTextRelPath = rel
            }
            
            let item = ClipboardItem(
                id: 0,  // Will be assigned by database
                kind: kind,
                createdAt: createdAt,
                lastAccessedAt: lastAccessedAt,
                isFavorite: isFavorite,
                contentHash: contentHash,
                text: text,
                imageRelPath: imageRelPath,
                thumbRelPath: thumbRelPath,
                fileSize: fileSize,
                width: width,
                height: height,
                sourceApp: sourceApp,
                copyCount: copyCount,
                lastCopiedAt: lastCopiedAt,
                isPinned: isPinned,
                pinnedAt: pinnedAt,
                richTextRelPath: richTextRelPath
            )
            
            let id = store.insert(item)
            if id > 0 {
                importedCount += 1
            }
        }
        
        return importedCount
    }
    
    public enum ImportError: Error, LocalizedError, Equatable {
        case invalidFormat
        case unsupportedVersion
        
        public var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Invalid export file format"
            case .unsupportedVersion: return "Export file version is not supported"
            }
        }
    }
}
