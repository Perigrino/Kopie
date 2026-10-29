import Foundation

/// Query-time grouping of rapid multi-copies. No schema change: groups are
/// computed when a list renders, so toggling never rewrites history.
public struct CopyGroup: Equatable, Sendable {
    /// The newest member — the row the group renders as.
    public let leaderID: Int64
    /// Newest-first; member[0] is the leader.
    public let members: [ClipboardItem]
}

public enum GroupedEntry: Equatable, Sendable {
    case single(ClipboardItem)
    case group(CopyGroup)

    /// The item this entry renders as (single item, or group leader).
    public var payload: ClipboardItem {
        switch self {
        case .single(let item): return item
        case .group(let g): return g.members[0]
        }
    }
}

public enum CopyGrouper {
    /// Two copies within this many seconds of each other (chained) belong to
    /// one burst. Chain rule: each member is compared to the previous member,
    /// not the leader, so a 6-copy burst 1.5s apart stays one group.
    public static let defaultWindow: TimeInterval = 2.0

    /// Collapses rapid multi-copy runs. `items` arrive newest-first (the
    /// store's query order). Callers pass one day's items so bursts never
    /// straddle day headers.
    ///
    /// Exempt rows never absorb into a group and never chain a burst over:
    /// pinned (kept as its own "Pinned" section upstream), favorited,
    /// and sensitive (masked) clips always render as single rows.
    public static func group(_ items: [ClipboardItem],
                             window: TimeInterval = defaultWindow) -> [GroupedEntry] {
        var out: [GroupedEntry] = []
        var burst: [ClipboardItem] = []
        var lastAddedDate: Date?

        func sameSource(_ a: ClipboardItem, _ b: ClipboardItem) -> Bool {
            // Two unattributed clips count as the same "unknown" origin —
            // that reading matches the "burst, same app" intent.
            return a.sourceApp == b.sourceApp
        }

        func flush() {
            if burst.count >= 2 {
                let members = burst
                out.append(.group(CopyGroup(leaderID: members[0].id, members: members)))
            } else {
                for single in burst { out.append(.single(single)) }
            }
            burst = []
            lastAddedDate = nil
        }

        for item in items {
            let exempt = item.isPinned || item.isFavorite || item.isSensitive
            // `(… ?? false)` is parenthesized: `&&` binds tighter than `??`,
            // so the plan's unparenthesized form would mis-parse (and fail
            // to type-check) — this reads identically: no prior member
            // inside the window means the run breaks here.
            let chains = burst.count > 0
                && (lastAddedDate.map { $0.timeIntervalSince(item.createdAt) <= window } ?? false)
                && sameSource(burst[0], item)
            if exempt {
                flush()
                out.append(.single(item))
                continue
            }
            if chains {
                burst.append(item)
                lastAddedDate = item.createdAt
            } else {
                flush()
                burst = [item]
                lastAddedDate = item.createdAt
            }
        }
        flush()
        return out
    }
}
