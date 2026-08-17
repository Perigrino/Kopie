import Foundation

/// Central, typed access to every persisted app setting.
///
/// All `UserDefaults` keys are declared once in `Keys`; callers never touch raw
/// strings. A schema version drives forward migrations (see `migrateIfNeeded`),
/// and a type-healing pass removes values that were stored under the wrong type
/// so accessors always fall back to sane defaults.
///
/// Thread safety: state lives inside `UserDefaults`, which is thread-safe.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    // MARK: - Keys (single source of truth)

    public enum Keys {
        public static let schemaVersion = "settingsSchemaVersion"
        public static let monitorPaused = "monitorPaused"
        public static let saveText = "saveText"
        public static let saveImages = "saveImages"
        public static let saveFiles = "saveFiles"
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
        public static let ambientSpeed = "ambientSpeed"
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

    /// Ambient landing animation speed. All ambient motion (background breath,
    /// orb drift and scale, twinkles, particles) shares one cycle; `off` makes
    /// the whole scene static while keeping the pastel gradient.
    public enum AmbientSpeed: String, CaseIterable, Codable, Identifiable, Sendable {
        case off, slow, medium, fast

        public var id: String { rawValue }

        /// Seconds per breath cycle; `nil` means no ambient motion.
        public var cycle: Double? {
            switch self {
            case .off: return nil
            case .slow: return 30
            case .medium: return 18
            case .fast: return 10
            }
        }

        public var label: String {
            switch self {
            case .off: return "Off"
            case .slow: return "Slow"
            case .medium: return "Medium"
            case .fast: return "Fast"
            }
        }
    }

    private let defaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        healInvalidTypes()
        migrateIfNeeded()
    }

    // MARK: - Migration & healing

    private func migrateIfNeeded() {
        let stored = defaults.integer(forKey: Keys.schemaVersion)
        guard stored < Self.currentSchemaVersion else { return }
        // v0 → v1: backfill JSON excludedApps from the legacy string-array key,
        // then drop the legacy key.
        if defaults.data(forKey: Keys.excludedApps) == nil,
           let legacy = defaults.stringArray(forKey: Keys.excludedAppIDs), !legacy.isEmpty {
            let apps = legacy.map { ExcludedApp(id: $0, name: $0) }
            if let data = try? JSONEncoder().encode(apps) {
                defaults.set(data, forKey: Keys.excludedApps)
            }
        }
        defaults.removeObject(forKey: Keys.excludedAppIDs)
        defaults.set(Self.currentSchemaVersion, forKey: Keys.schemaVersion)
    }

    /// Removes stored values whose type does not match the key's contract, so
    /// accessors always resolve to defaults instead of silently misreading.
    private func healInvalidTypes() {
        let boolKeys = [Keys.monitorPaused, Keys.saveText, Keys.saveImages, Keys.saveFiles,
                        Keys.ignoreDuplicates, Keys.autoDeleteFavorites, Keys.launchAtLogin,
                        Keys.showMenuBarIcon, Keys.startMonitoring, Keys.hasSeenOnboarding]
        for key in boolKeys {
            if let value = defaults.object(forKey: key), value as? Bool == nil {
                defaults.removeObject(forKey: key)
            }
        }
        for key in [Keys.maxItems, Keys.retentionPeriod] {
            if let value = defaults.object(forKey: key), value as? Int == nil {
                defaults.removeObject(forKey: key)
            }
        }
        for key in [Keys.excludedApps, Keys.hotkey] {
            if let value = defaults.object(forKey: key), value as? Data == nil {
                defaults.removeObject(forKey: key)
            }
        }
        if let value = defaults.object(forKey: Keys.ambientSpeed), value as? String == nil {
            defaults.removeObject(forKey: Keys.ambientSpeed)
        }
        if let value = defaults.object(forKey: Keys.excludedAppIDs), value as? [String] == nil {
            defaults.removeObject(forKey: Keys.excludedAppIDs)
        }
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

    public var saveFiles: Bool {
        get { defaults.object(forKey: Keys.saveFiles) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.saveFiles) }
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

    /// Bundle IDs of excluded apps, derived from `excludedApps`.
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

    public var ambientSpeed: AmbientSpeed {
        get {
            guard let raw = defaults.object(forKey: Keys.ambientSpeed) as? String,
                  let speed = AmbientSpeed(rawValue: raw) else {
                return .slow
            }
            return speed
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.ambientSpeed) }
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
            saveFiles: saveFiles,
            ignoreDuplicates: ignoreDuplicates,
            maxItems: maxItems,
            excludedAppIDs: excludedAppIDs)
    }
}
