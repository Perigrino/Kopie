import Testing
import Foundation
import AppKit
@testable import KopieCore

/// Stress tests for the clipboard capture pipeline under rapid activity.
///
/// These tests exercise the path: CaptureQueue → CaptureProcessor →
/// CapturePipeline → ClipStore, verifying that bursts of clipboard changes
/// are captured, processed, and persisted in order without silent loss.

private func text(_ s: String) -> CapturedContent {
    CapturedContent(kind: .text(s), sourceAppID: "com.test.app")
}

private func image(_ size: CGSize = CGSize(width: 40, height: 40)) -> CapturedContent {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
                               pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    return CapturedContent(kind: .image(data), sourceAppID: "com.test.app")
}

@Suite(.serialized) struct ClipboardCaptureStressTests {

    // MARK: - Queue ordering under burst

    @Test func captureQueuePreservesOrderUnderBurst() throws {
        ClipboardDiagnostics.shared.reset()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stress_q_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp)
        let pipeline = CapturePipeline(store: store, writer: writer)
        let queue = CaptureQueue(maxDepth: 1000)
        let processor = CaptureProcessor(queue: queue, pipeline: pipeline)

        var outcomes: [CaptureOutcome] = []
        let outcomeLock = NSLock()
        processor.onOutcome = { outcome in
            outcomeLock.lock()
            outcomes.append(outcome)
            outcomeLock.unlock()
        }
        processor.start()
        defer { processor.stop() }

        // Enqueue 20 items rapidly, simulating a burst of clipboard changes.
        let itemCount = 20
        for i in 0..<itemCount {
            let capture = PendingCapture(
                sequence: Int64(i),
                capturedAt: .now,
                content: text("burst-item-\(i)")
            )
            queue.enqueue(capture)
        }

        // Wait for all items to be processed.
        let deadline = Date.now.addingTimeInterval(5)
        while outcomes.count < itemCount, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        outcomeLock.lock()
        let saved = outcomes.filter { if case .saved = $0 { return true }; return false }
        let savedIds = saved.compactMap { if case .saved(id: let id, _) = $0 { return id }; return nil }
        outcomeLock.unlock()

        #expect(saved.count == itemCount, "expected \(itemCount) saved, got \(saved.count)")
        #expect(store.count() == itemCount, "expected \(itemCount) rows, got \(store.count())")
        #expect(savedIds.count == itemCount)
        #expect(savedIds.sorted() == Array(1...Int64(itemCount)), "saved IDs should be 1..\(itemCount)")

