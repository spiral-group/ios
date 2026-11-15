//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The NSE's fresh token for a feed push
// after the platform's `401`: a newer token already in the keychain needs no
// client; otherwise the session restored as the Matrix pushes do, one
// authenticated request so the SDK refreshes, then the session's token — one
// refresh at a time in the process under the feed's own lock holder, and no
// token when the SDK has none newer or the session cannot be restored.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Synchronization
import Testing

struct FeedPushTokenRefresherTests {
    @Test
    func theSDKsRefreshedTokenIsTheAnswer() async {
        let keychain = KeychainSessions(accessToken: "mat_stale")
        let client = refreshingClient(keychain)
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReturnValue = client

        let token = await refresher(factory, keychain: keychain).refreshedAccessToken(replacing: "mat_stale")

        #expect(token == "mat_fresh")
        #expect(client.ignoredUsersCallsCount == 1, "one GET makes the SDK refresh")
        #expect(client.fetchMediaPreviewConfigCallsCount == 0, "two GETs when the stable event is absent")
        let arguments = factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReceivedArguments
        #expect(arguments?.credentials.userID == "@me:spiral.md")
        #expect(arguments?.roomID == "!spiral-feed-push:spiral.md")
    }

    /// M1: the feed's client holds the SDK's lease under its own name, so its refresh
    /// waits for a Matrix push's refresh in the same process instead of sharing the lease.
    @Test
    func theRefreshersClientHoldsItsOwnLock() async {
        let keychain = KeychainSessions(accessToken: "mat_stale")
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReturnValue = refreshingClient(keychain)

        _ = await refresher(factory, keychain: keychain).refreshedAccessToken(replacing: "mat_stale")

        #expect(factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReceivedArguments?.lockHolder == .feedTokenRefresh)
    }

    @Test
    func theFeedsLockHolderIsNotAMatrixPushs() {
        #expect(NSEClientLockHolder.notification.name(bundleIdentifier: "com.veruslogistics.messenger.nse") == "com.veruslogistics.messenger.nse")
        #expect(NSEClientLockHolder.feedTokenRefresh.name(bundleIdentifier: "com.veruslogistics.messenger.nse") == "com.veruslogistics.messenger.nse.feed")
    }

    /// H1 (a): the app, or another push, refreshed meanwhile — its token is the answer, and no client is built.
    @Test
    func aNewerKeychainTokenBuildsNoClient() async {
        let keychain = KeychainSessions(accessToken: "mat_from_the_app")
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReturnValue = refreshingClient(keychain)

        let token = await refresher(factory, keychain: keychain).refreshedAccessToken(replacing: "mat_stale")

        #expect(token == "mat_from_the_app")
        #expect(factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderCallsCount == 0)
    }

    /// H1 (b): two stale-token pushes in one process exchange the refresh token once, not twice.
    @Test
    func concurrentPushesShareOneRefresh() async {
        let keychain = KeychainSessions(accessToken: "mat_stale")
        let client = refreshingClient(keychain)
        let flight = FeedPushRefreshFlight()
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderClosure = { _, _, _, _, _, _ in
            // Hold the build until the second push waits on this refresh (bounded, so a missing flight fails rather than hangs).
            let giveUp = ContinuousClock.now.advanced(by: .seconds(2))
            while await flight.waitedCount == 0, ContinuousClock.now < giveUp {
                try await Task.sleep(for: .milliseconds(5))
            }
            return client
        }
        let refresher = refresher(factory, keychain: keychain, flight: flight)

        async let first = refresher.refreshedAccessToken(replacing: "mat_stale")
        async let second = refresher.refreshedAccessToken(replacing: "mat_stale")
        let tokens = await [first, second]

        #expect(tokens == ["mat_fresh", "mat_fresh"])
        #expect(factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderCallsCount == 1)
        #expect(client.ignoredUsersCallsCount == 1)
    }

    /// The token still works for Matrix, so the platform's `401` is not about it: no second read.
    @Test
    func theSameTokenIsNoAnswer() async {
        let keychain = KeychainSessions(accessToken: "mat_stale")
        let client = ClientSDKMock(.init(session: Self.session(accessToken: "mat_stale")))
        client.ignoredUsersReturnValue = []
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReturnValue = client

        #expect(await refresher(factory, keychain: keychain).refreshedAccessToken(replacing: "mat_stale") == nil)
    }

