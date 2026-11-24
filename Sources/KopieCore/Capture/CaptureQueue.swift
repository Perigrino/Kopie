import Foundation

/// A pending clipboard capture waiting for background processing.
///
/// `sequence` guarantees capture order even if enqueues interleave with
/// other work. `capturedAt` records when the pasteboard was read so the
/// pipeline can timestamp the item consistently.
public struct PendingCapture: Sendable {
    public let sequence: Int64
    public let capturedAt: Date
    public let content: CapturedContent

    public init(sequence: Int64, capturedAt: Date, content: CapturedContent) {
        self.sequence = sequence
        self.capturedAt = capturedAt
        self.content = content
    }
}

/// Thread-safe, bounded FIFO queue for captured clipboard items.
///
/// Producers (the clipboard monitor) enqueue concurrently from the main
/// thread. The consumer (`CaptureProcessor`) dequeues serially on a
/// background queue. `enqueue` never blocks; `dequeue` blocks with a
/// timeout so the processor can poll for shutdown.
///
/// The queue is bounded to prevent unbounded growth under memory pressure.
/// When full, the oldest item is dropped and a diagnostic is recorded.
public final class CaptureQueue: @unchecked Sendable {
    /// Maximum number of pending captures to hold. When exceeded, the
    /// oldest item is dropped to make room.
    public let maxDepth: Int

    private var buffer: [PendingCapture] = []
    private let lock = NSLock()
    /// Signaled on every enqueue; waited on by the processor.
    private let semaphore = DispatchSemaphore(value: 0)
    /// Set to true to wake a blocked dequeue for shutdown.
    private var isShutdown = false

    public init(maxDepth: Int = 1000) {
        precondition(maxDepth > 0, "maxDepth must be positive")
        self.maxDepth = maxDepth
    }

    /// Current number of items waiting in the queue.
    public var depth: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Enqueues a captured item. Returns `false` if the queue was full and
    /// the oldest item was dropped to make room.
    @discardableResult
    public func enqueue(_ capture: PendingCapture) -> Bool {
        lock.lock()
        let wasFull = buffer.count >= maxDepth
        if wasFull {
            buffer.removeFirst() // drop oldest to bound memory
        }
        buffer.append(capture)
        lock.unlock()
        semaphore.signal()
        return !wasFull
    }

    /// Dequeues the next item, blocking up to `timeout` for one to arrive.
    /// Returns `nil` on timeout or after shutdown.
    public func dequeue(timeout: DispatchTime = .distantFuture) -> PendingCapture? {
        // Fast path: check buffer without blocking if an item is already waiting.
        lock.lock()
        if !buffer.isEmpty {
            let item = buffer.removeFirst()
            lock.unlock()
            return item
        }
        lock.unlock()

        guard semaphore.wait(timeout: timeout) == .success else { return nil }

        lock.lock()
        // Re-check under lock: another consumer may have taken it, or we're
        // shutting down.
        if isShutdown {
            lock.unlock()
            return nil
        }
        guard !buffer.isEmpty else {
            // Spurious wake; the semaphore was signaled but the buffer is
            // empty. Don't consume the signal — just return nil and let the
            // caller wait again.
            lock.unlock()
            return nil
        }
        let item = buffer.removeFirst()
        lock.unlock()
        return item
    }

    /// Signals all blocked dequeues to return nil and stop. No further
    /// enqueues should happen after calling this.
    public func shutdown() {
        lock.lock()
        isShutdown = true
        lock.unlock()
        // Wake any blocked waiter.
        semaphore.signal()
    }
}
