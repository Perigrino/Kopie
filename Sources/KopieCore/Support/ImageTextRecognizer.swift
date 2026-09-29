import Foundation
import Vision
import AppKit

/// On-device OCR for captured clipboard images (Vision `VNRecognizeTextRequest`).
/// Recognized text is stored per item so image copies become searchable by the
/// words inside them. 100% on-device — no network, matching Kopie's privacy
/// promise.
public enum ImageTextRecognizer {

    /// Runs text recognition on raw image data. Returns nil when the image
    /// cannot be decoded or contains no recognizable text.
    /// Vision's request handler is synchronous; callers should invoke off the
    /// main thread for large images.
    public static func recognizeText(in imageData: Data) -> String? {
        guard let image = NSImage(data: imageData),
              let cg = cgImage(from: image) else { return nil }
        return recognizeText(in: cg)
    }

    /// Runs text recognition on a CGImage.
    public static func recognizeText(in cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest { _, _ in }
        request.recognitionLevel = .fast          // clipboard-sized snippets; .accurate on demand
        request.usesLanguageCorrection = false    // keep raw text faithful for search
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        for rep in image.representations {
            if let cg = rep.cgImage(forProposedRect: nil, context: nil, hints: nil) { return cg }
        }
        return nil
    }
}
