import Foundation

/// Central, typed access to every persisted app setting.
///
/// All `UserDefaults` keys are declared once in `Keys`; callers never touch
/// raw strings. A schema version drives forward migrations (see `migrateIfNeeded`).
/// Thread safety: state lives inside `UserDefaults`, which is thread-safe.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    // MARK: - Keys

    public enum Keys {
        public static let schemaVersion = "settingsSchemaVersion"
        public static let monitorPaused = "monitorPaused"
        public static let saveText = "saveText"
        public static let saveImages = "saveImages"
        public static let ignoreDuplicates = "ignoreDuplicates"
        public static let maxItems = "maxItems"
        public static let excludedApps = "excludedApps"
        /// Legacy pre-store key (string array of bundle IDs); migrated to `excludedApps` JSON.
        public static let excludedAppIDs = "excludedAppIDs"
        public static let retentionPeriod = "retentionPeriod"
        public static let autoDeleteFavorites = "autoDeleteFavorites"
        public static let launchAtLogin = "launchAtLogin"
        public static let showMenuBarIcon = "showMenuBarIcon"
        public static let startMonitoring = "startMonitoring"
        public static let hasSeenOnboarding = "hasSeenOnboarding"
        public static let hotkey = "hotkey"
    }

    /// Bump when adding a new migration step.
    public static let currentSchemaVersion = 1

    /// An app excluded from capture, stored as JSON under `Keys.excludedApps`.
    public struct ExcludedApp: Codable, Equatable, Identifiable, Sendable {
        public let id: String        // bundle identifier
        public var name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        migrateIfNeeded()
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        let stored = defaults.integer(forKey: Keys.schemaVersion)
        guard stored < Self.currentSchemaVersion else { return }
        // v0 → v1: backfill JSON excludedApps from the legacy string-array key.
        if defaults.data(forKey: Keys.excludedApps) == nil,
           let legacy = defaults.stringArray(forKey: Keys.excludedAppIDs), !legacy.isEmpty {
            let apps = legacy.map { ExcludedApp(id: $0, name: $0) }
            if let data = try? JSONEncoder().encode(apps) {
                defaults.set(data, forKey: Keys.excludedApps)
            }
        }
        defaults.set(Self.currentSchemaVersion, forKey: Keys.schemaVersion)
    }

    // MARK: - Typed accessors

    public var retentionPeriod: RetentionPeriod {
        get {
            guard let raw = defaults.object(forKey: Keys.retentionPeriod) as? Int,
                  let period = RetentionPeriod(rawValue: raw) else {
                return .daySeven
            }
            return period
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.retentionPeriod) }
    }

    public var monitorPaused: Bool {
        get { defaults.bool(forKey: Keys.monitorPaused) }
        set { defaults.set(newValue, forKey: Keys.monitorPaused) }
    }

    public var saveText: Bool {
        get { defaults.object(forKey: Keys.saveText) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveText) }
    }

    public var saveImages: Bool {
        get { defaults.object(forKey: Keys.saveImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveImages) }
    }

    public var ignoreDuplicates: Bool {
        get { defaults.object(forKey: Keys.ignoreDuplicates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.ignoreDuplicates) }
    }

    public var maxItems: Int {
        get { defaults.object(forKey: Keys.maxItems) as? Int ?? 1000 }
        set { defaults.set(newValue, forKey: Keys.maxItems) }
    }

    public var excludedApps: [ExcludedApp] {
        get {
            guard let data = defaults.data(forKey: Keys.excludedApps),
                  let list = try? JSONDecoder().decode([ExcludedApp].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.excludedApps)
            }
        }
    }

    /// Bundle IDs of excluded apps, kept in sync with `excludedApps` on write.
    public var excludedAppIDs: Set<String> {
        get { Set(excludedApps.map { $0.id }) }
        set {
            let existing = excludedApps
            let merged = existing.filter { newValue.contains($0.id) } +
                newValue.subtracting(existing.map { $0.id }).map { ExcludedApp(id: $0, name: $0) }
            excludedApps = merged
        }
    }

    public var autoDeleteFavorites: Bool {
        get { defaults.bool(forKey: Keys.autoDeleteFavorites) }
        set { defaults.set(newValue, forKey: Keys.autoDeleteFavorites) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    public var showMenuBarIcon: Bool {
        get { defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showMenuBarIcon) }
    }

    public var startMonitoring: Bool {
        get { defaults.object(forKey: Keys.startMonitoring) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.startMonitoring) }
    }

    public var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasSeenOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasSeenOnboarding) }
    }

    public var hotkey: HotKeySpec {
        get {
            guard let data = defaults.data(forKey: Keys.hotkey),
                  let spec = try? JSONDecoder().decode(HotKeySpec.self, from: data) else {
                return .default
            }
            return spec
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.hotkey)
            }
        }
    }

    /// The capture configuration derived from the current settings.
    public var captureConfig: CaptureConfig {
        CaptureConfig(
            paused: monitorPaused,
            saveText: saveText,
            saveImages: saveImages,
            ignoreDuplicates: ignoreDuplicates,
            maxItems: maxItems,
            excludedAppIDs: excludedAppIDs)
    }
}
