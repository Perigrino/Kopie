import Foundation
import KopieCore

/// Minimal paste-failure toast surface so the AppDelegate retry orchestrator
/// compiles and degrades gracefully before Task 4's shared `ToastCenter` +
/// floating `ToastPanel` land. Phase-in only: the wording already comes from
/// `PasteToastCopy` (KopieCore); delivery is temporarily a log line + console
/// print. Task 4 replaces this implementation (API shape below matches the
/// contract `showPaste(obstacle:targetName:)` so the swap is drop-in).
@MainActor
final class ToastCenter {
    static let shared = ToastCenter()

    func showPaste(obstacle: PasteObstacle, targetName: String?) {
        let text = PasteToastCopy.message(obstacle: obstacle, targetName: targetName)
        PasteLog.logger.error("paste fallback: \(obstacle.rawValue, privacy: .public) target=\(targetName ?? "nil", privacy: .public) — \(text, privacy: .public)")
        print("Kopie toast (\(obstacle.rawValue)): \(text)")
    }
}
