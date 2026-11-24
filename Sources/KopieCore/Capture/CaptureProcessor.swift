import Foundation

/// Outcome of processing a single pending capture, reported back to the app
/// layer on the main thread.
public enum CaptureOutcome: Equatable {
    /// Item was saved as a new history entry. `ocrData` carries the raw image
    /// bytes when the item is an image and OCR should be run asynchronously.
    case saved(id: Int64, ocrData: Data?)
    /// Item matched an existing entry (re-copy); count was incremented.
    case recopied(id: Int64)
    /// Item was intentionally not saved (paused, disabled kind, empty, excluded app, sensitive skip).
    case skipped(reason: SkipReason)
    /// Item failed to persist after all retries.
    case failed(error: String)

    public enum SkipReason: String, Sendable {
        case paused
        case disabledKind
        case empty
        case excludedApp
        case sensitiveSkipped
    }
}

/// Serial background processor for captured clipboard items.
///
/// Runs on its own dispatch queue so that slow database writes and image
/// file writes never block the clipboard monitor's change detection.
///
/// Each item is dequeued, run through `CapturePipeline.process`, and — on
/// `.writeError` — retried up to `maxRetries` times with a fixed delay.
/// Results are delivered to `onOutcome` on the main thread.
///
/// The processor never drops a successfully captured item: failures are
/// retried, and only after all retries are exhausted is the outcome
/// reported as `.failed` so the UI can inform the user.
public final class CaptureProcessor: @unchecked Sendable {
    private let queue: CaptureQueue
    private let pipeline: CapturePipeline
    private let diagnostics: ClipboardDiagnostics

    /// Serial worker queue. All processing happens here, one item at a time,
    /// guaranteeing capture order.
    private let workerQueue: DispatchQueue

    /// Callback invoked on the main thread with each processing outcome.
    public var onOutcome: ((CaptureOutcome) -> Void)?

    /// Maximum number of retry attempts after a `.writeError`.
    public let maxRetries: Int
    /// Delay between retries, in seconds.
    public let retryDelay: TimeInterval

    private var stopRequested = false
    private var isRunning = false

    public init(
        queue: CaptureQueue,
        pipeline: CapturePipeline,
        diagnostics: ClipboardDiagnostics = .shared,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 0.5
    ) {
        self.queue = queue
        self.pipeline = pipeline
        self.diagnostics = diagnostics
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.workerQueue = DispatchQueue(
            label: "com.kopie.capture.processor",
            qos: .userInitiated
        )
    }

    /// Starts the processing loop on the worker queue. Idempotent.
    public func start() {
        workerQueue.sync {
            guard !isRunning else { return }
            isRunning = true
            stopRequested = false
            workerQueue.async { [weak self] in
                self?.runLoop()
            }
        }
    }

    /// Stops the processing loop. In-flight items finish; queued items
    /// remain in the queue for the next start.
    public func stop() {
        stopRequested = true
        queue.shutdown()
    }

    private func runLoop() {
        while !stopRequested {
            let waitStart = Date.now
            guard let capture = queue.dequeue(timeout: .now() + 0.5) else { continue }
            diagnostics.recordItemDequeued(waitStart: waitStart)
            process(capture)
        }
        isRunning = false
    }

    /// Processes one captured item through the pipeline, with retries on
    /// write errors. Uses `processWithPendingOCR` so that OCR recognition
    /// happens asynchronously off the processing path (handled by the app
    /// layer via `onOutcome`'s `.saved(id:ocrData:)` case).
    private func process(_ capture: PendingCapture) {
        var result: CaptureResult
        var ocrData: Data?
        var attempts = 0

        repeat {
            attempts += 1
            (result, ocrData) = pipeline.processWithPendingOCR(
                capture.content, config: currentConfig(), now: capture.capturedAt
            )

            switch result {
            case .captured(let id):
                diagnostics.recordItemProcessed()
                diagnostics.recordItemPersisted()
                postOnMain { [weak self] in
                    self?.onOutcome?(.saved(id: id, ocrData: ocrData))
                }
                return

            case .recopied(let id):
                diagnostics.recordItemDuplicate()
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.recopied(id: id))
                }
                return

            case .paused:
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.skipped(reason: .paused))
                }
                return

            case .disabledKind:
                diagnostics.recordItemDisabledKind()
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.skipped(reason: .disabledKind))
                }
                return

            case .empty:
                diagnostics.recordItemEmpty()
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.skipped(reason: .empty))
                }
                return

            case .excludedApp:
                diagnostics.recordItemExcludedApp()
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.skipped(reason: .excludedApp))
                }
                return

            case .sensitiveSkipped:
                diagnostics.recordItemSensitiveSkipped()
                diagnostics.recordItemProcessed()
                postOnMain { [weak self] in
                    self?.onOutcome?(.skipped(reason: .sensitiveSkipped))
                }
                return

            case .writeError(let message):
                diagnostics.recordProcessingFailure()
                if attempts < maxRetries {
                    diagnostics.recordRetryAttempt()
                    Thread.sleep(forTimeInterval: retryDelay)
                    continue
                }
                diagnostics.recordPersistenceFailure()
                postOnMain { [weak self] in
                    self?.onOutcome?(.failed(error: message))
                }
                return
            }
        } while true
    }

    /// Reads the current capture configuration from settings.
    private func currentConfig() -> CaptureConfig {
        SettingsStore.shared.captureConfig
    }

    private func postOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
