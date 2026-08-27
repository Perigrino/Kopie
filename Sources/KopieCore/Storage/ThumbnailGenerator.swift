import Foundation
import AppKit

/// Generates thumbnails on-demand for image items that don't have one yet.
public final class ThumbnailGenerator {
    private let baseDir: URL
    private let crypto: HistoryCrypto?
    private static let thumbSide = 256
    private static let magic = Data("KPE1".utf8)
    
    public init(baseDir: URL? = nil, crypto: HistoryCrypto? = nil) {
        self.baseDir = baseDir ?? StoragePaths.baseDir()
        self.crypto = crypto ?? (try? KeychainHistoryCrypto())
        let fm = FileManager.default
        try? fm.createDirectory(at: self.baseDir.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
    }
    
    /// Generates a thumbnail for an image item if one doesn't exist.
    /// Returns the relative path to the thumbnail, or nil if generation failed.
    @discardableResult
    public func generateThumbnailIfNeeded(imageRelPath: String, hashHex: String) -> String? {
        let thumbRel = "thumbs/\(hashHex).png"
        let thumbPath = baseDir.appendingPathComponent(thumbRel)
        
        // Already exists
        if FileManager.default.fileExists(atPath: thumbPath.path) {
            return thumbRel
        }
        
        // Load the full image
        let imagePath = baseDir.appendingPathComponent(imageRelPath)
        guard let data = readDecrypted(at: imagePath),
              let image = NSImage(data: data) else {
            return nil
        }
        
        // Resize to thumbnail size
        guard let thumb = resize(image, maxSide: Self.thumbSide),
              let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        // Write encrypted thumbnail
        let encrypted = self.encrypted(png)
        do {
            try encrypted.write(to: thumbPath, options: .atomic)
            return thumbRel
        } catch {
            return nil
        }
    }
    
    private func readDecrypted(at url: URL) -> Data? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        if raw.starts(with: Self.magic) {
            guard let c = crypto, let d = c.decrypt(raw.dropFirst(Self.magic.count)) else { return raw }
            return d
        }
        return raw
    }
    
    private func encrypted(_ data: Data) -> Data {
        guard let c = crypto, let enc = try? c.encrypt(data) else { return data }
        return Self.magic + enc
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
    
    private func pixelSize(_ image: NSImage) -> (Int, Int) {
        for rep in image.representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (Int(cg.width), Int(cg.height))
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}
