//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Spiral 1.0.1 → 1.0.2): settings 1.0.1 stored in a shape the
// 26.10 code no longer reads. The key and the JSON values are hardcoded, as in
// `UserSettingsTests`, so a rename breaks this test instead of the migration.

import Foundation
@testable import Spiral
import Testing

struct SpiralSettingsMigrationTests {
    private let store = VolatileUserDefaults()
    private let aliceSettings: UserSettings
    private let bobSettings: UserSettings

    init() {
        let appSettings = AppSettings(store: store)
        aliceSettings = appSettings.userSettings(for: "@alice:example.com")
        bobSettings = appSettings.userSettings(for: "@bob:example.com")
    }

    @Test(arguments: [("hide", false), ("show", false), ("current", true)])
    func roomListActivityVisibilityBecomesShowAllActivity(stored: String, expected: Bool) throws {
        try store.set(JSONEncoder().encode(stored), forKey: "roomListActivityVisibility")
        aliceSettings.account.showAllRoomListActivity = !expected

        aliceSettings.account.migrateRoomListActivityVisibility()

        #expect(aliceSettings.account.showAllRoomListActivity == expected)
        #expect(store.object(forKey: "roomListActivityVisibility") == nil)
        #expect(bobSettings.account.showAllRoomListActivity, "only the migrated account takes the value")
    }

    @Test
    func nothingStoredLeavesTheDefault() {
        aliceSettings.account.migrateRoomListActivityVisibility()

        #expect(aliceSettings.account.showAllRoomListActivity)
    }

    @Test
    func anUnreadableValueIsDroppedNotMigrated() throws {
        try store.set(JSONEncoder().encode("dimmed"), forKey: "roomListActivityVisibility")

        aliceSettings.account.migrateRoomListActivityVisibility()

        #expect(aliceSettings.account.showAllRoomListActivity)
        #expect(store.object(forKey: "roomListActivityVisibility") == nil)
    }
}
