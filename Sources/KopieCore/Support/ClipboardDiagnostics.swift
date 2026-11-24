import Foundation

/// Thread-safe diagnostics for the clipboard capture pipeline.
///
/// All counters are cumulative for the lifetime of the app. Use these to
/// distinguish between actual data loss (pasteboard overwritten before we
/// could read it), processing delays (queue backlog), and persistence
/// failures (DB or disk write errors).
///
/// Nothing here is ever shown to users — it is purely for developer
/// diagnostics and crash-reporting context.
public final class ClipboardDiagnostics: @unchecked Sendable {
    public static let shared = ClipboardDiagnostics()

    private let lock = NSLock()

    // MARK: - Counters (cumulative)

    /// Number of pasteboard changeCount deltas detected by the monitor.
    private(set) var changesDetected: Int64 = 0
    /// Number of clipboard contents successfully captured (read from pasteboard).
    private(set) var itemsCaptured: Int64 = 0
    /// Number of captured items enqueued for background processing.
    private(set) var itemsEnqueued: Int64 = 0
    /// Number of items dequeued by the processor.
    private(set) var itemsDequeued: Int64 = 0
    /// Number of items successfully processed by the pipeline.
    private(set) var itemsProcessed: Int64 = 0
    /// Number of items successfully persisted to the database.
    private(set) var itemsPersisted: Int64 = 0
    /// Number of items rejected as duplicates (content hash matched).
    private(set) var itemsDuplicated: Int64 = 0
    /// Number of items rejected as empty.
    private(set) var itemsEmpty: Int64 = 0
    /// Number of items rejected because their kind is disabled in settings.
    private(set) var itemsDisabledKind: Int64 = 0
    /// Number of items rejected because their source app is excluded.
    private(set) var itemsExcludedApp: Int64 = 0
    /// Number of items skipped because they matched a sensitive-data rule.
    private(set) var itemsSensitiveSkipped: Int64 = 0
    /// Number of pipeline processing failures (non-retryable or exhausted retries).
    private(set) var processingFailures: Int64 = 0
    /// Number of persistence failures (DB/disk write errors after retries).
    private(set) var persistenceFailures: Int64 = 0
    /// Number of items dropped because the queue was full (memory pressure).
    private(set) var queueDrops: Int64 = 0
    /// Number of retry attempts attempted for failed writes.
    private(set) var retryAttempts: Int64 = 0
    /// Number of changes detected but whose content was already overwritten
    /// by the OS before we could read it (genuine, unrecoverable loss).
    private(set) var itemsUnrecoverable: Int64 = 0

    // MARK: - Timing / depth

    private(set) var lastChangeDetected: Date?
    private(set) var lastItemPersisted: Date?
    /// Maximum queue depth observed (high-water mark for backlog).
    private(set) var maxQueueDepth: Int = 0
    /// Total time spent waiting on the queue (in seconds), for delay reporting.
    private(set) var totalQueueWaitSeconds: Double = 0
    private var queueWaitCount: Int64 = 0

    // MARK: - Recording

    public func recordChangeDetected() {
        lock.lock()
        changesDetected += 1
        lastChangeDetected = .now
        lock.unlock()
    }

    public func recordItemCaptured() {
        lock.lock()
        itemsCaptured += 1
        lock.unlock()
    }

    public func recordItemEnqueued() {
        lock.lock()
        itemsEnqueued += 1
        lock.unlock()
    }

    public func recordItemDequeued(waitStart: Date?) {
        lock.lock()
        itemsDequeued += 1
        if let waitStart {
            let wait = Date.now.timeIntervalSince(waitStart)
            totalQueueWaitSeconds += wait
            queueWaitCount += 1
        }
        lock.unlock()
    }

    public func recordItemProcessed() {
        lock.lock()
        itemsProcessed += 1
        lock.unlock()
    }

    public func recordItemPersisted() {
        lock.lock()
        itemsPersisted += 1
        lastItemPersisted = .now
        lock.unlock()
    }

    public func recordItemDuplicate() {
        lock.lock()
        itemsDuplicated += 1
        lock.unlock()
    }

