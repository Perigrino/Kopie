import XCTest
import Foundation
@testable import KopieCore

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "settings-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func store() -> SettingsStore { SettingsStore(userDefaults: defaults) }

    // MARK: - Defaults

    func test_defaults() {
        let s = store()
        XCTAssertEqual(s.saveText, true)
        XCTAssertEqual(s.saveImages, true)
        XCTAssertEqual(s.ignoreDuplicates, true)
        XCTAssertEqual(s.maxItems, 1000)
        XCTAssertEqual(s.retentionPeriod, .daySeven)
        XCTAssertEqual(s.autoDeleteFavorites, false)
        XCTAssertEqual(s.showMenuBarIcon, true)
        XCTAssertEqual(s.startMonitoring, true)
        XCTAssertEqual(s.hasSeenOnboarding, false)
        XCTAssertEqual(s.monitorPaused, false)
        XCTAssertEqual(s.excludedApps, [])
        XCTAssertEqual(s.hotkey, .default)
    }

    // MARK: - Round trip

    func test_roundTrip() {
        let s = store()
        s.saveText = false
        s.maxItems = 250
        s.retentionPeriod = .dayThirty
        s.showMenuBarIcon = false
        s.hotkey = HotKeySpec(keyCode: 12, modifiers: 0x0100)
        s.excludedApps = [.init(id: "com.example.app", name: "Example")]

        // A second store reading the same suite sees the persisted values.
        let s2 = store()
        XCTAssertEqual(s2.saveText, false)
        XCTAssertEqual(s2.maxItems, 250)
        XCTAssertEqual(s2.retentionPeriod, .dayThirty)
        XCTAssertEqual(s2.showMenuBarIcon, false)
        XCTAssertEqual(s2.hotkey, HotKeySpec(keyCode: 12, modifiers: 0x0100))
        XCTAssertEqual(s2.excludedApps, [.init(id: "com.example.app", name: "Example")])
    }

    // MARK: - Migration

    func test_migrationFromLegacyAppIDs() {
        defaults.set(["com.a", "com.b", "com.c"], forKey: SettingsStore.Keys.excludedAppIDs)
        let s = store()
        XCTAssertEqual(s.excludedApps.map(\.id), ["com.a", "com.b", "com.c"])
        // Legacy key is dropped after migration.
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.excludedAppIDs))
        // Schema version is stamped so migration never re-runs.
        XCTAssertEqual(defaults.integer(forKey: SettingsStore.Keys.schemaVersion),
                       SettingsStore.currentSchemaVersion)
    }

    func test_migrationDoesNotOverwriteExistingData() {
        let data = try! JSONEncoder().encode([SettingsStore.ExcludedApp(id: "com.kept", name: "Kept")])
        defaults.set(data, forKey: SettingsStore.Keys.excludedApps)
        defaults.set(["com.legacy"], forKey: SettingsStore.Keys.excludedAppIDs)
        let s = store()
        XCTAssertEqual(s.excludedApps, [.init(id: "com.kept", name: "Kept")])
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.excludedAppIDs))
    }

    func test_migrationRunsOnlyOnce() {
        defaults.set(["com.a"], forKey: SettingsStore.Keys.excludedAppIDs)
        _ = store()   // migrates
        defaults.set(["com.z"], forKey: SettingsStore.Keys.excludedAppIDs)  // simulate a late write
        _ = store()   // schema already current — must not migrate again
        XCTAssertEqual(defaults.stringArray(forKey: SettingsStore.Keys.excludedAppIDs), ["com.z"])
    }

    // MARK: - Type healing

    func test_healsWrongTypedValues() {
        defaults.set("definitely-not-a-bool", forKey: SettingsStore.Keys.saveText)
        defaults.set("also-not-an-int", forKey: SettingsStore.Keys.maxItems)
        let s = store()
        XCTAssertEqual(s.saveText, true)   // falls back to the default…
        XCTAssertEqual(s.maxItems, 1000)
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.saveText))   // …and the garbage is removed
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.maxItems))
    }

    func test_keepsValidValues() {
        defaults.set(false, forKey: SettingsStore.Keys.saveText)
        defaults.set(42, forKey: SettingsStore.Keys.maxItems)
        let s = store()
        XCTAssertEqual(s.saveText, false)
        XCTAssertEqual(s.maxItems, 42)
        XCTAssertNotNil(defaults.object(forKey: SettingsStore.Keys.saveText))
        XCTAssertNotNil(defaults.object(forKey: SettingsStore.Keys.maxItems))
    }

    // MARK: - Derived config

    func test_captureConfigReflectsSettings() {
        let s = store()
        s.saveText = false
        s.saveImages = true
        s.ignoreDuplicates = false
        s.maxItems = 25
        s.monitorPaused = true
        s.excludedApps = [.init(id: "com.blocked", name: "Blocked")]
        let cfg = s.captureConfig
        XCTAssertEqual(cfg.saveText, false)
        XCTAssertEqual(cfg.saveImages, true)
        XCTAssertEqual(cfg.ignoreDuplicates, false)
        XCTAssertEqual(cfg.maxItems, 25)
        XCTAssertEqual(cfg.paused, true)
        XCTAssertEqual(cfg.excludedAppIDs, ["com.blocked"])
    }

    // MARK: - Excluded app IDs

    func test_excludedAppIDsSetSyncsNames() {
        let s = store()
        s.excludedAppIDs = ["com.new"]
        XCTAssertEqual(s.excludedApps, [.init(id: "com.new", name: "com.new")])
        s.excludedAppIDs = ["com.new", "com.other"]
        XCTAssertEqual(s.excludedAppIDs, ["com.new", "com.other"])
        XCTAssertEqual(s.excludedApps.count, 2)
    }
}
