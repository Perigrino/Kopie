import Foundation
import AppKit

/// Observes the system pasteboard's change count and turns every reported
/// change into exactly one `read()` → `handle()` pipeline run.
///
/// Capture guarantee (S-010/S-011/S-012):
/// - Every observed delta either lands a capture or is *surfaced* as a miss —
///   never silently dropped. Deltas > 1 are accounted in `missedCount`
///   (intermediate contents are unrecoverable; the newest state is captured).
/// - A failed read gets exactly one retry on the next tick; after that it
///   counts as a miss via `onAnomaly`.
/// - Our own pasteboard writes never re-capture: write sites call
///   `noteSelfWrite()` after the write; the filter is count-based
///   (`observedCount <= lastSelfWriteCount` skips), which survives multiple
///   rapid user changes after our write. `beginSuppression()` is the legacy
///   *pre-write* signal kept as a second belt.
/// - Reads NEVER execute unless the injected `readGate` allows it (S-013:
///   the macOS 15+ pasteboard-prompt contract — reads tied to user intent).
///   A gated skip is intentional and never surfaces as an anomaly.
///
/// Threading: `tick()` stays on the main run loop (Timer), and `handler` is
/// invoked synchronously on the ticking thread — main in production, in
/// capture order guaranteed — so `ClipStore` writes stay on the main thread
/// until S-031 (M4) adds FULLMUTEX. (Deviation from the original plan sketch,
/// which dispatched `handle` to a private serial queue: that would move
/// store writes off-main and race the existing synchronous XCTest suite.)
public final class ClipboardMonitor: @unchecked Sendable {
    // Reads only the integer — the only thing we need from the pasteboard here.
    private let readChangeCount: () -> Int
    private let read: () -> CapturedContent?
    private let handle: (CapturedContent) -> Void
    private let readGate: (() -> Bool)?

    private var timer: Timer?
    private var lastCount: Int
    private var lastSelfWriteCount: Int?
    private var pendingSuppression = 0        // legacy pre-write signal (Task 2 keeps one writer site)
    private var pendingRetry = false
    private(set) var missedChanges: Int = 0

    /// Current accumulated missed changes. Grows monotonically; resets
    /// internally inside `reconcile()` (silently — no anomaly re-report).
    public var missedCount: Int { missedChanges }

    /// Fired on the caller-chosen thread whenever missedCount increases.
    public var onAnomaly: ((Int) -> Void)?

    public var isRunning: Bool { timer != nil }

    /// - Parameters:
    ///   - readChangeCount: injectable read of the pasteboard's changeCount
    ///     (production: `{ NSPasteboard.general.changeCount }`; tests: a closure
    ///     over a mutable integer).
    ///   - reader: produces a CapturedContent from the current pasteboard, or
    ///     nil when the board is empty/unreadable.
    ///   - handler: invoked on the ticking (main) thread, in capture order.
    ///   - readGate: evaluated on the main thread before any read; returning
    ///     false skips the capture intentionally (S-013).
    public init(readChangeCount: @escaping () -> Int,
                reader: @escaping () -> CapturedContent?,
                handler: @escaping (CapturedContent) -> Void,
                readGate: (() -> Bool)? = nil) {
        self.readChangeCount = readChangeCount
        self.read = reader
        self.handle = handler
        self.readGate = readGate
        self.lastCount = readChangeCount()
    }

    /// Legacy two-parameter init (kept so the existing XCTest suite that
    /// uses `ClipboardMonitor(reader:handler:)` compiles unchanged): reads
    /// the real system pasteboard's changeCount.
    public convenience init(reader: @escaping () -> CapturedContent?,
                            handler: @escaping (CapturedContent) -> Void) {
        self.init(readChangeCount: { NSPasteboard.general.changeCount },
                  reader: reader, handler: handler)
    }

    public func start() {
        guard timer == nil else { return }   // idempotent: already running
        lastCount = readChangeCount()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Poll cadence. 0.15s keeps up with copies ≥ 300ms apart (S-010 harness)
    /// while idling at one integer compare per tick.
    static let tickInterval: TimeInterval = 0.15

    /// Legacy pre-write suppression: bump immediately before our own
    /// pasteboard write on the same run-loop turn.
    public func beginSuppression() { pendingSuppression += 1 }

    /// Count-based own-write filter (S-011): call once AFTER our own
    /// pasteboard write, on the main thread.
    public func noteSelfWrite() { lastSelfWriteCount = readChangeCount() }

    /// Forced read of the current board state, for reconcile-on-open (S-012).
    /// Clears `missedChanges` without raising `onAnomaly` — the popover owns
    /// badge dismissal for display purposes.
    public func reconcile() {
        pendingRetry = false
        missedChanges = 0
        lastCount = readChangeCount()
        guard readGate?() ?? true else { return }
        if let content = read() {
            let handle = self.handle
            handle(content)   // read already done on THIS thread (caller thread = main)
        }
    }

    public func tick() {
        let n = readChangeCount()
        if n == lastCount {
            if pendingRetry { retryRead() }
            return
        }
        // A. own-write filter — count-based, survives user changes above our write.
        if let own = lastSelfWriteCount, n <= own { lastCount = n; return }
        // B. legacy suppression — the one write that is about to happen on
        //    this same run-loop turn.
        if pendingSuppression > 0 {
            pendingSuppression -= 1
            lastCount = n
            return
        }
        let delta = n - lastCount
        if delta > 1 {
            // Multiple changes since the last tick: intermediate contents are
            // gone (the board only holds the newest); surface, don't stay silent.
            pendingRetry = false
            missedChanges += delta - 1
            onAnomaly?(missedChanges)
        }
        lastCount = n
        guard readGate?() ?? true else { return }
        readNow()
    }

    private func readNow() {
        let c = read()
        if let content = c {
            pendingRetry = false
            let handle = self.handle
            handle(content)
        } else if pendingRetry {
            pendingRetry = false
            missedChanges += 1
            onAnomaly?(missedChanges)
        } else {
            pendingRetry = true     // one retry on the next tick
        }
    }

    private func retryRead() {
        pendingRetry = false
        if let content = read() {
            let handle = self.handle
            handle(content)
        } else {
            missedChanges += 1
            onAnomaly?(missedChanges)
        }
    }
}
