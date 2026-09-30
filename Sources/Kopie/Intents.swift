import Foundation
import AppKit
import AppIntents
import KopieCore

/// App Intents surface for the Shortcuts app (and Siri/Spotlight).
///
/// `KopieStateBridge` hands the intents a `KopieStateHandle` registered by the
/// app delegate at launch — the running app's live `AppState`. When Shortcuts
/// invokes an intent **inside** the main app process, the delegate has already
/// run and the handle is present. If macOS instead launches a separate instance
/// (`NSWorkspace` open), `waitForApp` gives it a moment to register.
@available(macOS 13.0, *)
@MainActor
enum KopieStateBridge {
    private static var handle: KopieStateHandle?
    private static var continuation: CheckedContinuation<KopieStateHandle, Never>?

    static func register(_ h: KopieStateHandle) {
        handle = h
        continuation?.resume(returning: h)
        continuation = nil
    }

    static func waitForApp() async -> KopieStateHandle {
        if let handle { return handle }
        return await withCheckedContinuation { continuation = $0 }
    }
}

/// Live handle onto the running app's state (registered by the AppDelegate).
@MainActor
final class KopieStateHandle {
    weak var state: AppState?
    init(state: AppState) { self.state = state }
}

// MARK: - Get Latest Clipboard Item

@available(macOS 13.0, *)
struct GetLatestClipboardItem: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Clipboard Item"
    static let description = IntentDescription(
        "Returns the most recent item in your Kopie history as text.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let handle = await KopieStateBridge.waitForApp()
        guard let item = handle.state?.latestItem() else {
            return .result(value: "")
        }
        return .result(value: item.text ?? item.preview)
    }
}

// MARK: - Search Clipboard History

@available(macOS 13.0, *)
struct SearchHistoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Clipboard History"
    static let description = IntentDescription(
        "Searches your Kopie clipboard history and returns the matching items as text.")

    @Parameter(title: "Query", description: "Text to search for", default: "")
    var query: String

    @Parameter(title: "Limit", description: "Maximum number of results", default: 5)
    var limit: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let handle = await KopieStateBridge.waitForApp()
        let results = handle.state?.searchItems(query: query, limit: max(1, min(limit, 50))) ?? []
        let values = results.map { $0.text ?? $0.preview }
        return .result(value: values)
    }
}

// MARK: - Paste Next From Queue

@available(macOS 13.0, *)
struct PasteNextFromQueue: AppIntent {
    static let title: LocalizedStringResource = "Paste Next From Queue"
    static let description = IntentDescription(
        "Pastes the next item from your Kopie sequential paste queue.")

    static var suggestedInvocationPhrase: String { "Paste next from Kopie" }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let handle = await KopieStateBridge.waitForApp()
        guard let item = handle.state?.pasteNextFromQueue() else {
            return .result(value: "")
        }
        return .result(value: item.text ?? item.preview)
    }
}

// MARK: - App Shortcuts (Spotlight / Siri phrases)

@available(macOS 13.0, *)
struct KopieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestClipboardItem(),
            phrases: [
                "Get latest clipboard item in \(.applicationName)",
                "Latest copy in \(.applicationName)"
            ],
            shortTitle: "Get Latest Clipboard Item",
            systemImageName: "doc.on.clipboard")
        AppShortcut(
            intent: PasteNextFromQueue(),
            phrases: [
                "\u{201c}Paste Next\u{201d} from \(.applicationName)",
                "Paste queue in \(.applicationName)"
            ],
            shortTitle: "Paste Next From Queue",
            systemImageName: "arrow.down.to.line.compact")
        AppShortcut(
            intent: SearchHistoryIntent(),
            phrases: [
                "Search clipboard in \(.applicationName)",
                "Search history in \(.applicationName)"
            ],
            shortTitle: "Search Clipboard History",
            systemImageName: "magnifyingglass")
    }
}
