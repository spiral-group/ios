//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3): which of upstream's launch migrations a Spiral update
// runs. The thresholds mirror `AppCoordinator`'s `performMigrationsIfNecessary`
// (app-wide) and `performUserSessionMigrations` (per account).
//

@testable import Spiral
import Testing
import Version

struct UpstreamMigrationBaselineTests {
    private let expireSyncSessions = Version(25, 9, 2)
    private let showNewSoundBanner = Version(25, 10, 0)
    private let appThresholds = [Version(1, 6, 7), Version(25, 7, 4), Version(26, 10, 2)]
    private let accountThresholds = [Version(1, 6, 0), Version(25, 6, 0), Version(25, 9, 2), Version(25, 10, 0),
                                     Version(26, 10, 1), Version(26, 10, 2), Version(26, 10, 3), Version(26, 10, 4)]
    private let accountThresholds2610 = [Version(26, 10, 1), Version(26, 10, 2), Version(26, 10, 3), Version(26, 10, 4)]

    @Test
    func updatingFrom102RunsNoUpstreamMigration() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(1, 0, 2), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(!account.runs(expireSyncSessions), "every account's sync would be reset")
        #expect(!account.runs(showNewSoundBanner), "the new sound banner would come back")
        #expect(accountThresholds.filter(account.runs).isEmpty)
        #expect(appThresholds.filter(launch.runs).isEmpty)
        #expect(launch.needsMigrations, "the per-update housekeeping still runs")
    }

    @Test
    func updatingFrom101RunsOnlyThe2610Migrations() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(1, 0, 1), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(launch.appliedRelease == Version(26, 8, 1))
        #expect(appThresholds.filter(launch.runs) == [Version(26, 10, 2)])
        #expect(accountThresholds.filter(account.runs) == accountThresholds2610)
    }

    @Test
    func updatingFrom100RunsWhatItsOldestUpstreamLacked() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(1, 0, 0), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(launch.appliedRelease == Version(26, 4, 2))
        #expect(accountThresholds.filter(account.runs) == accountThresholds2610)
    }

    @Test
    func aPreRebrandBuildMigratesFromItsOwnUpstreamVersion() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(25, 9, 0), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(account.runs(expireSyncSessions))
        #expect(!launch.runs(Version(25, 7, 4)))
    }

    @Test
    func aFreshInstallMigratesNothing() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: nil, appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(!launch.needsMigrations)
        #expect(!account.needsMigrations)
        #expect(accountThresholds.filter(account.runs).isEmpty)
    }

    @Test
    func anAccountNotRestoredOnTheUpdatesLaunchMigratesOnTheNext() {
        let update = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(1, 0, 1), appVersion: Version(1, 0, 3))
        // The launch ends before the account is restored, so the account's marker is never written.
        let nextLaunch = UpstreamMigrationBaseline(marker: update.markerAfterLaunch, accountFallback: update.accountFallbackAfterLaunch,
                                                   previousAppVersion: Version(1, 0, 3), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: nextLaunch.accountFallbackAfterLaunch)
        let afterAccountMigrated = UpstreamMigrationBaseline.Account(marker: account.markerAfterMigrations, fallback: nextLaunch.accountFallbackAfterLaunch)

        #expect(!nextLaunch.needsMigrations, "the app-wide ones already ran")
        #expect(account.needsMigrations)
        #expect(accountThresholds.filter(account.runs) == accountThresholds2610, "sharing presence and notifications would fall back to on")
        #expect(!afterAccountMigrated.needsMigrations)
    }

    @Test
    func theMarkerWinsOverTheAppVersion() {
        let launch = UpstreamMigrationBaseline(marker: "26.10.8", accountFallback: "26.8.1", previousAppVersion: Version(1, 0, 1), appVersion: Version(1, 0, 4))
        let account = UpstreamMigrationBaseline.Account(marker: "26.10.8", fallback: launch.accountFallbackAfterLaunch)

        #expect(appThresholds.filter(launch.runs).isEmpty)
        #expect(accountThresholds.filter(account.runs).isEmpty)
        #expect(launch.accountFallbackAfterLaunch == "26.8.1", "the fallback is kept once set")
    }

    @Test
    func aMigrationAddedByAnUpstreamSyncRunsOnce() {
        let synced = Version(26, 11, 5)
        let newThreshold = Version(26, 11, 2)
        let firstLaunch = UpstreamMigrationBaseline(marker: "26.10.8", accountFallback: "26.10.8",
                                                    previousAppVersion: Version(1, 0, 3), appVersion: Version(1, 0, 4), syncedRelease: synced)
        let nextUpdate = UpstreamMigrationBaseline(marker: firstLaunch.markerAfterLaunch, accountFallback: firstLaunch.accountFallbackAfterLaunch,
                                                   previousAppVersion: Version(1, 0, 4), appVersion: Version(1, 0, 5), syncedRelease: synced)
        let account = UpstreamMigrationBaseline.Account(marker: "26.10.8", fallback: firstLaunch.accountFallbackAfterLaunch, syncedRelease: synced)
        let accountNextUpdate = UpstreamMigrationBaseline.Account(marker: account.markerAfterMigrations, fallback: nextUpdate.accountFallbackAfterLaunch,
                                                                  syncedRelease: synced)

        #expect(firstLaunch.runs(newThreshold))
        #expect(!nextUpdate.runs(newThreshold))
        #expect(account.runs(newThreshold))
        #expect(!accountNextUpdate.runs(newThreshold))
    }

    @Test
    func anUpstreamSyncWithoutAVersionBumpStillMigrates() {
        let synced = Version(26, 11, 5)
        let sameVersion = UpstreamMigrationBaseline(marker: "26.10.8", accountFallback: "26.10.8",
                                                    previousAppVersion: Version(1, 0, 4), appVersion: Version(1, 0, 4), syncedRelease: synced)
        let nothingNew = UpstreamMigrationBaseline(marker: "26.11.5", accountFallback: "26.10.8",
                                                   previousAppVersion: Version(1, 0, 4), appVersion: Version(1, 0, 4), syncedRelease: synced)

        #expect(sameVersion.needsMigrations)
        #expect(!nothingNew.needsMigrations)
        #expect(UpstreamMigrationBaseline.Account(marker: "26.10.8", fallback: nil, syncedRelease: synced).needsMigrations)
    }

    @Test
    func theMarkersRecordTheSyncedRelease() {
        let launch = UpstreamMigrationBaseline(marker: nil, accountFallback: nil, previousAppVersion: Version(1, 0, 2), appVersion: Version(1, 0, 3))
        let account = UpstreamMigrationBaseline.Account(marker: nil, fallback: launch.accountFallbackAfterLaunch)

        #expect(launch.markerAfterLaunch == "26.10.8")
        #expect(account.markerAfterMigrations == "26.10.8")
        #expect((appThresholds + accountThresholds).allSatisfy { $0 <= UpstreamMigrationBaseline.syncedRelease })
    }
}