    /// A failed request may still have refreshed (the app did, and the SDK reloaded it).
    @Test
    func aFailedCheckStillReadsTheSession() async {
        let keychain = KeychainSessions(accessToken: "mat_stale")
        let client = ClientSDKMock(.init(session: Self.session(accessToken: "mat_from_the_app")))
        client.ignoredUsersThrowableError = ClientError.Generic(msg: "offline", details: nil)
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderReturnValue = client

        #expect(await refresher(factory, keychain: keychain).refreshedAccessToken(replacing: "mat_stale") == "mat_from_the_app")
    }

    @Test
    func aSessionThatCannotBeRestoredIsNoAnswer() async {
        let factory = ClientFactoryMock()
        factory.makeNSEClientCredentialsRoomIDClientSessionDelegateUserSettingsAppHooksLockHolderThrowableError = ClientError.Generic(msg: "store", details: nil)

        #expect(await refresher(factory, keychain: KeychainSessions(accessToken: "mat_stale")).refreshedAccessToken(replacing: "mat_stale") == nil)
    }

    @Test
    func theUnknownRoomIsOnTheUsersServer() {
        #expect(FeedPushTokenRefresher.unknownRoomID(forUserID: "@me:spiral.md") == "!spiral-feed-push:spiral.md")
        #expect(FeedPushTokenRefresher.unknownRoomID(forUserID: "@me:localhost:8008") == "!spiral-feed-push:localhost:8008")
        #expect(FeedPushTokenRefresher.unknownRoomID(forUserID: "@me") == nil)
        #expect(FeedPushTokenRefresher.unknownRoomID(forUserID: "@me:") == nil)
    }

    // MARK: - Helpers

    private func refresher(_ factory: ClientFactoryMock,
                           keychain: KeychainSessions,
                           flight: FeedPushRefreshFlight = FeedPushRefreshFlight()) -> FeedPushTokenRefresher {
        let credentials = KeychainCredentials(userID: "@me:spiral.md",
                                              restorationToken: RestorationToken(session: Self.session(accessToken: "mat_stale"),
                                                                                 sessionDirectories: .init(),
                                                                                 passphrase: RestorationTokenFixtures.passphrase,
                                                                                 pusherNotificationClientIdentifier: "pusher"))
        return FeedPushTokenRefresher(credentials: credentials,
                                      clientSessionDelegate: keychain,
                                      userSettings: AppSettings.volatile().userSettings(for: "@me:spiral.md"),
                                      appHooks: AppHooks(),
                                      clientFactory: factory,
                                      flight: flight)
    }

    /// What the SDK does on `M_UNKNOWN_TOKEN`: refresh, save through the session delegate, retry.
    private func refreshingClient(_ keychain: KeychainSessions) -> ClientSDKMock {
        let client = ClientSDKMock(.init(session: Self.session(accessToken: "mat_stale")))
        client.ignoredUsersClosure = {
            let fresh = Self.session(accessToken: "mat_fresh")
            keychain.saveSessionInKeychain(session: fresh)
            client.sessionReturnValue = fresh
            return []
        }
        return client
    }

    fileprivate nonisolated static func session(accessToken: String) -> Session {
        Session(accessToken: accessToken,
                refreshToken: "refresh",
                userId: "@me:spiral.md",
                deviceId: "DEVICE",
                homeserverUrl: "https://matrix.spiral.md",
                oauthData: nil,
                slidingSyncVersion: .native)
    }
}

/// The keychain as the SDK's session delegate sees it.
private final nonisolated class KeychainSessions: ClientSessionDelegate {
    private let session: Mutex<Session>

    init(accessToken: String) {
        session = Mutex(FeedPushTokenRefresherTests.session(accessToken: accessToken))
    }

    func retrieveSessionFromKeychain(userId: String) throws -> Session {
        session.withLock { $0 }
    }

    func saveSessionInKeychain(session: Session) {
        self.session.withLock { $0 = session }
    }
}
