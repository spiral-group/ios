//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3; docs DEBT.md § 1.0.2 sync, N9: "upstream's version-gated
// migrations re-run on every Spiral upgrade"): upstream's launch migrations are
// gated on Element X release numbers, but our marketing version is 1.0.x — below
// every threshold — so each Spiral update replayed all of them (sync reset, log
// moves, the "new sound" banner). They now compare the upstream release whose
// migrations have already run: app-wide ones per install, the rest per account.
//

import Version

/// Which of upstream's version-gated app-wide launch migrations an install still needs.
nonisolated struct UpstreamMigrationBaseline: Equatable {
    /// The Element X release this code was merged from (the comment beside
    /// `MARKETING_VERSION` in `project.yml`). Bump it in every upstream sync, or
    /// the sync's new migrations run again on every later update.
    static let syncedRelease = Version(26, 10, 8)

    /// Compare upstream's app-wide thresholds with this, never with the app's own version.
    let appliedRelease: Version
    /// Whether this launch has anything to do: housekeeping for an app update, or an upstream migration.
    let needsMigrations: Bool

    /// Persist as `AppSettings.upstreamMigrationsVersion` once this launch's app-wide migrations ran.
    let markerAfterLaunch: String
    /// Persist as `AppSettings.upstreamAccountMigrationsFallback`: where an account without its own
    /// marker starts. Set by the first launch that knows about markers and kept from then on.
    let accountFallbackAfterLaunch: String

    /// - Parameters:
    ///   - marker: `AppSettings.upstreamMigrationsVersion`, `nil` before 1.0.3.
    ///   - accountFallback: `AppSettings.upstreamAccountMigrationsFallback`, `nil` before 1.0.3.
    ///   - previousAppVersion: `AppSettings.lastVersionLaunched`, `nil` on a fresh install, which migrates nothing.
    ///   - appVersion: the running app's marketing version.
    ///   - syncedRelease: overridable for tests.
    init(marker: String?, accountFallback: String?, previousAppVersion: Version?, appVersion: Version, syncedRelease: Version = Self.syncedRelease) {
        markerAfterLaunch = syncedRelease.description

        guard let previousAppVersion else {
            appliedRelease = syncedRelease
            needsMigrations = false
            accountFallbackAfterLaunch = syncedRelease.description
            return
        }

        appliedRelease = marker.flatMap(Version.init) ?? Self.release(launchedBy: previousAppVersion)
        needsMigrations = previousAppVersion != appVersion || appliedRelease < syncedRelease
        accountFallbackAfterLaunch = accountFallback ?? appliedRelease.description
    }

    /// Whether upstream's `if oldVersion < threshold` migration runs on this launch.
    func runs(_ threshold: Version) -> Bool {
        appliedRelease < threshold
    }

    /// Before the marker existed, the last launched app version tells which upstream release's
    /// migrations had run, from the release each Spiral version was merged from (git history):
    /// - Fork builds before 1.0.0 carried upstream's own calendar version (25.x, 26.x).
    /// - 1.0.0 (2026-05-10 on, `ios-1.0.0-b*`) was built from release/26.04.2 up to 26.08.1; the oldest counts.
    /// - 1.0.1 (`ios-1.0.1-b2`…`b5`) from release/26.08.1, so it never had the 26.10.x migrations.
    /// - 1.0.2 (`ios-1.0.2-b2`) from release/26.10.8; a pre-marker 1.0.3 dev build is the same code.
    private static func release(launchedBy appVersion: Version) -> Version {
        if appVersion.major >= 25 {
            appVersion
        } else if appVersion < Version(1, 0, 1) {
            Version(26, 4, 2)
        } else if appVersion < Version(1, 0, 2) {
            Version(26, 8, 1)
        } else {
            Version(26, 10, 8)
        }
    }
}

extension UpstreamMigrationBaseline {
    /// Which of upstream's per-account migrations an account still needs. Kept per account because an
    /// account migrates only once it's restored, which a launch can end before.
    nonisolated struct Account: Equatable {
        /// Compare upstream's per-account thresholds with this.
        let appliedRelease: Version
        let needsMigrations: Bool
        /// Persist as the account's `AccountSettings.upstreamMigrationsVersion` once its migrations ran, or when it signs in.
        let markerAfterMigrations: String

        /// - Parameters:
        ///   - marker: the account's `AccountSettings.upstreamMigrationsVersion`, `nil` until it first migrated.
        ///   - fallback: `AppSettings.upstreamAccountMigrationsFallback`.
        ///   - syncedRelease: overridable for tests.
        init(marker: String?, fallback: String?, syncedRelease: Version = UpstreamMigrationBaseline.syncedRelease) {
            appliedRelease = marker.flatMap(Version.init) ?? fallback.flatMap(Version.init) ?? syncedRelease
            needsMigrations = appliedRelease < syncedRelease
            markerAfterMigrations = syncedRelease.description
        }

        /// Whether upstream's `if oldVersion < threshold` migration runs for this account.
        func runs(_ threshold: Version) -> Bool {
            appliedRelease < threshold
        }
    }
}
