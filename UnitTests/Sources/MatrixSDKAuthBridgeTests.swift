//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0082 E2E, FD5): a MAS access token lives five
// minutes, and the platform refused an expired one while the SDK had no
// reason yet to refresh it; every feed read failed until the next sync's
// own 401. After a platform 401 the bridge asks the SDK to refresh now.
//

import MatrixRustSDK
@testable import Spiral
import Testing

struct MatrixSDKAuthBridgeTests {
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
    private let keychain = KeychainControllerMock()
    private let stored = StoredToken("mat_stale")

    init() {
        keychain.restorationTokensClosure = { [stored] in [Self.credentials(accessToken: stored.value)] }
    }

    @Test
    func aRefusedTokenIsRefreshedThroughTheSDK() async {
        clientProxy.refreshAccessTokenIfExpiredClosure = { [stored] in stored.value = "mat_fresh" }
        let bridge = MatrixSDKAuthBridge(clientProxy: clientProxy, keychainController: keychain)

        #expect(await bridge.refreshedAccessToken(replacing: "mat_stale") == "mat_fresh")
        #expect(clientProxy.refreshAccessTokenIfExpiredCallsCount == 1)
        #expect(await bridge.currentAccessToken() == "mat_fresh")
    }

    @Test
    func aNewerTokenInTheKeychainNeedsNoRefresh() async {
        stored.value = "mat_fresh"
        let bridge = MatrixSDKAuthBridge(clientProxy: clientProxy, keychainController: keychain)

        #expect(await bridge.refreshedAccessToken(replacing: "mat_stale") == "mat_fresh")
        #expect(clientProxy.refreshAccessTokenIfExpiredCallsCount == 0)
    }

    @Test
    func noNewerTokenIsNone() async {
        let bridge = MatrixSDKAuthBridge(clientProxy: clientProxy, keychainController: keychain)

        #expect(await bridge.refreshedAccessToken(replacing: "mat_stale") == nil)
        #expect(clientProxy.refreshAccessTokenIfExpiredCallsCount == 1)
    }

    @Test
    func requestsRefusedTogetherShareOneRefresh() async {
        clientProxy.refreshAccessTokenIfExpiredClosure = { [stored] in
            try? await Task.sleep(for: .milliseconds(50))
            stored.value = "mat_fresh"
        }
        let bridge = MatrixSDKAuthBridge(clientProxy: clientProxy, keychainController: keychain)

        async let first = bridge.refreshedAccessToken(replacing: "mat_stale")
        async let second = bridge.refreshedAccessToken(replacing: "mat_stale")
        let tokens = await [first, second]

        #expect(tokens == ["mat_fresh", "mat_fresh"])
        #expect(clientProxy.refreshAccessTokenIfExpiredCallsCount == 1)
    }

    // MARK: - Helpers

    private static func credentials(accessToken: String) -> KeychainCredentials {
        KeychainCredentials(userID: "@me:spiral.md",
                            restorationToken: RestorationToken(session: Session(accessToken: accessToken,
                                                                                refreshToken: "refresh",
                                                                                userId: "@me:spiral.md",
                                                                                deviceId: "DEVICE",
                                                                                homeserverUrl: "https://matrix.spiral.md",
                                                                                oauthData: nil,
                                                                                slidingSyncVersion: .native),
                                                               sessionDirectories: .init(),
                                                               passphrase: RestorationTokenFixtures.passphrase,
                                                               pusherNotificationClientIdentifier: "pusher"))
    }
}

/// The keychain's access token, as the SDK's refresh would leave it.
private final class StoredToken {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}
