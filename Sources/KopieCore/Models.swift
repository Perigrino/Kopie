import Foundation

public enum ClipKind: String, Sendable {
    case text
    case image
}

/// Coarse time bucket used by the "Today"/"Yesterday" sidebar filters.
public enum DateBucket: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, older, all
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .older: "Older"
        case .all: "All"
        }
    }
}

/// Filters applied by `ClipStore.query`. All optional; nil/empty = no filter on that axis.
public struct QueryFilter: Hashable, Sendable {
    public var textQuery: String = ""
    public var kind: ClipKind? = nil
    public var bucket: DateBucket? = nil
    public var favoritesOnly: Bool = false
    public var limit: Int = 200

    public init(textQuery: String = "", kind: ClipKind? = nil, bucket: DateBucket? = nil,
                favoritesOnly: Bool = false, limit: Int = 200) {
        self.textQuery = textQuery
        self.kind = kind
        self.bucket = bucket
        self.favoritesOnly = favoritesOnly
        self.limit = limit
    }
}

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var kind: ClipKind
    public var createdAt: Date
    public var lastAccessedAt: Date
    public var isFavorite: Bool
    public var contentHash: String
    public var text: String?
    public var imageRelPath: String?
    public var thumbRelPath: String?
    public var fileSize: Int
    public var width: Int?
    public var height: Int?

    public init(id: Int64, kind: ClipKind, createdAt: Date, lastAccessedAt: Date, isFavorite: Bool,
                contentHash: String, text: String?, imageRelPath: String?, thumbRelPath: String?,
                fileSize: Int, width: Int?, height: Int?) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.isFavorite = isFavorite
        self.contentHash = contentHash
        self.text = text
        self.imageRelPath = imageRelPath
        self.thumbRelPath = thumbRelPath
        self.fileSize = fileSize
        self.width = width
        self.height = height
    }

    public var charCount: Int? { text?.count }
    public var typeLabel: String { kind == .text ? "Text" : "Image" }
    public var dimensionLabel: String? {
        guard let w = width, let h = height else { return nil }
        return "\(w) × \(h)"
    }
    public var preview: String {
        if let t = text {
            let one = t.replacingOccurrences(of: "\n", with: " ")
            return one.count > 200 ? String(one.prefix(200)) + "…" : one
        }
        return "(image)"
    }
}

/// A just-read clipboard payload handed to the capture pipeline.
public struct CapturedContent: Sendable {
    public enum Kind: Sendable {
        case text(String)
        case image(Data)
    }
    public let kind: Kind
    public let sourceAppID: String?

    public init(kind: Kind, sourceAppID: String?) {
        self.kind = kind
        self.sourceAppID = sourceAppID
    }

    public var clipKind: ClipKind { if case .text = kind { .text } else { .image } }
    public var text: String? { if case .text(let s) = kind { s } else { nil } }
    public var imageData: Data? { if case .image(let d) = kind { d } else { nil } }
    public var canonicalData: Data {
        switch kind {
        case .text(let s): Data(s.utf8)
        case .image(let d): d
        }
    }
}
