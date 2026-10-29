import Testing
import Foundation
@testable import KopieCore

@Suite struct CaptureRecencyTests {

    @Test func freshActivityAllowsRead() {
        var r = CaptureRecency(activeWindow: 90)
        let now = Date(timeIntervalSince1970: 1_000_000)
        r.touch(now)
        #expect(r.mayRead(now))
    }

    @Test func staleActivityDeniesRead() {
        var r = CaptureRecency(activeWindow: 90)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        r.touch(t0)
        #expect(!r.mayRead(t0.addingTimeInterval(91)))
    }

    @Test func boundaryIsInclusive() {
        var r = CaptureRecency(activeWindow: 90)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        r.touch(t0)
        #expect(r.mayRead(t0.addingTimeInterval(90)), "exactly at the window edge still counts")
    }

    @Test func neverTouchedDenies() {
        var r = CaptureRecency(activeWindow: 90)
        #expect(!r.mayRead(Date(timeIntervalSince1970: 500)))
    }
}
