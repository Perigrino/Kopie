import Foundation
import AppKit
import UniformTypeIdentifiers

/// Resolves macOS bundle identifiers to application icons.
/// Caches results to avoid repeated system lookups.
public enum AppIconResolver {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()
    
    /// Returns the icon for a given bundle identifier.
    /// Falls back to a generic document icon if the app icon cannot be loaded.
    public static func icon(for bundleID: String, size: NSSize = NSSize(width: 16, height: 16)) -> NSImage {
        lock.lock()
        defer { lock.unlock() }
        
        let cacheKey = "\(bundleID)_\(Int(size.width))"
        if let cached = cache[cacheKey] { return cached }
        
        // Try to get the app path and its icon
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let fullIcon = NSWorkspace.shared.icon(forFile: url.path)
            // Create a properly sized copy to avoid rendering issues
            let icon = NSImage(size: size)
            icon.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            fullIcon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
            icon.unlockFocus()
            cache[cacheKey] = icon
            return icon
        }
        
        // Fallback: use the generic application icon
        let fallback = NSImage(size: size)
        fallback.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        if let appBundleType = UTType("com.apple.application-bundle") {
            let genericIcon = NSWorkspace.shared.icon(for: appBundleType)
            genericIcon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
        } else {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        fallback.unlockFocus()
        cache[cacheKey] = fallback
        return fallback
    }
    
    /// Clears the icon cache. Call when memory pressure is high or for testing.
    public static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}
