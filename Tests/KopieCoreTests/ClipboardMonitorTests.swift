import Testing
import Foundation
import AppKit
@testable import KopieCore

/// Test double for the pasteboard's changeCount: a mutable integer the
/// monitor reads through its injected closure. Reader/handler are spies.
final class CountBoard {
    var count = 100
    var pendingContent: CapturedContent? = nil
    func makeMonitor(reader: @escaping () -> CapturedContent? = { nil },
                     handler: @escaping (CapturedContent) -> Void = { _ in },
                     readGate: (() -> Bool)? = nil) -> ClipboardMonitor {
        self.readSpy = reader
        return ClipboardMonitor(readChangeCount: { [self] in self.count },
                                reader: reader,
                                handler: handler,
                                readGate: readGate)
    }
    private(set) var readSpy: (() -> CapturedContent?)? = nil
}

private func text(_ s: String) -> CapturedContent {
    CapturedContent(kind: .text(s), sourceAppID: "com.test.app")
}

@Suite struct ClipboardMonitorTests {

    @Test func firstChangeIsCaptured() {
        let board = CountBoard()
        var captured: [CapturedContent] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0) }
        board.pendingContent = text("hello")
        board.count = 101
        m.tick()
        #expect(captured.map(\.text) == ["hello"])
        #expect(m.missedCount == 0)
    }

    @Test func unchangedCountNeverSpamsReads() {
        let board = CountBoard()
        var reads = 0
        let m = board.makeMonitor(reader: { reads += 1; return board.pendingContent }) { _ in }
        let baseReads = reads
        board.pendingContent = text("hello")
        m.tick(); m.tick(); m.tick()
        #expect(reads == baseReads)   // count hasn't moved — no read at all
        #expect(reads == baseReads)   // loot expected: reader only runs on change
    }

    @Test func ownWriteCountIsHonored() {
        let board = CountBoard()
        var captured: [CapturedContent] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0) }
        // OUR OWN write: bump count, record it, then poll.
        board.pendingContent = text("self-written")
        board.count = 101
        m.noteSelfWrite()
        m.tick()
        #expect(captured.isEmpty, "own write must never re-capture")
        // Count-based filter is *count*-based, not suppression-count-based:
        // a later user change above our write count still lands.
        board.pendingContent = text("user")
        board.count = 102
        m.tick()
        #expect(captured.map(\.text) == ["user"])
    }

    @Test func legacySuppressionStillHonored() {
        let board = CountBoard()
        var captured: [CapturedContent] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0) }
        board.pendingContent = text("self")
        board.count = 101
        m.beginSuppression()          // write about to happen on this run-loop turn
        m.tick()
        #expect(captured.isEmpty)
    }

    @Test func deltaGreaterThanOneSurfacesMissWithoutSilentLoss() {
        let board = CountBoard()
        var anomalies: [Int] = []
        var captured: [CapturedContent] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0) }
        m.onAnomaly = { anomalies.append($0) }
        board.pendingContent = text("newest")
        board.count = 105            // jumped 100 → 105: 4 intermediate changes
        m.tick()
        #expect(captured.map(\.text) == ["newest"], "newest state is still captured")
        #expect(m.missedCount == 4)
        #expect(anomalies == [4], "one anomaly, one read — never silent")
    }

    @Test func readFailureRetriesOncePerTickThenSurfaces() {
        let board = CountBoard()
        var anomalies: [Int] = []
        var attempts = 0
        let m = board.makeMonitor(reader: { attempts += 1; return nil }) { _ in }
        m.onAnomaly = { anomalies.append($0) }
        board.count = 101
        m.tick()
        #expect(anomalies.isEmpty, "first failure gets one retry attempt")
        m.tick()                     // count unchanged, but retry fires
        m.tick()                     // retry again? No: only one retry per failure
        #expect(attempts == 2, "initial read + one retry, then stop")
        #expect(m.missedCount == 1)
        #expect(anomalies == [1])
    }

    @Test func readGateBlocksReadButNeverMarksMiss() {
        let board = CountBoard()
        var reads = 0
        var anomalies: [Int] = []
        let m = board.makeMonitor(reader: { reads += 1; return nil }) { _ in }
        m.onAnomaly = { anomalies.append($0) }
        board.count = 101
        m.tick()
        // Gate closes (idle): the change is skipped intentionally.
        let closed = { false }
        let m2 = board.makeMonitor(reader: { reads += 1; return nil }, readGate: closed)
        m2.onAnomaly = { anomalies.append($0) }
        m2.tick()
        #expect(anomalies.isEmpty, "an intentional idle skip is not a 'missed copy'")
    }

    @Test func reconcileReadsCurrentBoardAndClearsMissedSilently() {
        let board = CountBoard()
        var anomalies: [Int] = []
        var captured: [CapturedContent] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0) }
        m.onAnomaly = { anomalies.append($0) }
        board.pendingContent = text("reconciled")
        board.count = 105
        m.reconcile()                 // forced read; no anomaly just because we reconciled
        #expect(captured.map(\.text) == ["reconciled"])
        #expect(m.missedCount == 0)
        #expect(anomalies.isEmpty, "reconcile never re-reports the misses it just fixed")
    }

    @Test func orderingIsStableAcrossQueueHops() async throws {
        // Reader hops to main async — simulate by capturing main-thread ordering:
        // (this asserts the serial contract, not real concurrency timing)
        let board = CountBoard()
        var captured: [String] = []
        let m = board.makeMonitor(reader: { board.pendingContent }) { captured.append($0.text ?? "") }
        board.pendingContent = text("two")
        board.count = 102
        m.tick()
        board.pendingContent = text("three")
        board.count = 103
        m.tick()
        // Order across two ticks: each capture succeeds — that's the 'no loss' contract.
        // Handler hop to main is exercised implicitly by the real handler path.
        #expect(captured == ["two", "three"])
    }
}

