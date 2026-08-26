import Foundation
import AppKit

/// Resolves macOS bundle identifiers to user-friendly application names.
/// Caches results to avoid repeated system lookups.
public enum AppNameResolver {
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    private static let lock = NSLock()
    
    /// Returns the display name for a given bundle identifier.
    /// Falls back to the bundle ID if name cannot be resolved.
    public static func name(for bundleID: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cache[bundleID] { return cached }
        
        // Try running apps first (fastest path)
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            if let name = app.localizedName, !name.isEmpty {
                cache[bundleID] = name
                return name
            }
        }
        
        // Fallback: lookup from system bundles
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            // Try localized display name first, then fall back to bundle name
            let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.localizedInfoDictionary?["CFBundleName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            
            if let name = name, !name.isEmpty {
                cache[bundleID] = name
                return name
            }
        }
        
        // Last resort: return the bundle ID itself
        cache[bundleID] = bundleID
        return bundleID
    }
    
    /// Clears the name cache. Call when memory pressure is high or for testing.
    public static func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
    
    /// Returns a short, user-friendly label for the bundle ID.
    /// For example: "com.apple.Safari" → "Safari"
    /// Uses the last path component if it looks like a bundle ID.
    public static func shortLabel(for bundleID: String) -> String {
        let name = self.name(for: bundleID)
        // If name is the same as bundleID, try to extract from last component
        if name == bundleID {
            let parts = bundleID.split(separator: ".")
            if let last = parts.last {
                return String(last).localizedCapitalized
            }
        }
        return name
    }
}
