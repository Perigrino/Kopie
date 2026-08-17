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

    @discardableResult
    public func run(config: RetentionConfig, now: Date = .now) -> Int64 {
        guard let cutoff = RetentionPolicy.cutoff(for: config.period, now: now) else { return 0 }
        return store.purgeOlder(olderThan: cutoff, deleteFavorites: config.deleteFavorites)
    }
}