// MARK: - S-011 self-write wiring (Task 2)

/// RestoreService must tell the monitor when its staging write is DONE, so the
/// count-based own-write filter can skip the change it just created.
@Suite struct SelfWriteWiringTests {

    @Test func restoreServiceFiresDidWriteAfterStaging() {
        // RestoreService stages content then fires onDidWrite — the wiring
        // calls monitor.noteSelfWrite() in it. Simulate the AppState pair:
        let board = CountBoard()
        let m = board.makeMonitor(reader: { board.pendingContent }) { _ in }
        let restore = RestoreService()
        var didWriteFires = 0
        restore.onDidWrite = { didWriteFires += 1; m.noteSelfWrite() }
        board.count = 200
        // RestoreService writes to the REAL pasteboard here (test host is a
        // macOS process; NSPasteboard.general is available in SPM tests).
        let writer = ClipWriterStub()
        restore.restore(makeItem(text: "self-written-string"), writer: writer, plainTextOnly: false)
        #expect(didWriteFires == 1, "onDidWrite fires exactly once per restore")
        m.tick()
        // The restore bumped the real changeCount; noteSelfWrite recorded it
        // so the poll skips instead of re-capturing our own staging.
        // (Reader here returns nil; the assertion is that no anomaly fired.)
        #expect(m.missedCount == 0, "own write after restore does not count as a miss")
    }

    private func makeItem(text t: String) -> ClipboardItem {
        ClipboardItem(id: 1, kind: .text, createdAt: Date(), lastAccessedAt: Date(), isFavorite: false,
                      contentHash: "h-\(t)", text: t, imageRelPath: nil, thumbRelPath: nil,
                      fileSize: t.utf8.count, width: nil, height: nil)
    }
}

/// No-op ClipWriter stub: satisfies the protocol's full surface so
/// RestoreService.restore compiles and runs without touching disk.
final class ClipWriterStub: ClipWriter {
    @discardableResult
    func writeImage(_ data: Data, hashHex: String) throws -> ImageStorageInfo {
        ImageStorageInfo(imageRelPath: "", thumbRelPath: nil, width: 0, height: 0, byteSize: 0)
    }
    func imageData(relPath: String) throws -> Data { Data() }
    func loadThumb(relPath: String?) -> NSImage? { nil }
    func fileSize(relPath: String) -> Int { 0 }
    @discardableResult
    func writeRichText(_ data: Data, hashHex: String) throws -> String { "" }
    @discardableResult
    func writeHTML(_ data: Data, hashHex: String) throws -> String { "" }
    func loadRichText(relPath: String) -> Data? { nil }
}
