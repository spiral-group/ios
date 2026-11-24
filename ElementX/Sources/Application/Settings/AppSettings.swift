//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

#if IS_MAIN_APP
#endif

import Combine
import Foundation
import Macros
import SwiftUI

nonisolated enum AppBuildType {
    case debug
    case nightly
    case release
    
    static var current: AppBuildType {
        #if DEBUG
        return .debug
        #else
        if InfoPlistReader.main.isNightlyBuild {
            .nightly
        } else {
            .release
        }
        #endif
    }
}

/// Store Element specific app settings.
///
/// State is persisted in `UserDefaults`, which is thread-safe per Apple's documentation, hence `@unchecked`.
final nonisolated class AppSettings: @unchecked Sendable {
    static let suiteName: String = InfoPlistReader.main.appGroupIdentifier
    
    /// UserDefaults to be used on reads and writes.
    private let store: UserDefaultsProtocol
    
    static var appBuildType: AppBuildType {
        // AGENT-PLATFORM: upstream's AppBuildType.current keys off the
        // isNightlyBuild Info.plist flag, which our rebranded Nightly
        // variant now sets (Variants/Nightly/nightly.yml).
        AppBuildType.current
    }
    
    func resetAllSettings() {
        MXLog.warning("Resetting the AppSettings.")
        store.reset()
    }
    
    // MARK: - Hooks
    
    // swiftlint:disable:next function_parameter_count
    func override(accountProviders: [AccountProvider],
                  allowOtherAccountProviders: Bool,
                  hideBrandChrome: Bool,
                  pushGatewayBaseURL: URL,
                  oAuthRedirectURL: URL,
                  oAuthClientURIPath: String?,
                  websiteURL: URL,
                  logoURL: URL,
                  copyrightURL: URL,
                  acceptableUseURL: URL,
                  privacyURL: URL,
                  encryptionURL: URL,
                  deviceVerificationURL: URL,
                  chatBackupDetailsURL: URL,
                  identityPinningViolationDetailsURL: URL,
                  historySharingDetailsURL: URL, // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningHost
                  bugReportApplicationID: String,
                  analyticsTermsURL: URL?,
                  mapTilerConfiguration: MapTilerConfiguration) {
        self.accountProviders = accountProviders
        self.allowOtherAccountProviders = allowOtherAccountProviders
        self.hideBrandChrome = hideBrandChrome
        self.pushGatewayBaseURL = pushGatewayBaseURL
        self.oAuthRedirectURL = oAuthRedirectURL
        self.oAuthClientURIPath = oAuthClientURIPath
        self.websiteURL = websiteURL
        self.logoURL = logoURL
        self.copyrightURL = copyrightURL
        self.acceptableUseURL = acceptableUseURL
        self.privacyURL = privacyURL
        self.encryptionURL = encryptionURL
        self.deviceVerificationURL = deviceVerificationURL
        self.chatBackupDetailsURL = chatBackupDetailsURL
        self.identityPinningViolationDetailsURL = identityPinningViolationDetailsURL
        self.historySharingDetailsURL = historySharingDetailsURL
        self.bugReportApplicationID = bugReportApplicationID
        self.analyticsTermsURL = analyticsTermsURL
        self.mapTilerConfiguration = RemotePreference(mapTilerConfiguration)
    }
    
    // MARK: - Application
    
    /// The last known version of the app that was launched on this device, which is
    /// used to detect when migrations should be run. When `nil` the app may have been
    /// deleted between runs so should clear data in the shared container and keychain.
    @UserPreference
    var lastVersionLaunched: String?
    
    /// AGENT-PLATFORM (1.0.3): the Element X release whose launch migrations have run, see `UpstreamMigrationBaseline`.
    @UserPreference(key: "spiralUpstreamMigrationsVersion")
    var upstreamMigrationsVersion: String?
    
    /// AGENT-PLATFORM (1.0.3): where an account without its own marker starts its migrations, see `UpstreamMigrationBaseline`.
    @UserPreference(key: "spiralUpstreamAccountMigrationsFallback")
    var upstreamAccountMigrationsFallback: String?
    
    /// Defaults to `true` for new users, and we use a migration to set it to `false` for existing users.
    @UserPreference(defaultValue: true)
    var hasSeenNewSoundBanner: Bool
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008): the invitation a person
    // arrived with, kept across the OAuth round-trip so the authorization
    // URL can carry it and the first session can offer "Message <inviter>".
    // Cleared once that offer has been made (or the person signed in to an
    // existing account).
    @UserPreference
    var pendingInvite: PendingInvite?
    
    /// Defaults to `true` so new users never see it. Developer options arms it for now, an upgrade migration will at launch.
    @UserPreference(defaultValue: true)
    var hasSeenMultiAccountAnnouncement: Bool
    
    /// AGENT-PLATFORM (question 412): the posts catalogue's introduction shows once, on first opening.
    @UserPreference(key: "spiralHasSeenInteractivePostIntroduction", defaultValue: false)
    var hasSeenInteractivePostIntroduction: Bool
    
    /// The initial set of account providers shown to the user in the authentication flow.
    ///
    /// Account provider is the friendly term for the server name. It should not contain an `https` prefix and should
    /// match the last part of the user ID. For example `example.com` and not `https://matrix.example.com`.
    // AGENT-PLATFORM: closed v1.0 single-tenant SaaS — only our own homeserver
    // is offered, with manual entry of other providers disabled.
    private(set) var accountProviders: [AccountProvider] = [SpiralEnvironment.current.accountProvider] // AGENT-PLATFORM (Brief 0084)
    /// Whether or not the user is allowed to manually enter their own account provider or must select from one of `defaultAccountProviders`.
    private(set) var allowOtherAccountProviders = false
    /// Whether the components surrounding the app brand/logo should be hidden or not
    private(set) var hideBrandChrome = false
    
    // AGENT-PLATFORM: derive from Info.plist baseBundleIdentifier so the
    // value follows our $(BASE_BUNDLE_IDENTIFIER).background.refresh wiring
    // and stays consistent across Debug/Release/Nightly variants.
    /// The task identifier used for background app refresh. Also used in main target's the Info.plist
    let backgroundAppRefreshTaskIdentifier = "\(InfoPlistReader.main.baseBundleIdentifier).background.refresh"
    /// The task identifier used for the search index backfill. Also used in main target's the Info.plist
    // AGENT-PLATFORM: bundle-ID based, like the refresh task above.
    let searchBackfillTaskIdentifier = "\(InfoPlistReader.main.baseBundleIdentifier).background.search-backfill"

    // AGENT-PLATFORM: brand URLs hosted on our homeserver host so MAS dynamic
    // client registration accepts them. MSC2966 enforces that client_uri /
    // logo_uri / tos_uri / policy_uri / redirect_uri all share a host (or
    // subdomain) — split-host metadata is rejected as invalid_client_metadata.
    // Pages under /brand/ are served by Caddy file_server (backend R2.3.5).
    /// A URL where users can go read more about the app.
    private(set) var websiteURL: URL = SpiralEnvironment.current.websiteURL // AGENT-PLATFORM (Brief 0084)
    /// AGENT-PLATFORM (§ 5.56): the curated Interactive Post templates, static
    /// on the same host as /brand/.
    ///
    /// A debug build takes another from the launch arguments —
    /// `-SpiralCatalogURL file:///…/Documents/catalog/` — so a template is
    /// tried on a simulator before it is live for everyone (§ 5.60).
    private(set) var interactiveCatalogURL: URL = {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "SpiralCatalogURL"), let url = URL(string: override) {
            return url
        }
        #endif
        return SpiralEnvironment.current.catalogURL // AGENT-PLATFORM (Brief 0084)
    }()

    /// AGENT-PLATFORM (1.0.2): the app's App Store page, where "Update" leads. The id is the store listing's, as the
    /// backend's `app_store_id` and the web pages' install buttons have it.
    static let appStoreURL: URL = "https://apps.apple.com/app/id6760817174"
    /// A URL that contains the app's logo that may be used when showing content in a web view.
    private(set) var logoURL: URL = SpiralEnvironment.current.logoURL // AGENT-PLATFORM (Brief 0084)
    /// A URL that contains that app's copyright notice.
    private(set) var copyrightURL: URL = "https://spiral.md/brand/copyright"
    /// A URL that contains the app's Terms of use.
    private(set) var acceptableUseURL: URL = SpiralEnvironment.current.acceptableUseURL // AGENT-PLATFORM (Brief 0084)
    /// A URL that contains the app's Privacy Policy.
    private(set) var privacyURL: URL = SpiralEnvironment.current.privacyURL // AGENT-PLATFORM (Brief 0084)
    /// AGENT-PLATFORM (AGPL publication): the app's source. Not live until the
    /// publication pushes the repository.
    private(set) var sourceCodeURL: URL = "https://github.com/spiral-group/ios"
    /// AGENT-PLATFORM (AGPL publication, decision 107): the server's source, the
    /// Synapse fork the app talks to (AGPL-3.0 §13). SOURCES.md's server section,
    /// not a branch: a build keeps the link after the server is upgraded, and
    /// that section names whatever the server runs. Not live until the publication.
    private(set) var serverSourceCodeURL: URL = "https://github.com/spiral-group/ios/blob/spiral/main/SOURCES.md#the-server"
    /// AGENT-PLATFORM (AGPL publication): SOURCES.md, every component's source for a release.
    private(set) var sourcesListURL: URL = "https://github.com/spiral-group/ios/blob/spiral/main/SOURCES.md"
    /// AGENT-PLATFORM (AGPL publication): where to ask for the source of a build (NOTICE).
    private(set) var sourceRequestAddress = "support@spiral.md"
    /// A URL where users can go read more about encryption in general.
    private(set) var encryptionURL: URL = "https://spiral.md/brand/help#encryption"
    /// A URL where users can go read more about device verification..
    private(set) var deviceVerificationURL: URL = "https://spiral.md/brand/help#device-verification"
    /// A URL where users can go read more about the chat backup.
    private(set) var chatBackupDetailsURL: URL = "https://spiral.md/brand/help#key-backup"
    /// A URL where users can go read more about identity pinning violations
    private(set) var identityPinningViolationDetailsURL: URL = "https://spiral.md/brand/help#identity-pinning"
    /// A URL describing how history sharing works
    private(set) var historySharingDetailsURL: URL = "https://spiral.md/brand/help#history-sharing"

    // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningHost (mobile.element.io) and no
    // elementProAppStoreURL; Element's provisioning links and Element Pro's alert are gone.
    
    @UserPreference(defaultValue: AppAppearance.system)
    var appAppearance: AppAppearance
    
    /// Tracks previous servers the user connected to for autocompletion purposes. Entries are made lowercase on write.
    @UserPreference(key: "previousServers", defaultValue: [])
    var previousServers: [String]
    
    var defaultAccountProvider: AccountProvider {
        if allowOtherAccountProviders {
            previousServers.first.map { .generic($0) } ?? accountProviders[0]
        } else {
            accountProviders[0]
        }
    }
    
    // MARK: - Security
    
    /// The app must be locked with a PIN code as part of the authentication flow.
    let appLockIsMandatory = false
    /// The amount of time the app can remain in the background for without requesting the PIN/TouchID/FaceID.
    let appLockGracePeriod: TimeInterval = 0
    /// Any codes that the user isn't allowed to use for their PIN.
    let appLockPINCodeBlockList = ["0000", "1234"]
    /// The number of attempts the user has made to unlock the app with a PIN code (resets when unlocked).
    @UserPreference(defaultValue: 0)
    var appLockNumberOfPINAttempts: Int
    
    // MARK: - Authentication
    
    /// Any pre-defined static client registrations for OAuth issuers.
    // AGENT-PLATFORM: dropped ThirdRoom static registration — Element-specific,
    // does not apply to our deployment.
    let oAuthStaticRegistrations: [URL: String] = [:]
    /// The redirect URL used for OAuth.
    // AGENT-PLATFORM: redirect host must equal client_uri host per MAS dynamic
    // client registration policy (MSC2966). Path /oidc/login is served by
    // Caddy file_server alongside /brand/* (backend R2.3.5); the matching
    // apple-app-site-association entry is added when AASA lands.
    private(set) nonisolated(unsafe) var oAuthRedirectURL: URL! = SpiralEnvironment.current.oAuthRedirectURL // AGENT-PLATFORM (Brief 0084)
    /// A path that is appended to `websiteURL` to form the OAuth `clientURI`. MAS uses `clientURI` as the identifier for a specific app, allowing us to
    /// distinguish the various clients we have for Android, iOS and Web from each other.
    // AGENT-PLATFORM: nil — our clientURI stays the bare websiteURL (spiral.md),
    // matching the MAS client registration that is already live.
    private(set) var oAuthClientURIPath: String?
    
    var oAuthConfiguration: OAuthConfiguration {
        OAuthConfiguration(clientName: InfoPlistReader.main.bundleDisplayName,
                           redirectURI: oAuthRedirectURL,
                           clientURI: oAuthClientURIPath.map { websiteURL.appending(path: $0) } ?? websiteURL,
                           logoURI: logoURL,
                           tosURI: acceptableUseURL,
                           policyURI: privacyURL,
                           staticRegistrations: oAuthStaticRegistrations.mapKeys { $0.absoluteString })
    }
    
    /// Whether or not the Create Account button is shown on the start screen.
    ///
    /// **Note:** Setting this to false doesn't prevent someone from creating an account when the selected homeserver's MAS allows registration.
    let showCreateAccountButton = true
    
    // AGENT-PLATFORM (Brief 0073): the start screen's «Sign in with QR code».
    // Off until the homeserver enables MSC4108 — today `/rendezvous` is a 404
    // and the scan ends in an error.
    @UserPreference(defaultValue: false)
    var qrCodeLoginEnabled: Bool
    
    // MARK: - Notifications
    
    var pusherAppID: String {
        #if DEBUG
        InfoPlistReader.main.baseBundleIdentifier + ".ios.dev"
        #else
        InfoPlistReader.main.baseBundleIdentifier + ".ios.prod"
        #endif
    }
    
    // AGENT-PLATFORM: Caddy proxies /_matrix/push/v1/* to our self-hosted
    // Sygnal instance; the actual Sygnal service lands in backend R2.3.
    private(set) var pushGatewayBaseURL: URL = SpiralEnvironment.current.baseURL // AGENT-PLATFORM (Brief 0084)
    var pushGatewayNotifyEndpoint: URL {
        pushGatewayBaseURL.appending(path: "_matrix/push/v1/notify")
    }

    // AGENT-PLATFORM: base URL for the Agent Platform REST API
    // (`/api/v1/*`). Mounted on the same Caddy as Synapse + MAS;
    // generated paths from swift-openapi-generator are absolute under
    // /api/v1/... so the URL is protocol + host only. Lands wired
    // through AgentPlatformClient via MatrixSDKAuthBridge — see
    // `Services/AgentPlatform/`.
    private(set) var agentPlatformBaseURL: URL = SpiralEnvironment.current.platformURL // AGENT-PLATFORM (Brief 0084)
    
    /// AGENT-PLATFORM: feed (Brief 0082): the platform API for a session, where the
    /// launch environment is not known (the NSE): a Debug build's dev-stack
    /// account (`@…:localhost`) talks to the dev stack, everyone else to `agentPlatformBaseURL`.
    func agentPlatformBaseURL(forUserID userID: String) -> URL {
        #if DEBUG
        if userID.hasSuffix(":localhost") {
            return SpiralEnvironment.localDev.platformURL // AGENT-PLATFORM (Brief 0084)
        }
        #endif
        return agentPlatformBaseURL
    }
    
    @UserPreference(defaultValue: false)
    var hideQuietNotificationAlerts: Bool
    
    /// Tag describing which set of device specific rules a pusher executes.
    @UserPreference
    var pusherProfileTag: String?
    
    /// The device's last boot time as recorded by the NSE.
    @UserPreference
    var lastNotificationBootTime: TimeInterval?
    
    /// The app icon badge value the app last computed from the SDK's unread notification counts.
    @UserPreference(defaultValue: 0)
    var lastKnownBadgeCount: Int
    
    // MARK: - Logging
    
    @UserPreference(defaultValue: LogLevel.info)
    var logLevel: LogLevel
    
    @UserPreference(defaultValue: Set<TraceLogPack>())
    var traceLogPacks: Set<TraceLogPack>
    
    // MARK: - Bug report
    
    let bugReportRageshakeURL: RemotePreference<RageshakeConfiguration> = .init(Secrets.rageshakeURL.map { .url(URL(string: $0)!) } ?? .disabled) // swiftlint:disable:this force_unwrapping
    // AGENT-PLATFORM (Brief 0078): no Sentry DSNs — Spiral links no crash reporter.
    /// The name allocated by the bug report server
    private(set) var bugReportApplicationID = "element-x-ios"
    
    // MARK: - Content scanner
    
    /// The base URL of the content scanner server used to scan media before it is downloaded.
    /// `nil` when content scanning is disabled.
    let contentScannerURL: RemotePreference<URL?> = .init(nil)
    
    // MARK: - Encryption
    
    /// Whether the server forbids the use of E2EE: new rooms are created unencrypted and
    /// enabling encryption on existing rooms is not offered.
    let forceDisableE2EE: RemotePreference<Bool> = .init(false)
    
    // MARK: - Analytics
    
    // AGENT-PLATFORM (Brief 0078): always `nil` — Spiral links no analytics SDK, so there is
    // nothing to consent to: no onboarding prompt, no Analytics row in Settings.
    /// The configuration to use for analytics. Set to `nil` to disable analytics.
    let analyticsConfiguration: AnalyticsConfiguration? = nil
    /// The URL to open with more information about analytics terms. When this is `nil` the "Learn more" link will be hidden.
    private(set) var analyticsTermsURL: URL? = "https://spiral.md/brand/privacy" // AGENT-PLATFORM (Brief 0083 L1b): Spiral's privacy policy, not Element's cookie policy.
    /// Whether or not there the app is able ask for user consent to enable analytics or sentry reporting.
    var canPromptForAnalytics: Bool {
        analyticsConfiguration != nil // AGENT-PLATFORM (Brief 0078): Sentry consent went with Sentry.
    }
    
    /// Whether the user has opted in to send analytics.
    @UserPreference(defaultValue: AnalyticsConsentState.unknown)
    var analyticsConsentState: AnalyticsConsentState
    
    // AGENT-PLATFORM (Brief 0083 L1b): no hasSignedInBefore, it only stopped Element Classic's import prompt.
    
    @UserPreference(defaultValue: false)
    var hasRunNotificationPermissionsOnboarding: Bool
    
    @UserPreference(defaultValue: false)
    var hasRequestedLocationAlwaysLocationAuthorization: Bool
    
    @UserPreference(defaultValue: [FrequentlyUsedEmoji]())
    var frequentlyUsedSystemEmojis: [FrequentlyUsedEmoji]
    
    // MARK: - Live Location
    
    @UserPreference(defaultValue: 10)
    var liveLocationMinimumDistanceUpdate: Int
    
    @UserPreference(defaultValue: false)
    var liveLocationDisclaimerDisplayed: Bool
    
    // MARK: - Room Screen
    
    @UserPreference(defaultValue: AppBuildType.current == .debug)
    var viewSourceEnabled: Bool
    
    @UserPreference(defaultValue: true)
    var optimizeMediaUploads: Bool
    
    @UserPreference(defaultValue: AudioPlaybackSpeed.default)
    var voiceMessagePlaybackSpeed: AudioPlaybackSpeed
    
    // AGENT-PLATFORM (Brief 0067): the Element Call section (base URL, analytics
    // endpoints, URL override) is gone with the widget (ADR-0079).
    
    // MARK: - Users
    
    /// Whether to hide the display name and avatar of ignored users as these may contain objectionable content.
    let hideIgnoredUserProfiles = true
    
    // MARK: - Maps
    
    /// The locally-bundled MapTiler configuration.
    // AGENT-PLATFORM: upstream UUIDs (9bc819c8…, dea61faf…) are private styles
    // in Element Ltd's MapTiler account and return HTTP 404 for any other API
    // key. Use the public streets-v2 / streets-v2-dark presets that every
    // MapTiler account can serve so location sharing renders maps under our
    // own MapTiler key. Replace with custom Spiral-branded styles later.
    static let bundledMapTilerConfiguration = MapTilerConfiguration(baseURL: "https://api.maptiler.com/maps",
                                                                    apiKey: Secrets.mapLibreAPIKey,
                                                                    lightStyleID: "streets-v2",
                                                                    darkStyleID: "streets-v2-dark")
    
    /// The MapTiler configuration used to build map URLs, which defaults to the bundled one.
    private(set) var mapTilerConfiguration = RemotePreference(AppSettings.bundledMapTilerConfiguration)
    
    // MARK: - Feature Flags
    
    /// Others
    @UserPreference(defaultValue: false)
    var fuzzyRoomListSearchEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var lowPriorityFilterEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var mentionsFilterEnabled: Bool
    
    /// Configuration to enable only signed device isolation mode for  crypto. In this mode only devices signed by their owner will be considered in e2ee rooms.
    @UserPreference(defaultValue: false)
    var enableOnlySignedDeviceIsolationMode: Bool
    
    @UserPreference(defaultValue: false)
    var knockingEnabled: Bool
    
    // AGENT-PLATFORM (Brief 0066 step 6): on by default. An Interactive
    // Post is generated in a THREAD of the owner's DM with the agent
    // (notebook § 5.35), so threads are part of the product rather than a
    // lab. Upstream ships both off.
    // AGENT-PLATFORM (decision 188): own storage keys, so an "off" stored by
    // an earlier build's Labs or Developer options toggle is no longer read.
    @UserPreference(key: "spiralThreadsEnabled", defaultValue: true)
    var threadsEnabled: Bool
    
    @UserPreference(key: "globalSearchEnabledV2", defaultValue: true)
    var globalSearchEnabled: Bool
    
    // AGENT-PLATFORM (decision 301): Spiral doesn't use Matrix spaces yet. Off drops the Spaces tab,
    // the Chats space filter and Create room's space picker, and the Chats list shows joined spaces
    // as rows, so a space opens in Chats like a room. On is upstream's behaviour. Read when a session starts.
    @UserPreference(key: "spiralSpacesEnabled", defaultValue: false)
    var spacesEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var focusEventOnNotificationTap: Bool
    
    @UserPreference(defaultValue: false)
    var linkPreviewsEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var jumpToReadMarkerEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var linkNewDeviceEnabled: Bool
    
    @UserPreference(key: "clientPausingAndResumingEnabledV2", defaultValue: false, volatile: true)
    var clientPausingAndResumingEnabled: Bool
    
    @UserPreference(defaultValue: AppBuildType.current != .release)
    var developerOptionsEnabled: Bool
    
    /// Runs calls through the native matrix-rust-rtc stack instead of the Element Call web view.
    @UserPreference(defaultValue: false)
    var nativeCallEnabled: Bool
    
    @UserPreference(defaultValue: false)
    var multiAccountEnabled: Bool
    
    /// Lets the add account flow start once `multiAccountEnabled` shows its entry points. Not a user preference, so testers
    /// can't add a second account while signing out of one isn't safe yet. Only set it to `true` locally, for development.
    let addAccountFlowEnabled = false
    
    init(store: UserDefaultsProtocol) {
        self.store = store
    }
    
    func userSettings(for userID: String) -> UserSettings {
        UserSettings(appSettings: self, accountSettings: .init(userID: userID, store: store))
    }
    
    static func volatile() -> AppSettings {
        AppSettings(store: VolatileUserDefaults())
    }
}
