import Testing
import Foundation
@testable import KopieCore

private func item(_ id: Int64, at seconds: Double, source app: String? = "com.test.app",
                  pinned: Bool = false, favorite: Bool = false, sensitive: Bool = false) -> ClipboardItem {
    ClipboardItem(id: id, kind: .text,
                  createdAt: Date(timeIntervalSince1970: 1_000_000 - seconds),
                  lastAccessedAt: Date(timeIntervalSince1970: 1_000_000 - seconds),
                  isFavorite: favorite, contentHash: "h\(id)", text: "clip \(id)",
                  imageRelPath: nil, thumbRelPath: nil, fileSize: 8, width: nil, height: nil,
                  sourceApp: app, isPinned: pinned, isSensitive: sensitive)
}

@Suite struct CopyGrouperTests {

    @Test func adjacentCopiesWithinWindowMerge() {
        // 0.9s and 1.7s ago — 0.8s apart from each other (chain rule).
        let lead = item(1, at: 0.9)
        let prev = item(2, at: 1.7, source: "com.test.app")
        let entries = CopyGrouper.group([lead, prev])
        guard case .group(let g) = entries.first, entries.count == 1 else {
            Issue.record("expected one group, got \(entries)")
            return
        }
        #expect(g.leaderID == 1)
        #expect(g.members.map(\.id) == [1, 2])
    }

    @Test func copiesBeyondWindowStaySingle() {
        let lead = item(1, at: 0.5)
        let two = item(2, at: 0.5 + 3.0)        // 2.5s gap from the leader
        let entries = CopyGrouper.group([lead, two])
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    @Test func chainRuleGroupsLongRuns() {
        // 4 copies 1.5s apart chain into one group even though the tail is
        // >window away from the leader.
        let one = item(1, at: 0)
        let two = item(2, at: 1.5)
        let three = item(3, at: 3.0)
        let four = item(4, at: 4.5)
        let entries = CopyGrouper.group([one, two, three, four])
        #expect(entries.count == 1)
        guard case .group(let g) = entries[0] else { Issue.record("not a group"); return }
        #expect(g.members.map(\.id) == [1, 2, 3, 4])
    }

    @Test func sourceChangeSplitsTheBurst() {
        let a1 = item(1, at: 0, source: "app.a")
        let a2 = item(2, at: 1.0, source: "app.a")
        let b3 = item(3, at: 2.0, source: "app.b")
        let entries = CopyGrouper.group([a1, a2, b3])
        // [a1 a2] group + [b3] single
        #expect(entries.count == 2)
        guard case .group(let g) = entries[0] else { Issue.record("first not a group"); return }
        #expect(g.members.map(\.id) == [1, 2])
        guard case .single(let s) = entries[1] else { Issue.record("second not single"); return }
        #expect(s.id == 3)
    }

    @Test func pinnedItemsNeverAbsorb() {
        let lead = item(1, at: 0, pinned: true)
        let two = item(2, at: 1.0)
        let entries = CopyGrouper.group([lead, two])
        #expect(entries.count == 2, "pinned leader stays a lone row")
    }

    @Test func favoritesAndSensitiveNeverAbsorb() {
        let lead = item(1, at: 0, favorite: true)
        let two = item(2, at: 1.0)
        let three = item(3, at: 2.0, sensitive: true)
        let entries = CopyGrouper.group([three, lead, two])   // newest first: three @2.0
        #expect(entries.count == 3, "favorite + sensitive never merge into anything")
    }

    @Test func unknownSourceMatchesUnknownSource() {
        let one = item(1, at: 0, source: nil)
        let two = item(2, at: 1.0, source: nil)
        let entries = CopyGrouper.group([one, two])
        #expect(entries.count == 1)
        guard case .group(let g) = entries[0] else { Issue.record("nil-source items should chain"); return }
        #expect(g.members.map(\.id) == [1, 2])
    }

    @Test func boundaryEqualityChains() {
        let one = item(1, at: 0)
        let two = item(2, at: 2.0)      // exactly at the window edge
        let entries = CopyGrouper.group([one, two])
        guard case .group(let g) = entries.first else { Issue.record("boundary should chain"); return }
        #expect(g.members.map(\.id) == [1, 2])
    }

    @Test func singletonRunsRenderAsSingle() {
        let only = item(1, at: 0)
        let two = item(2, at: 5.0)
        let entries = CopyGrouper.group([only, two])
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    @Test func payloadAlwaysYieldsTheRenderedItem() {
        let lead = item(1, at: 0)
        let two = item(2, at: 1.0)
        let entries = CopyGrouper.group([lead, two])
        #expect(entries[0].payload.id == 1)
        let solo = CopyGrouper.group([item(9, at: 0)])
        #expect(solo[0].payload.id == 9)
    }
}
