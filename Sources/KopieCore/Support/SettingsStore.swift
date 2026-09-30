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
        public static let appearance = "appearance"
        public static let hasSeenOnboarding = "hasSeenOnboarding"
        public static let hotkey = "hotkey"
        public static let ambientSpeed = "ambientSpeed"
        public static let trackSourceApp = "trackSourceApp"
        public static let ocrImages = "ocrImages"
        public static let pasteDirect = "pasteDirect"
        public static let pasteAsPlainText = "pasteAsPlainText"
        public static let pasteQueueIDs = "pasteQueueIDs"
        public static let splitPosition = "splitPosition"
        public static let showMenuBarPreview = "showMenuBarPreview"
        public static let sensitiveDataPolicy = "sensitiveDataPolicy"
        public static let sensitiveDisabledRules = "sensitiveDisabledRules"
        public static let autoExpireOneTimeSecrets = "autoExpireOneTimeSecrets"
        public static let screenShieldMode = "screenShieldMode"
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
    /// App-wide appearance: follow the system, or force light/dark.
    public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
        case system, light, dark
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
        /// SF Symbol for menu items / buttons.
        public var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
    }

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
                        Keys.showMenuBarIcon, Keys.hasSeenOnboarding,
                        Keys.trackSourceApp, Keys.ocrImages, Keys.pasteDirect, Keys.pasteAsPlainText,
                        Keys.showMenuBarPreview, Keys.autoExpireOneTimeSecrets]
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
        if let value = defaults.object(forKey: Keys.appearance), value as? String == nil {
            defaults.removeObject(forKey: Keys.appearance)
        }
        // Enum raw values that no longer decode are dead data — drop them so
        // accessors fall back to their default.
        if let raw = defaults.string(forKey: Keys.appearance), AppAppearance(rawValue: raw) == nil {
            defaults.removeObject(forKey: Keys.appearance)
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

    /// Floating hover-preview bubble beside the menu-bar popover's item list.
    public var showMenuBarPreview: Bool {
        get { defaults.object(forKey: Keys.showMenuBarPreview) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showMenuBarPreview) }
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

    /// App-wide appearance (light/dark/system). Defaults to following the system.
    public var appearance: AppAppearance {
        get {
            guard let raw = defaults.object(forKey: Keys.appearance) as? String,
                  let mode = AppAppearance(rawValue: raw) else {
                return .system
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.appearance) }
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

    public var trackSourceApp: Bool {
        get { defaults.object(forKey: Keys.trackSourceApp) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.trackSourceApp) }
    }

    /// On-device OCR of image copies so screenshots become searchable by their text.
    public var ocrImages: Bool {
        get { defaults.object(forKey: Keys.ocrImages) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.ocrImages) }
    }

    /// Enables ⌥↩ / ⌥-click / ⌥1-9 direct paste into the frontmost app
    /// (simulated ⌘V via the Accessibility permission).
    public var pasteDirect: Bool {
        get { defaults.object(forKey: Keys.pasteDirect) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.pasteDirect) }
    }

    /// When true, copying an item back stages only the plain-text flavor,
    /// stripping rich text (RTF/HTML) so target apps receive unstyled text.
    public var pasteAsPlainText: Bool {
        get { defaults.object(forKey: Keys.pasteAsPlainText) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.pasteAsPlainText) }
    }

    /// Item IDs queued for sequential pasting, in order. Survives launches so
    /// a queue built yesterday still pastes today.
    public var pasteQueueIDs: [Int64] {
        get {
            // New writes are JSON Data; legacy array-style values still read.
            if let data = defaults.data(forKey: Keys.pasteQueueIDs),
               let arr = try? JSONDecoder().decode([Int64].self, from: data) {
                return arr
            }
            if let arr = defaults.array(forKey: Keys.pasteQueueIDs) as? [Int] {
                return arr.map(Int64.init)
            }
            return []
        }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: Keys.pasteQueueIDs)
            } else if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.pasteQueueIDs)
            }
        }
    }

    /// Stores the horizontal split position (0…1) of the main view's list/detail divider.
    public var splitPosition: Double {
        get { let v = defaults.double(forKey: Keys.splitPosition); return v > 0 ? v : 0.4 }
        set { defaults.set(newValue, forKey: Keys.splitPosition) }
    }

    // MARK: - Sensitive-data sentinel

    /// What happens when copied content matches a secret rule.
    /// Default `.mask`: store it, but render masked until revealed.
    public var sensitiveDataPolicy: SensitiveDataPolicy {
        get {
            guard let raw = defaults.string(forKey: Keys.sensitiveDataPolicy),
                  let policy = SensitiveDataPolicy(rawValue: raw) else { return .mask }
            return policy
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.sensitiveDataPolicy) }
    }

    /// Rule ids the user turned off in Settings → Privacy.
    public var sensitiveDisabledRules: Set<String> {
        get {
            guard let data = defaults.data(forKey: Keys.sensitiveDisabledRules),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(list)
        }
        set {
            let list = Array(newValue).sorted()
            if list.isEmpty {
                defaults.removeObject(forKey: Keys.sensitiveDisabledRules)
            } else if let data = try? JSONEncoder().encode(list) {
                defaults.set(data, forKey: Keys.sensitiveDisabledRules)
            }
        }
    }

    public var sensitiveEnabledRules: Set<String> {
        SensitiveDataDetector.allRuleIDs.subtracting(sensitiveDisabledRules)
    }

    /// Auto-flag OTPs / magic links for delete-after-next-paste (Phase 2).
    public var autoExpireOneTimeSecrets: Bool {
        get { defaults.object(forKey: Keys.autoExpireOneTimeSecrets) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoExpireOneTimeSecrets) }
    }

    /// When Kopie's windows should be invisible to screen capture
    /// (screenshots, screen sharing, recording).
    public var screenShieldMode: ScreenShieldMode {
        get {
            guard let raw = defaults.string(forKey: Keys.screenShieldMode),
                  let mode = ScreenShieldMode(rawValue: raw) else { return .whenConferencing }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.screenShieldMode) }
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
            excludedAppIDs: excludedAppIDs,
            trackSourceApp: trackSourceApp,
            ocrImages: ocrImages,
            sensitivePolicy: sensitiveDataPolicy,
            sensitiveEnabledRules: sensitiveEnabledRules,
            autoExpireOneTime: autoExpireOneTimeSecrets)
    }
}
