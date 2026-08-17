import Foundation
import AppKit

/// Writes clipboard images to disk as PNG (hash-named, so identical copies never
/// create extra files) plus a thumbnail. Very large images are downscaled.
public final class DiskClipWriter: ClipWriter {
    private let base: URL
    private static let maxPixelSide = 4096
    private static let thumbSide = 256

    public init(baseDir: URL? = nil) {
        self.base = baseDir ?? StoragePaths.baseDir()
        let fm = FileManager.default
        try? fm.createDirectory(at: base.appendingPathComponent("images"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: base.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
    }

    private func absPath(_ rel: String) -> URL { base.appendingPathComponent(rel) }

    private func pixelSize(_ image: NSImage) -> (Int, Int) {
        for rep in image.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (Int(cg.width), Int(cg.height))
        }
        return (Int(image.size.width), Int(image.size.height))
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func resize(_ image: NSImage, maxSide: Int) -> NSImage? {
        let (w, h) = pixelSize(image)
        guard w > 0, h > 0 else { return nil }
        let scale = CGFloat(maxSide) / CGFloat(max(w, h))
        guard scale < 1 else { return image }
        let nw = max(1, Int(CGFloat(w) * scale))
        let nh = max(1, Int(CGFloat(h) * scale))
        let resized = NSImage(size: NSSize(width: nw, height: nh))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: nw, height: nh),
                   from: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    @discardableResult
    public func writeImage(_ data: Data, hashHex: String) throws -> ImageStorageInfo {
        guard let original = NSImage(data: data) else { throw ClipError.unreadableImage }
        var image = original
        var (w, h) = pixelSize(image)

        if max(w, h) > Self.maxPixelSide, let scaled = resize(image, maxSide: Self.maxPixelSide) {
            image = scaled
            (w, h) = pixelSize(scaled)
        }

        guard let png = pngData(for: image) else { throw ClipError.writeFailed("png encode failed") }
        let imgRel = "images/\(hashHex).png"
        do { try png.write(to: absPath(imgRel)) } catch { throw ClipError.writeFailed("\(error)") }

        var thumbRel: String? = nil
        if max(w, h) > Self.thumbSide,
           let t = resize(image, maxSide: Self.thumbSide),
           let td = pngData(for: t) {
            let rel = "thumbs/\(hashHex).png"
            if (try? td.write(to: absPath(rel))) != nil { thumbRel = rel }
        }
        return ImageStorageInfo(imageRelPath: imgRel, thumbRelPath: thumbRel,
                                width: w, height: h, byteSize: png.count)
    }

    public func imageData(relPath: String) throws -> Data {
        try Data(contentsOf: absPath(relPath))
    }
    public func loadThumb(relPath: String?) -> NSImage? {
        guard let rel = relPath else { return nil }
        return NSImage(contentsOf: absPath(rel))
    }
    public func fileSize(relPath: String) -> Int {
        (try? Data(contentsOf: absPath(relPath)))?.count ?? 0
    }
}
