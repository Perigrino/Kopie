import SwiftUI
import KopieCore
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText: String = ""
    @Published var isPaused: Bool = false

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
        // Lazy generation: try to generate thumbnail on-demand
        if let imageRel = item.imageRelPath {
            let hashHex = (imageRel as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
            if let thumbRel = thumbGenerator.generateThumbnailIfNeeded(imageRelPath: imageRel, hashHex: hashHex) {
                if let img = writer.loadThumb(relPath: thumbRel) {
                    let key = thumbRel as NSString
                    Self.thumbCache.setObject(img, forKey: key)
                    return img
                }
            }
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
        // launch-time catch-up retention
        runRetentionPolicy()
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
        // Auto-detect regex: try to compile as regex, if valid use regex search
        if !searchText.isEmpty {
            f.useRegex = searchText.isValidRegex
        }
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
    func togglePin(_ item: ClipboardItem) { store.setPinned(item.id, !item.isPinned); refresh() }
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
