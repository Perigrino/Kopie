import Foundation
import AppKit

/// Classifies legacy text entries so the one-time cleanup can tell an image
/// copy (captured as its URL before the image-first reader fix) apart from
/// text the user genuinely copied.
public enum ImageURLTextClassifier {
    public enum Result: Equatable {
        /// Ordinary text — leave untouched.
        case keep
        /// An http(s) URL pointing directly at an image file. The image bytes
        /// were never stored, so the entry is noise and gets removed.
        case imageURL
        /// A base64 `data:image/...` URI — the image data is actually present
        /// and the entry can be converted into a real image item.
        case dataImage(Data)
    }

    public static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff",
        "bmp", "svg", "ico", "avif", "jfif", "pict", "psd", "dng",
    ]

    public static func classify(_ raw: String) -> Result {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .keep }
        if s.lowercased().hasPrefix("data:image/") {
            return dataImage(from: s) ?? .keep
        }
        return isImageFileURL(s) ? .imageURL : .keep
    }

    // MARK: - Heuristics

    private static func isImageFileURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              url.pathExtension.lowercased() != "" else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func dataImage(from s: String) -> Result? {
        guard let comma = s.firstIndex(of: ",") else { return nil }
        let header = s[..<comma]
        guard header.lowercased().contains("base64") else { return nil }
        let body = String(s[s.index(after: comma)...])

        var cleaned = body
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        if cleaned.contains("%") { cleaned = percentDecode(cleaned) }
        // URL-safe base64 → standard base64.
        cleaned = cleaned.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        guard let data = Data(base64Encoded: cleaned + padding), !data.isEmpty else { return nil }
        return .dataImage(data)
    }

    /// Percent-decodes a UTF-8 string (base64 is ASCII, so this is lossless).
    private static func percentDecode(_ s: String) -> String {
        var bytes: [UInt8] = []
        let chars = Array(s.utf8)
        var i = 0
        while i < chars.count {
            if chars[i] == 37 /* % */, i + 2 < chars.count,
               let hi = hexValue(chars[i + 1]), let lo = hexValue(chars[i + 2]) {
                bytes.append(hi * 16 + lo)
                i += 3
            } else {
                bytes.append(chars[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48          // 0-9
        case 65...70: return c - 55          // A-F
        case 97...102: return c - 87         // a-f
        default: return nil
        }
    }
}

/// One-time migration that cleans up text entries captured before the
/// image-first reader fix: image-file URLs are removed (their bytes were never
/// stored), and base64 data-URI entries are converted into real image items.
/// Runs at most once per database, tracked via `PRAGMA user_version`.
public final class OneTimeCleanup {
    public static let currentVersion: Int64 = 1
    private let store: ClipStore
    private let writer: ClipWriter
    public init(store: ClipStore, writer: ClipWriter) {
        self.store = store
        self.writer = writer
    }

    /// Removes/converts legacy image-URL text rows. Returns how many rows were
    /// touched, or 0 if the cleanup already ran.
    @discardableResult
    public func run() -> Int {
        guard store.cleanupVersion < Self.currentVersion else { return 0 }
        defer { store.setCleanupVersion(Self.currentVersion) }

        var touched = 0
        for (id, text) in store.textItemsForCleanup() {
            switch ImageURLTextClassifier.classify(text) {
            case .keep:
                break
            case .imageURL:
                store.delete([id])
                touched += 1
            case .dataImage(let data):
                if convertToImage(id: id, data: data) { touched += 1 }
            }
        }
        if touched > 0 {
            NSLog("One-time cleanup: removed/converted \(touched) pre-fix image-URL text entries")
        }
        return touched
    }

    private func convertToImage(id: Int64, data: Data) -> Bool {
        do {
            let info = try writer.writeImage(data, hashHex: Hashing.sha256(data))
            store.convertToImage(id: id, imageRelPath: info.imageRelPath,
                                 thumbRelPath: info.thumbRelPath,
                                 fileSize: info.byteSize, width: info.width, height: info.height)
            return true
        } catch {
            NSLog("One-time cleanup: could not convert entry \(id) to image: \(error)")
            return false
        }
    }
}