        let snap = ClipboardDiagnostics.shared.snapshot()
        #expect(snap.itemsPersisted == Int64(itemCount))
        #expect(snap.processingFailures == 0)
        #expect(snap.persistenceFailures == 0)
    }

    // MARK: - Duplicate detection under rapid re-copy

    @Test func rapidRecopyDoesNotCreateDuplicates() throws {
        ClipboardDiagnostics.shared.reset()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stress_dup_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp)
        let pipeline = CapturePipeline(store: store, writer: writer)
        let queue = CaptureQueue(maxDepth: 1000)
        let processor = CaptureProcessor(queue: queue, pipeline: pipeline)

        var outcomes: [CaptureOutcome] = []
        let outcomeLock = NSLock()
        processor.onOutcome = { outcome in
            outcomeLock.lock()
            outcomes.append(outcome)
            outcomeLock.unlock()
        }
        processor.start()
        defer { processor.stop() }

        // Copy the same text 10 times rapidly — should create 1 row with copy_count=10.
        let repeatCount = 10
        for _ in 0..<repeatCount {
            let capture = PendingCapture(
                sequence: Int64.random(in: 0...1_000_000),
                capturedAt: .now,
                content: text("same-content")
            )
            queue.enqueue(capture)
        }

        let deadline = Date.now.addingTimeInterval(5)
        while outcomes.count < repeatCount, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        outcomeLock.lock()
        let saved = outcomes.filter { if case .saved = $0 { return true }; return false }
        let recopied = outcomes.filter { if case .recopied = $0 { return true }; return false }
        outcomeLock.unlock()

        #expect(saved.count == 1, "expected 1 saved, got \(saved.count)")
        #expect(recopied.count == repeatCount - 1, "expected \(repeatCount - 1) recopied, got \(recopied.count)")
        #expect(store.count() == 1, "expected 1 row, got \(store.count())")
        #expect(store.get(1)?.copyCount == repeatCount, "expected copyCount=\(repeatCount)")

        let snap = ClipboardDiagnostics.shared.snapshot()
        #expect(snap.itemsDuplicated == Int64(repeatCount - 1))
    }

    // MARK: - Mixed content types

    @Test func mixedTextImagesFilesAllCaptured() throws {
        ClipboardDiagnostics.shared.reset()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stress_mixed_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp)
        let pipeline = CapturePipeline(store: store, writer: writer)
        let queue = CaptureQueue(maxDepth: 1000)
        let processor = CaptureProcessor(queue: queue, pipeline: pipeline)

        var outcomes: [CaptureOutcome] = []
        let outcomeLock = NSLock()
        processor.onOutcome = { outcome in
            outcomeLock.lock()
            outcomes.append(outcome)
            outcomeLock.unlock()
        }
        processor.start()
        defer { processor.stop() }

        let contents: [CapturedContent] = [
            text("first text"),
            image(),
            text("second text"),
            image(CGSize(width: 200, height: 100)),
            text("third text"),
        ]

        for (i, content) in contents.enumerated() {
            let capture = PendingCapture(sequence: Int64(i), capturedAt: .now, content: content)
            queue.enqueue(capture)
        }

        let deadline = Date.now.addingTimeInterval(5)
        while outcomes.count < contents.count, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        outcomeLock.lock()
        let saved = outcomes.filter { if case .saved = $0 { return true }; return false }
        outcomeLock.unlock()

        #expect(saved.count == contents.count, "expected \(contents.count) saved, got \(saved.count)")
        #expect(store.count() == contents.count)

        let textRows = store.query(QueryFilter(kind: .text))
        let imageRows = store.query(QueryFilter(kind: .image))
        #expect(textRows.count == 3)
        #expect(imageRows.count == 2)

        let snap = ClipboardDiagnostics.shared.snapshot()
        #expect(snap.itemsPersisted == Int64(contents.count))
        #expect(snap.processingFailures == 0)
    }

    // MARK: - Large images don't block small items

    @Test func largeImageDoesNotBlockSubsequentSmallItems() throws {
        ClipboardDiagnostics.shared.reset()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stress_large_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp)
        let pipeline = CapturePipeline(store: store, writer: writer)
        let queue = CaptureQueue(maxDepth: 1000)
        let processor = CaptureProcessor(queue: queue, pipeline: pipeline)

        var outcomes: [CaptureOutcome] = []
        let outcomeLock = NSLock()
        processor.onOutcome = { outcome in
            outcomeLock.lock()
            outcomes.append(outcome)
            outcomeLock.unlock()
        }
        processor.start()
        defer { processor.stop() }

        // Enqueue a large image followed by several small text items.
        let largeImage = image(CGSize(width: 2000, height: 2000))
        let captureLarge = PendingCapture(sequence: 0, capturedAt: .now, content: largeImage)
        queue.enqueue(captureLarge)

        for i in 1...5 {
            let capture = PendingCapture(
                sequence: Int64(i),
                capturedAt: .now,
                content: text("text-after-large-\(i)")
            )
            queue.enqueue(capture)
        }

        let totalExpected = 6
        let deadline = Date.now.addingTimeInterval(10)
        while outcomes.count < totalExpected, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        outcomeLock.lock()
        let saved = outcomes.filter { if case .saved = $0 { return true }; return false }
        let failed = outcomes.filter { if case .failed = $0 { return true }; return false }
        outcomeLock.unlock()

        #expect(saved.count == totalExpected, "expected \(totalExpected) saved, got \(saved.count)")
        #expect(failed.isEmpty, "no failures expected, got \(failed.count)")
        #expect(store.count() == totalExpected)

        let snap = ClipboardDiagnostics.shared.snapshot()
        #expect(snap.itemsPersisted == Int64(totalExpected))
        #expect(snap.processingFailures == 0)
    }

    // MARK: - Queue bounded depth

    @Test func queueDropsOldestWhenFull() {
        let queue = CaptureQueue(maxDepth: 3)
        #expect(queue.depth == 0)

        _ = queue.enqueue(PendingCapture(sequence: 1, capturedAt: .now, content: text("one")))
        _ = queue.enqueue(PendingCapture(sequence: 2, capturedAt: .now, content: text("two")))
        _ = queue.enqueue(PendingCapture(sequence: 3, capturedAt: .now, content: text("three")))
        #expect(queue.depth == 3)

        // Enqueueing a 4th should drop the oldest.
        let dropped = queue.enqueue(PendingCapture(sequence: 4, capturedAt: .now, content: text("four")))
        #expect(dropped == false, "enqueue should return false when queue was full")
        #expect(queue.depth == 3, "depth should stay at maxDepth")

        // The remaining items should be 2, 3, 4 (1 was dropped).
        let d1 = queue.dequeue()?.sequence
        let d2 = queue.dequeue()?.sequence
        let d3 = queue.dequeue()?.sequence
        #expect(d1 == 2)
        #expect(d2 == 3)
        #expect(d3 == 4)
        #expect(queue.dequeue() == nil)
    }

    // MARK: - Extended activity (many items over time)

    @Test func extendedActivitySustainsCapture() throws {
        ClipboardDiagnostics.shared.reset()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stress_extended_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = try ClipStore(dir: tmp)
        let writer = DiskClipWriter(baseDir: tmp)
        let pipeline = CapturePipeline(store: store, writer: writer)
        let queue = CaptureQueue(maxDepth: 1000)
        let processor = CaptureProcessor(queue: queue, pipeline: pipeline)

        var outcomes: [CaptureOutcome] = []
        let outcomeLock = NSLock()
        processor.onOutcome = { outcome in
            outcomeLock.lock()
            outcomes.append(outcome)
            outcomeLock.unlock()
        }
        processor.start()
        defer { processor.stop() }

        // Enqueue 50 items in 5 bursts of 10, with small delays between bursts.
        let bursts = 5
        let perBurst = 10
        var totalEnqueued = 0
        for b in 0..<bursts {
            for i in 0..<perBurst {
                let capture = PendingCapture(
                    sequence: Int64(b * perBurst + i),
                    capturedAt: .now,
                    content: text("burst-\(b)-item-\(i)")
                )
                queue.enqueue(capture)
                totalEnqueued += 1
            }
            // Small delay between bursts to simulate real-world pacing.
            Thread.sleep(forTimeInterval: 0.1)
        }

        let deadline = Date.now.addingTimeInterval(10)
        while outcomes.count < totalEnqueued, Date.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        outcomeLock.lock()
        let saved = outcomes.filter { if case .saved = $0 { return true }; return false }
        let failed = outcomes.filter { if case .failed = $0 { return true }; return false }
        outcomeLock.unlock()

        #expect(saved.count == totalEnqueued, "expected \(totalEnqueued) saved, got \(saved.count)")
        #expect(failed.isEmpty, "no failures expected, got \(failed.count)")
        #expect(store.count() == totalEnqueued)

        let snap = ClipboardDiagnostics.shared.snapshot()
        #expect(snap.itemsPersisted == Int64(totalEnqueued))
        #expect(snap.processingFailures == 0)
    }
}