    public func recordItemEmpty() {
        lock.lock()
        itemsEmpty += 1
        lock.unlock()
    }

    public func recordItemDisabledKind() {
        lock.lock()
        itemsDisabledKind += 1
        lock.unlock()
    }

    public func recordItemExcludedApp() {
        lock.lock()
        itemsExcludedApp += 1
        lock.unlock()
    }

    public func recordItemSensitiveSkipped() {
        lock.lock()
        itemsSensitiveSkipped += 1
        lock.unlock()
    }

    public func recordProcessingFailure() {
        lock.lock()
        processingFailures += 1
        lock.unlock()
    }

    public func recordPersistenceFailure() {
        lock.lock()
        persistenceFailures += 1
        lock.unlock()
    }

    public func recordQueueDrop() {
        lock.lock()
        queueDrops += 1
        lock.unlock()
    }

    public func recordRetryAttempt() {
        lock.lock()
        retryAttempts += 1
        lock.unlock()
    }

    public func recordUnrecoverable() {
        lock.lock()
        itemsUnrecoverable += 1
        lock.unlock()
    }

    public func setQueueDepth(_ depth: Int) {
        lock.lock()
        if depth > maxQueueDepth { maxQueueDepth = depth }
        lock.unlock()
    }

    // MARK: - Snapshots

    /// A point-in-time snapshot of all counters, safe to pass to UI or logs.
    public struct Snapshot: Sendable {
        public let changesDetected: Int64
        public let itemsCaptured: Int64
        public let itemsEnqueued: Int64
        public let itemsDequeued: Int64
        public let itemsProcessed: Int64
        public let itemsPersisted: Int64
        public let itemsDuplicated: Int64
        public let itemsEmpty: Int64
        public let itemsDisabledKind: Int64
        public let itemsExcludedApp: Int64
        public let itemsSensitiveSkipped: Int64
        public let processingFailures: Int64
        public let persistenceFailures: Int64
        public let queueDrops: Int64
        public let retryAttempts: Int64
        public let itemsUnrecoverable: Int64
        public let lastChangeDetected: Date?
        public let lastItemPersisted: Date?
        public let maxQueueDepth: Int
        public let averageQueueWaitSeconds: Double
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let avgWait = queueWaitCount > 0
            ? totalQueueWaitSeconds / Double(queueWaitCount)
            : 0
        return Snapshot(
            changesDetected: changesDetected,
            itemsCaptured: itemsCaptured,
            itemsEnqueued: itemsEnqueued,
            itemsDequeued: itemsDequeued,
            itemsProcessed: itemsProcessed,
            itemsPersisted: itemsPersisted,
            itemsDuplicated: itemsDuplicated,
            itemsEmpty: itemsEmpty,
            itemsDisabledKind: itemsDisabledKind,
            itemsExcludedApp: itemsExcludedApp,
            itemsSensitiveSkipped: itemsSensitiveSkipped,
            processingFailures: processingFailures,
            persistenceFailures: persistenceFailures,
            queueDrops: queueDrops,
            retryAttempts: retryAttempts,
            itemsUnrecoverable: itemsUnrecoverable,
            lastChangeDetected: lastChangeDetected,
            lastItemPersisted: lastItemPersisted,
            maxQueueDepth: maxQueueDepth,
            averageQueueWaitSeconds: avgWait
        )
    }

    /// Resets all counters (used by tests).
    public func reset() {
        lock.lock()
        changesDetected = 0
        itemsCaptured = 0
        itemsEnqueued = 0
        itemsDequeued = 0
        itemsProcessed = 0
        itemsPersisted = 0
        itemsDuplicated = 0
        itemsEmpty = 0
        itemsDisabledKind = 0
        itemsExcludedApp = 0
        itemsSensitiveSkipped = 0
        processingFailures = 0
        persistenceFailures = 0
        queueDrops = 0
        retryAttempts = 0
        itemsUnrecoverable = 0
        lastChangeDetected = nil
        lastItemPersisted = nil
        maxQueueDepth = 0
        totalQueueWaitSeconds = 0
        queueWaitCount = 0
        lock.unlock()
    }
}
