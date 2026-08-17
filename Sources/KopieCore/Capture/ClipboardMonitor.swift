import Foundation
import AppKit

/// Observes the system pasteboard's changeCount on a low-frequency timer.
/// Idle cost is a single integer compare; the read path only runs on change.
public final class ClipboardMonitor {
    private let read: () -> CapturedContent?
    private let handle: (CapturedContent) -> Void
    private var timer: Timer?
    private var lastCount: Int
    private(set) var pendingSuppression = 0

    public init(reader: @escaping () -> CapturedContent?, handler: @escaping (CapturedContent) -> Void) {
        self.read = reader
        self.handle = handler
        self.lastCount = NSPasteboard.general.changeCount
    }

    public func start() {
        stop()
        lastCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Tell the monitor to ignore the next observed change (our own pasteboard write).
    public func beginSuppression() { pendingSuppression += 1 }

    public func tick() {
        let board = NSPasteboard.general
        let n = board.changeCount
        if n == lastCount { return }
        lastCount = n
        if pendingSuppression > 0 {
            pendingSuppression -= 1
            return
        }
        if let content = read() {
            handle(content)
        }
    }
}
