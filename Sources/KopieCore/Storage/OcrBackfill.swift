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
        // Get the total count of non-sensitive image items (for progress reporting)
        let total = store.totalNonSensitiveImageCount()

        var totalDone = 0
        var lastError: String? = nil

        // Process in batches until no more items need OCR
        while true {
            // Fetch the next batch of images needing OCR
            let candidates = store.imagesNeedingOCR(limit: batchSize)
            guard !candidates.isEmpty else {
                // Nothing more to do — complete
                break
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
                    lastError = "Failed to process item \(id): \(error)"
                    // Continue with remaining items
                }
            }

            totalDone += batchDone

            // If we processed fewer than batchSize, we're done (no more candidates)
            if candidates.count < batchSize {
                break
            }
        }

        let isComplete = totalDone >= total || store.imagesNeedingOCR(limit: 1).isEmpty

        return Result(done: totalDone, total: total, isComplete: isComplete, error: lastError)
    }
}