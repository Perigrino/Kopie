import SwiftUI
import KopieCore
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var isPaused: Bool = false
    @Published var showOnboarding: Bool = false
    @Published var excludedApps: [SettingsStore.ExcludedApp] = []
    let store: ClipStore
    private let writer: DiskClipWriter
    private let pipeline: CapturePipeline
    private let restoreSVC: RestoreService
    private let monitor: ClipboardMonitor
    private let job: RetentionJob
    private let settings = SettingsStore.shared

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
        self.isPaused = settings.monitorPaused
        self.excludedApps = settings.excludedApps

        restore.onAboutToWrite = { [weak self] in self?.monitor.beginSuppression() }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .kopieStoreChanged, object: nil)
        // launch-time catch-up retention
        runRetentionPolicy()
        if !settings.hasSeenOnboarding { showOnboarding = true }
        else if settings.startMonitoring { monitor.start() }
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

    static func currentConfig() -> CaptureConfig {
        SettingsStore.shared.captureConfig
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
        let fm = FileManager.default
        for dir in [StoragePaths.thumbsDir()] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in files { try? fm.removeItem(at: f) }
            }
        }
        refresh()
    }

    /// Removes every clipboard item and all stored image/thumbnail files.
    func clearAllData() {
        store.clearAll()
        Self.thumbCache.removeAllObjects()
        let fm = FileManager.default
        for dir in [StoragePaths.imagesDir(), StoragePaths.thumbsDir()] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in files { try? fm.removeItem(at: f) }
            }
        }
        refresh()
    }

    func refresh(filter: QueryFilter? = nil) {
        var f = QueryFilter()
        f.textQuery = searchText
        if let filter { f.kind = filter.kind; f.bucket = filter.bucket; f.favoritesOnly = filter.favoritesOnly }
        items = store.query(f)
    }

    func startMonitoring() {
        monitor.start(); isPaused = false; settings.monitorPaused = false
        KopieNotifications.resumed()
    }
    func pauseMonitoring() {
        monitor.stop(); isPaused = true; settings.monitorPaused = true
        KopieNotifications.paused()
    }

    func copyBack(_ item: ClipboardItem) {
        restoreSVC.restore(item, writer: writer)
        store.bumpAccessed(item.id)
        refresh()
    }
    func toggleFavorite(_ item: ClipboardItem) { store.setFavorite(item.id, !item.isFavorite); refresh() }
    func remove(_ item: ClipboardItem) { store.delete([item.id]); refresh() }
    func remove(_ ids: [Int64]) { store.delete(ids); refresh() }
    func removeAll() {
        store.clearAll(); refresh()
        KopieNotifications.cleared()
    }

    func runRetentionPolicy() {
        job.run(config: RetentionConfig(period: settings.retentionPeriod,
                                        deleteFavorites: settings.autoDeleteFavorites))
        refresh()
    }

    func finishOnboarding(retention: RetentionPeriod) {
        settings.retentionPeriod = retention
        settings.hasSeenOnboarding = true
        showOnboarding = false
        startMonitoring()
        runRetentionPolicy()
    }
}

extension Notification.Name { static let kopieStoreChanged = Notification.Name("kopieStoreChanged") }
