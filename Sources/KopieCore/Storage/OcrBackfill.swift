import Foundation

/// OCR backfill types for the async backfill service (S-021).
/// Mirrors the `RetentionJob` shape — synchronous, idempotent, resumable.
public enum OcrBackfill {

    /// Progress snapshot for a backfill run.
    public struct Progress: Equatable, Sendable {
        public let done: Int
        public let total: Int
        public let isComplete: Bool

        public init(done: Int, total: Int, isComplete: Bool) {
            self.done = done
            self.total = total
            self.isComplete = isComplete
        }
    }

    /// Result of a backfill batch run.
    public struct Result: Equatable, Sendable {
        public let done: Int
        public let total: Int
        public let isComplete: Bool
        public let error: String?

        public init(done: Int, total: Int, isComplete: Bool, error: String? = nil) {
            self.done = done
            self.total = total
            self.isComplete = isComplete
            self.error = error
        }
    }
}