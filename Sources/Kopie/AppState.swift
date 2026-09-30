import SwiftUI
import KopieCore
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var isPaused: Bool = false
    /// Snapshot backing the main window's list. Views read this instead of
    /// querying the store during body evaluation (a query per render made
    /// selection clicks lag and let background captures reorder the list
    /// mid-interaction).
    @Published var mainItems: [ClipboardItem] = []
    private var mainFilter = QueryFilter()
    /// Images whose thumbnail generation already failed — never retried in a
    /// row render (a missing/corrupt file used to be re-decoded every pass).
    private var thumbGenFailed: Set<String> = []

    @Published var showOnboarding: Bool = false
    @Published var isReturnLaunch = false
    @Published var excludedApps: [SettingsStore.ExcludedApp] = []
    @Published var ambientSpeed: SettingsStore.AmbientSpeed = .slow
    let store: ClipStore
    private let writer: DiskClipWriter
    private let thumbGenerator: ThumbnailGenerator
    private lazy var historyExporter = HistoryExporter(store: store, writer: writer)
    private let pipeline: CapturePipeline
    private let restoreSVC: RestoreService
    private let monitor: ClipboardMonitor
    private let job: RetentionJob
    private let settings = SettingsStore.shared

    private static let thumbCache = NSCache<NSString, NSImage>()

    /// Loads (and caches) the thumbnail for an image item, falling back to the full image.
    /// Uses lazy generation: if no thumbnail exists, generates one on-demand.
    /// Generation failures are remembered in `thumbGenFailed` so a broken image
    /// isn't re-decoded on every row render.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if let rel = item.thumbRelPath ?? item.imageRelPath {
            let key = rel as NSString
            if let cached = Self.thumbCache.object(forKey: key) { return cached }
            if let img = writer.loadThumb(relPath: rel) {
                Self.thumbCache.setObject(img, forKey: key)
                return img
            }
        }
        // Lazy generation: try to generate thumbnail on-demand (once per image).
        if let imageRel = item.imageRelPath, !thumbGenFailed.contains(imageRel) {
            let hashHex = (imageRel as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
            if let thumbRel = thumbGenerator.generateThumbnailIfNeeded(imageRelPath: imageRel, hashHex: hashHex),
               let img = writer.loadThumb(relPath: thumbRel) {
                Self.thumbCache.setObject(img, forKey: thumbRel as NSString)
                return img
            }
            thumbGenFailed.insert(imageRel)
        }
        return nil
    }

    /// Loads (and caches) the full-resolution image for an image item, so the
    /// details panel shows the actual copied pixels instead of the 256px thumb.
    func fullImage(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let rel = item.imageRelPath else { return nil }
        let key = ("full:" + rel) as NSString
        if let cached = Self.thumbCache.object(forKey: key) { return cached }
        if let img = writer.loadThumb(relPath: rel) {
            Self.thumbCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }
    
    /// Loads rich text (RTF) data for an item, if available.
    func richText(for item: ClipboardItem) -> Data? {
        guard let rel = item.richTextRelPath else { return nil }
        return writer.loadRichText(relPath: rel)
    }

    // MARK: - Parsed rich text (off the main thread)

    /// Cached parse results keyed by item ID. `NSAttributedString(html:)`
    /// blocks on the nsattributedstringagent/WebKit round-trip and can wedge
    /// the main thread indefinitely (hang, 2026-09), so views must never call
    /// `RichTextRepresentation.resolve` directly — they read this cache and
    /// kick off `loadRich`, which parses once per item on a background task.
    @Published private(set) var richResolved: [Int64: RichTextRepresentation.Resolved] = [:]
    private var richInFlight: Set<Int64> = []

    /// The parsed result, or nil while the parse is still pending.
    func cachedRich(for item: ClipboardItem) -> RichTextRepresentation.Resolved? {
        richResolved[item.id]
    }

    /// Starts a background parse for `item` if it hasn't run yet. Safe (and
    /// cheap) to call from view bodies: it never parses on the calling
    /// thread, and repeated calls while a parse is in flight are no-ops.
    func loadRich(_ item: ClipboardItem, data: Data, isHTML: Bool) {
        guard richResolved[item.id] == nil, !richInFlight.contains(item.id) else { return }
        richInFlight.insert(item.id)
        let id = item.id
        let plain = item.text ?? item.preview
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = RichTextRepresentation.resolve(data: data, isHTML: isHTML, fallbackText: plain)
            await self?.finishRich(id: id, result: result)
        }
    }

    @MainActor
    private func finishRich(id: Int64, result: RichTextRepresentation.Resolved) {
        richResolved[id] = result
        richInFlight.remove(id)
    }

    init() {
        store = ClipStore()
        writer = DiskClipWriter()
        thumbGenerator = ThumbnailGenerator()
        let pipeline = CapturePipeline(store: store, writer: writer)
        let restore = RestoreService()
        let monitor = ClipboardMonitor(reader: { ClipboardReader.read() },
                                       handler: { [weak pipeline] c in
            guard let pipeline else { return }
            let cfg = SettingsStore.shared.captureConfig
            let r = pipeline.process(c, config: cfg)
            if case .captured = r { NotificationCenter.default.post(name: .kopieStoreChanged, object: nil) }
        })
        self.pipeline = pipeline; self.restoreSVC = restore; self.monitor = monitor
        self.job = RetentionJob(store: store)
        self.isPaused = settings.monitorPaused
        self.excludedApps = settings.excludedApps
        self.ambientSpeed = settings.ambientSpeed

        restore.onAboutToWrite = { [weak self] in self?.monitor.beginSuppression() }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .kopieStoreChanged, object: nil)
        // One-time migration: clean up text entries that were really image
        // copies (captured as URLs before the image-first reader fix).
        OneTimeCleanup(store: store, writer: writer).run()
        // Populate the main window's list snapshot before any view asks for it.
        refreshMain()
        // launch-time catch-up retention
        runRetentionPolicy()
        // Start monitoring immediately so copies made during onboarding or the
        // launch splash are captured. Idempotent: finishOnboarding() calls this
        // again, and startMonitoring() already no-ops when running.
        if settings.monitorPaused {
            isPaused = true
        } else {
            startMonitoring()
        }
        // First-ever launch shows the full interactive onboarding;
        // subsequent launches get a brief landing splash that auto-dismisses.
        if settings.hasSeenOnboarding {
            showOnboarding = true
            isReturnLaunch = true
        } else {
            showOnboarding = true
            isReturnLaunch = false
        }
        startRetentionTimer()
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
        retentionTimer?.invalidate()
    }

    nonisolated(unsafe) private var retentionTimer: Timer?
    private func startRetentionTimer() {
        retentionTimer?.invalidate()
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runRetentionPolicy() }
        }
        RunLoop.main.add(retentionTimer!, forMode: .common)
    }

    @objc private func storeChanged() { refresh() }

    // MARK: - Main-window query

    /// Re-runs the main-window query and republishes the result. Views read
    /// `mainItems` instead of querying the store in their bodies — a query
    /// per render made selection clicks lag and let background captures
    /// reorder the list mid-interaction.
    func refreshMain() {
        mainItems = store.query(mainFilter)
    }

    /// Applies the main window's filter + search text, then refreshes.
    func setMainQuery(_ filter: QueryFilter) {
        mainFilter = filter
        refreshMain()
    }

    func setAmbientSpeed(_ speed: SettingsStore.AmbientSpeed) {
        settings.ambientSpeed = speed
        ambientSpeed = speed
    }

    func addExcludedApp(bundleID: String, name: String) {
        guard !bundleID.isEmpty, !excludedApps.contains(where: { $0.id == bundleID }) else { return }
        excludedApps.append(SettingsStore.ExcludedApp(id: bundleID, name: name))
        settings.excludedApps = excludedApps
        refresh()
    }

    func removeExcludedApp(id: String) {
        excludedApps.removeAll { $0.id == id }
        settings.excludedApps = excludedApps
        refresh()
    }

    func storageStats() -> (count: Int64, bytes: Int64) {
        (store.count(), store.bytesUsed())
    }

    var storageError: String? { store.bootstrapError }

    /// Clears regenerable cache (in-memory thumbnails + thumbnail files).
    func clearCache() {
        Self.thumbCache.removeAllObjects()
        thumbGenFailed.removeAll()
        removeContents(of: StoragePaths.thumbsDir())
        refresh()
    }

    /// Removes every clipboard item and all stored image/thumbnail files.
    func clearAllData() {
        writer.removeFiles(relPaths: store.clearAll())
        Self.thumbCache.removeAllObjects()
        removeContents(of: StoragePaths.imagesDir())
        removeContents(of: StoragePaths.thumbsDir())
        removeContents(of: StoragePaths.rtfDir())
        refresh()
    }

    /// Deletes (best-effort) every file directly inside `dir`.
    private func removeContents(of dir: URL) {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
    }

    func refresh(filter: QueryFilter? = nil) {
        var f = QueryFilter()
        f.textQuery = searchText
        // Auto-detect regex: try to compile as regex, if valid use regex search.
        if !searchText.isEmpty {
            f.useRegex = searchText.isValidRegex
        }
        if let filter {
            f.kind = filter.kind
            f.bucket = filter.bucket
            f.favoritesOnly = filter.favoritesOnly
            f.pinnedOnly = filter.pinnedOnly
        }
        items = store.query(f)
        // Every mutation path calls refresh(); mirror the change into the main
        // window's snapshot so its list and detail panel stay in sync.
        refreshMain()
    }

    func startMonitoring() {
        let wasPaused = isPaused
        monitor.start(); isPaused = false; settings.monitorPaused = false
        // Only announce real user-facing pause→resume flips, never launch-time
        // auto-starts or redundant calls.
        if wasPaused { KopieNotifications.resumed() }
    }
    func pauseMonitoring() {
        let wasRunning = !isPaused
        monitor.stop(); isPaused = true; settings.monitorPaused = true
        if wasRunning { KopieNotifications.paused() }
    }

    func copyBack(_ item: ClipboardItem, plainTextOnly: Bool = false) {
        restoreSVC.restore(item, writer: writer, plainTextOnly: plainTextOnly)
        store.bumpAccessed(item.id)
        // One-time secrets: staging them onto the clipboard IS the use —
        // drop them from history so the code never lingers.
        if item.expiresAfterUse {
            writer.removeFiles(relPaths: store.delete([item.id]))
        }
        refresh()
    }

    /// Marks/unmarks an item for delete-after-next-paste.
    func toggleExpireAfterUse(_ item: ClipboardItem) {
        store.setExpiresAfterUse(item.id, !item.expiresAfterUse)
        refresh()
    }

    /// Saves an inline edit from the details panel: updates the stored text,
    /// re-derives the content hash (so re-copying dedupes) and the encrypted
    /// search index, then refreshes the UI.
    func updateText(_ item: ClipboardItem, to newText: String) {
        guard item.kind == .text,
              !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard store.updateText(item.id, newText) else { return }
        refresh()
    }
    // MARK: - Sequential paste queue

    /// Builds the queue from one or more items (order preserved as given).
    func enqueueForPaste(_ items: [ClipboardItem]) {
        let ids = items.map(\.id)
        guard !ids.isEmpty else { return }
        settings.pasteQueueIDs = (settings.pasteQueueIDs + ids).suffix(50)
    }

    /// Adds a single item to the paste queue.
    func enqueueForPaste(_ item: ClipboardItem) { enqueueForPaste([item]) }

    /// True when the item is waiting somewhere in the paste queue.
    func isQueuedForPaste(_ item: ClipboardItem) -> Bool {
        settings.pasteQueueIDs.contains(item.id)
    }

    /// True when the item is flagged for delete-after-next-paste.
    func isExpiredAfterUse(_ item: ClipboardItem) -> Bool {
        item.expiresAfterUse
    }

    /// Number of items still waiting in the paste queue.
    var pasteQueueCount: Int { settings.pasteQueueIDs.count }

    /// Stages the next queued item on the clipboard and simulates ⌘V in the
    /// frontmost app (if direct paste is enabled and permitted). Pops the item
    /// from the queue before pasting so a failed paste never loops.
    @discardableResult
    func pasteNextFromQueue() -> ClipboardItem? {
        var queue = settings.pasteQueueIDs
        guard let id = queue.first else { return nil }
        queue.removeFirst()
        settings.pasteQueueIDs = queue
        guard let item = store.get(id) else {
            // Queued item was deleted meanwhile — try the next one.
            return queue.isEmpty ? nil : pasteNextFromQueue()
        }
        copyBack(item)
        // Simulate ⌘V so the staged item lands in the frontmost app. Short
        // delay lets the target app process the pasteboard change. No
        // permission prompt from here — the item simply stays staged.
        if SettingsStore.shared.pasteDirect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = PasteDirectService.paste()
            }
        }
        return item
    }

    /// Drops everything waiting in the paste queue.
    func clearPasteQueue() { settings.pasteQueueIDs = [] }

    /// Newest item regardless of the UI's current search text (intent support).
    func latestItem() -> ClipboardItem? {
        store.query(QueryFilter()).first
    }

    /// Search used by the App Intents surface: substring search with the
    /// store's encrypted index when available.
    func searchItems(query: String, limit: Int) -> [ClipboardItem] {
        var f = QueryFilter()
        f.textQuery = query
        f.limit = limit
        if !query.isEmpty { f.useRegex = query.isValidRegex }
        return store.query(f)
    }

    /// Stages plain text on the system clipboard WITHOUT recording it in
    /// history (used by e.g. color-swatch copy actions). The monitor
    /// suppresses the resulting change, so nothing new is captured.
    func copyTextToClipboard(_ text: String) {
        monitor.beginSuppression()
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    /// Context-menu convenience: toggles the item's presence in the queue.
    func toggleQueued(_ item: ClipboardItem) {
        if isQueuedForPaste(item) {
            settings.pasteQueueIDs = settings.pasteQueueIDs.filter { $0 != item.id }
        } else {
            enqueueForPaste(item)
        }
    }

    func toggleFavorite(_ item: ClipboardItem) { store.setFavorite(item.id, !item.isFavorite); refresh() }
    func togglePin(_ item: ClipboardItem) { store.setPinned(item.id, !item.isPinned); refresh() }
    func remove(_ item: ClipboardItem) { remove([item.id]) }
    func remove(_ ids: [Int64]) {
        writer.removeFiles(relPaths: store.delete(ids))
        refresh()
    }
    func removeAll() {
        writer.removeFiles(relPaths: store.clearAll())
        Self.thumbCache.removeAllObjects()
        refresh()
        KopieNotifications.cleared()
    }

    func runRetentionPolicy() {
        let result = job.run(config: RetentionConfig(period: settings.retentionPeriod,
                                                     deleteFavorites: settings.autoDeleteFavorites))
        if !result.orphanedPaths.isEmpty {
            writer.removeFiles(relPaths: result.orphanedPaths)
        }
        // Unused one-time secrets are swept alongside retention (the hourly
        // timer covers them; restore-time deletion covers the used ones).
        let cutoff = Date.now.addingTimeInterval(-24 * 3600)
        let expiredPaths = store.purgeExpiredUnused(olderThan: cutoff)
        if !expiredPaths.isEmpty {
            writer.removeFiles(relPaths: expiredPaths)
        }
        refresh()
    }

    func finishOnboarding(retention: RetentionPeriod) {
        settings.retentionPeriod = retention
        settings.hasSeenOnboarding = true
        showOnboarding = false
        startMonitoring()
        runRetentionPolicy()
    }
    
    // MARK: - Export/Import
    
    func exportHistory(to url: URL) {
        do {
            try historyExporter.export(to: url)
            KopieNotifications.show(title: "Export Complete", message: "History exported successfully")
        } catch {
            KopieNotifications.show(title: "Export Failed", message: error.localizedDescription)
        }
    }
    
    func importHistory(from url: URL) {
        do {
            let count = try historyExporter.import(from: url)
            refresh()
            KopieNotifications.show(title: "Import Complete", message: "\(count) items imported")
        } catch {
            KopieNotifications.show(title: "Import Failed", message: error.localizedDescription)
        }
    }
}

extension Notification.Name { static let kopieStoreChanged = Notification.Name("kopieStoreChanged") }
