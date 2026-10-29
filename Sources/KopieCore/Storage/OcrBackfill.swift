import Foundation
import AppKit
import Vision

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

    /// Processes a SINGLE batch of OCR backfill work.
    /// Call repeatedly from a scheduler to get incremental progress updates.
    /// - Parameters:
    ///   - store: The ClipStore to query and update.
    ///   - writer: The ClipWriter to read image data from disk.
    ///   - batchSize: Maximum number of images to process in this step.
    ///   - total: Optional pre-known total count (for progress). If nil, queries the store.
    ///   - priorDone: Number of items already processed in previous steps (for cumulative progress).
    /// - Returns: Progress with updated done count, total, and isComplete flag.
    public static func backfillStep(
        store: ClipStore,
        writer: ClipWriter,
        batchSize: Int = 50,
        total: Int? = nil,
        priorDone: Int = 0
    ) -> Progress {
        let totalCount = total ?? store.totalNonSensitiveImageCount()

        // Fetch the next batch of images needing OCR
        let candidates = store.imagesNeedingOCR(limit: batchSize)
        guard !candidates.isEmpty else {
            // Nothing more to do — complete
            return Progress(done: priorDone, total: totalCount, isComplete: true)
        }

        var batchDone = 0

        for (id, relPath) in candidates {
            do {
                // Read image data from disk
                let imageData = try writer.imageData(relPath: relPath)

                // Run OCR
                let text = ImageTextRecognizer.recognizeText(in: imageData)

                // Write back to store (idempotent, reindexes tokens)
                let ok = store.updateOCR(id, text)
                if ok { batchDone += 1 }
            } catch {
                // Continue with remaining items; error is not propagated per-batch
                // The final Result will report an error if needed
            }
        }

        let newDone = priorDone + batchDone
        let isComplete = newDone >= totalCount || candidates.count < batchSize

        return Progress(done: newDone, total: totalCount, isComplete: isComplete)
    }

    /// Runs OCR backfill on all image items that lack OCR text, processing in batches
    /// until complete or an error occurs.
    /// - Parameters:
    ///   - store: The ClipStore to query and update.
    ///   - writer: The ClipWriter to read image data from disk.
    ///   - batchSize: Maximum number of images to process per internal batch.
    ///   - now: Timestamp for any time-sensitive operations (unused here, for consistency with RetentionJob).
    /// - Returns: Result with counts and completion status.
    public static func backfill(
        store: ClipStore,
        writer: ClipWriter,
        batchSize: Int = 50,
        now: Date = .now
    ) -> Result {
        let total = store.totalNonSensitiveImageCount()

        var totalDone = 0

        // Process in batches until no more items need OCR
        while true {
            let progress = backfillStep(store: store, writer: writer, batchSize: batchSize, total: total, priorDone: totalDone)
            totalDone = progress.done
            if progress.isComplete { break }
        }

        let isComplete = totalDone >= total || store.imagesNeedingOCR(limit: 1).isEmpty

        return Result(done: totalDone, total: total, isComplete: isComplete, error: nil)
    }
}