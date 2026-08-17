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
    var groups: [String: DayGroup] = [:]
    var order: [String] = []
    for it in items {
        let start = cal.startOfDay(for: it.createdAt)
        let key = start.timeIntervalSince1970.description
        if groups[key] == nil {
            let label = start == cal.startOfDay(for: .now) ? "Today" :
                        start == cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))! ? "Yesterday" :
                        it.createdAt.formatted(date: .abbreviated, time: .omitted)
            groups[key] = DayGroup(id: key, label: label, items: [])
            order.append(key)
        }
        groups[key]!.items.append(it)
    }
    return order.map { groups[$0]! }
}
