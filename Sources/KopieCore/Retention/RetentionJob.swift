import Foundation

public enum RetentionPolicy {
    /// Items created before this date are considered stale. `nil` means never delete.
    public static func cutoff(for period: RetentionPeriod, now: Date = .now) -> Date? {
        guard let d = period.days else { return nil }
        return now.addingTimeInterval(-Double(d) * 86400)
    }
}

/// Runs the retention rule against a store. Favorites are protected unless opted in.
public final class RetentionJob {
    private let store: ClipStore
    public init(store: ClipStore) { self.store = store }

    /// Purges stale rows, returning the deleted count and the relative paths of
    /// content files that are no longer referenced by any surviving row, so the
    /// caller can remove them from disk.
    @discardableResult
    public func run(config: RetentionConfig, now: Date = .now) -> ClipStore.PurgeResult {
        guard let cutoff = RetentionPolicy.cutoff(for: config.period, now: now) else {
            return ClipStore.PurgeResult(deleted: 0, orphanedPaths: [])
        }
        return store.purgeOlder(olderThan: cutoff, deleteFavorites: config.deleteFavorites)
    }
}
