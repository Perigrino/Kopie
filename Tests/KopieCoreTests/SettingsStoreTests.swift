import XCTest
import KopieCore

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = SettingsStore(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_defaults() {
        XCTAssertEqual(store.retentionPeriod, .daySeven)
        XCTAssertEqual(store.maxItems, 1000)
        XCTAssertTrue(store.saveText)
        XCTAssertTrue(store.saveImages)
        XCTAssertTrue(store.ignoreDuplicates)
        XCTAssertTrue(store.showMenuBarIcon)
        XCTAssertTrue(store.startMonitoring)
        XCTAssertFalse(store.monitorPaused)
        XCTAssertFalse(store.autoDeleteFavorites)
        XCTAssertFalse(store.hasSeenOnboarding)
        XCTAssertEqual(store.hotkey, .default)
        XCTAssertEqual(store.excludedApps, [])
        let cfg = store.captureConfig
        XCTAssertEqual(cfg.maxItems, 1000)
        XCTAssertTrue(cfg.saveText)
        XCTAssertTrue(cfg.saveImages)
        XCTAssertTrue(cfg.ignoreDuplicates)
        XCTAssertFalse(cfg.paused)
        XCTAssertTrue(cfg.excludedAppIDs.isEmpty)
    }

    func test_typedRoundTrips() {
        store.retentionPeriod = .dayNinety
        XCTAssertEqual(store.retentionPeriod, .dayNinety)
        store.maxItems = 250
        XCTAssertEqual(store.maxItems, 250)
        store.saveText = false
        XCTAssertFalse(store.saveText)
        store.monitorPaused = true
        XCTAssertTrue(store.monitorPaused)
        store.autoDeleteFavorites = true
        XCTAssertTrue(store.autoDeleteFavorites)
        store.showMenuBarIcon = false
        XCTAssertFalse(store.showMenuBarIcon)
        store.startMonitoring = false
        XCTAssertFalse(store.startMonitoring)
        store.hasSeenOnboarding = true
        XCTAssertTrue(store.hasSeenOnboarding)
    }

    func test_excludedAppsRoundTrip() {
        store.excludedApps = [
            .init(id: "com.1password", name: "1Password"),
            .init(id: "com.apple.keychainaccess", name: "Keychain Access"),
        ]
        // Fresh store over the same defaults reads them back.
        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.excludedApps.count, 2)
        XCTAssertEqual(reloaded.excludedApps[0].id, "com.1password")
        XCTAssertEqual(reloaded.excludedAppIDs, ["com.1password", "com.apple.keychainaccess"])
    }

    func test_captureConfigReflectsSettings() {
        store.maxItems = 50
        store.excludedApps = [.init(id: "com.1password", name: "1Password")]
        let cfg = store.captureConfig
        XCTAssertEqual(cfg.maxItems, 50)
        XCTAssertTrue(cfg.excludedAppIDs.contains("com.1password"))
        XCTAssertEqual(cfg.paused, store.monitorPaused)
    }

    func test_hotkeyRoundTrip() {
        store.hotkey = HotKeySpec(keyCode: 8, modifiers: 0x0100 | 0x0800) // ⌘⌥C
        let reloaded = SettingsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.hotkey.keyCode, 8)
        XCTAssertEqual(reloaded.hotkey.modifiers, 0x0100 | 0x0800)
    }

    func test_migration_fromLegacyExcludedAppIDs() {
        // Fresh domain untouched by setUp's store, simulating a pre-store install.
        let fresh = makeFreshDefaults()
        fresh.set(["com.1password", "com.banks.app"], forKey: SettingsStore.Keys.excludedAppIDs)
        let migrated = SettingsStore(userDefaults: fresh)
        XCTAssertEqual(migrated.excludedApps.map { $0.id }, ["com.1password", "com.banks.app"])
        XCTAssertEqual(migrated.excludedAppIDs, ["com.1password", "com.banks.app"])
        XCTAssertEqual(fresh.integer(forKey: SettingsStore.Keys.schemaVersion),
                       SettingsStore.currentSchemaVersion)
    }

    func test_migration_isIdempotent() {
        let fresh = makeFreshDefaults()
        fresh.set(["com.1password"], forKey: SettingsStore.Keys.excludedAppIDs)
        _ = SettingsStore(userDefaults: fresh)
        let again = SettingsStore(userDefaults: fresh)
        XCTAssertEqual(again.excludedApps.map { $0.id }, ["com.1password"])
        XCTAssertEqual(again.excludedApps.count, 1)
    }

    /// A pristine UserDefaults domain, removed on tearDown via `removePersistentDomain`
    /// (kept on disk until then so the store sees a consistent domain).
    private func makeFreshDefaults() -> UserDefaults {
        let name = "SettingsStoreTests_fresh_\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
}
