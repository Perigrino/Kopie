import Foundation
import KopieCore

/// A named bucket of items sharing the same calendar day.
struct DayGroup: Identifiable {
    let id: String
    let label: String
    var items: [ClipboardItem]
}

func groupByDay(_ items: [ClipboardItem]) -> [DayGroup] {
    let cal = Calendar.current
    
    // Separate pinned items from regular items
    let pinnedItems = items.filter { $0.isPinned }
    let regularItems = items.filter { !$0.isPinned }
    
    var result: [DayGroup] = []
    
    // Pinned section first (if any)
    if !pinnedItems.isEmpty {
        result.append(DayGroup(id: "pinned", label: "Pinned", items: pinnedItems))
    }
    
    // Then group regular items by day
    var groups: [String: DayGroup] = [:]
    for it in regularItems {
        let start = cal.startOfDay(for: it.createdAt)
        let key = start.timeIntervalSince1970.description
        if groups[key] == nil {
            let label = start == cal.startOfDay(for: .now) ? "Today" :
                        start == cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))! ? "Yesterday" :
                        it.createdAt.formatted(date: .abbreviated, time: .omitted)
            groups[key] = DayGroup(id: key, label: label, items: [])
        }
        groups[key]!.items.append(it)
    }
    
    // Sort groups by date descending (most recent day first)
    let sortedGroups = groups.values.sorted { $0.id > $1.id }
    result.append(contentsOf: sortedGroups)
    
    return result
}

extension GroupedEntry: Identifiable {
    public var id: Int64 { payload.id }
}

extension GroupedEntry {
    /// Total member count when this entry is a burst, else nil (S-014 badge).
    var burstCount: Int? {
        if case .group(let g) = self { return g.members.count }
        return nil
    }
}

/// Flattens one day's items into render entries with optional burst grouping.
func entriesForDay(_ group: DayGroup, burstGrouping: Bool) -> [GroupedEntry] {
    burstGrouping ? CopyGrouper.group(group.items) : group.items.map(GroupedEntry.single)
}
