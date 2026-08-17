import SwiftUI
import KopieCore
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var isPaused: Bool = false
    @Published var showOnboarding: Bool = false
    let store: ClipStore
    private let writer: DiskClipWriter
    private let pipeline: CapturePipeline
    private let restoreSVC: RestoreService
    private let monitor: ClipboardMonitor
    private let job: RetentionJob
    private let defaults = UserDefaults.standard

    static let pausedKey = "monitorPaused"

    private static let thumbCache = NSCache<NSString, NSImage>()

    /// Loads (and caches) the thumbnail for an image item, falling back to the full image.
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
        return nil
    }

    init() {
        store = ClipStore()
        writer = DiskClipWriter()
        let pipeline = CapturePipeline(store: store, writer: writer)
        let restore = RestoreService()
        let monitor = ClipboardMonitor(reader: { ClipboardReader.read() },
                                       handler: { [weak pipeline] c in
            guard let pipeline else { return }
            let cfg = AppState.currentConfig()
            let r = pipeline.process(c, config: cfg)
            if case .captured = r { NotificationCenter.default.post(name: .kopieStoreChanged, object: nil) }
        })
        self.pipeline = pipeline; self.restoreSVC = restore; self.monitor = monitor
        self.job = RetentionJob(store: store)
        self.isPaused = defaults.bool(forKey: Self.pausedKey)

        restore.onAboutToWrite = { [weak self] in self?.monitor.beginSuppression() }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .kopieStoreChanged, object: nil)
        // launch-time catch-up retention
        runRetentionPolicy(announce: false)
        if !defaults.bool(forKey: "hasSeenOnboarding") { showOnboarding = true }
        else { monitor.start() }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func storeChanged() { refresh() }

    static func currentConfig() -> CaptureConfig {
        let d = UserDefaults.standard
        return CaptureConfig(
            paused: d.bool(forKey: "monitorPaused"),
            saveText: d.object(forKey: "saveText") as? Bool ?? true,
            saveImages: d.object(forKey: "saveImages") as? Bool ?? true,
            ignoreDuplicates: d.object(forKey: "ignoreDuplicates") as? Bool ?? true,
            maxItems: d.object(forKey: "maxItems") as? Int ?? 1000,
            excludedAppIDs: Set(d.stringArray(forKey: "excludedAppIDs") ?? []))
    }

    func refresh(filter: QueryFilter? = nil) {
        var f = QueryFilter()
        f.textQuery = searchText
        if let filter { f.kind = filter.kind; f.bucket = filter.bucket; f.favoritesOnly = filter.favoritesOnly }
        items = store.query(f)
    }

    func startMonitoring() { monitor.start(); isPaused = false; UserDefaults.standard.set(false, forKey: Self.pausedKey) }
    func pauseMonitoring() { monitor.stop(); isPaused = true; UserDefaults.standard.set(true, forKey: Self.pausedKey) }

    func copyBack(_ item: ClipboardItem) {
        restoreSVC.restore(item, writer: writer)
        store.bumpAccessed(item.id)
        refresh()
    }
    func toggleFavorite(_ item: ClipboardItem) { store.setFavorite(item.id, !item.isFavorite); refresh() }
    func remove(_ item: ClipboardItem) { store.delete([item.id]); refresh() }
    func remove(_ ids: [Int64]) { store.delete(ids); refresh() }
    func removeAll() { store.clearAll(); refresh() }

    func runRetentionPolicy(announce: Bool) {
        let d = UserDefaults.standard
        let p = RetentionPeriod(rawValue: d.object(forKey: "retentionPeriod") as? Int ?? 7) ?? .daySeven
        let delFav = d.bool(forKey: "autoDeleteFavorites")
        job.run(config: RetentionConfig(period: p, deleteFavorites: delFav))
        refresh()
        _ = announce
    }

    func finishOnboarding(retention: RetentionPeriod) {
        UserDefaults.standard.set(retention.rawValue, forKey: "retentionPeriod")
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        showOnboarding = false
        startMonitoring()
    }
}

extension Notification.Name { static let kopieStoreChanged = Notification.Name("kopieStoreChanged") }
