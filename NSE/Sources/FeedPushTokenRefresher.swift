//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A MAS access token lives about five
// minutes, so the keychain's is usually stale when a feed push wakes an idle
// phone. After the platform's `401` this first reads the keychain again: the
// app, or another push, may have refreshed meanwhile. Only when the keychain
// still holds the rejected token does it restore the session the way the
// Matrix pushes do (`makeNSEClient`, the keychain as `ClientSessionDelegate`)
// and make one authenticated request: the SDK refreshes an expired token under
// its cross-process lock, writes it back to the keychain and retries. Its own
// lock holder makes that refresh wait for a Matrix push's refresh in the same
// process rather than share its lease (`NSEClientLockHolder`). No room
// is loaded and nothing is synced; the client is gone when the push is
// answered. Logs carry error types only.
//

import MatrixRustSDK

nonisolated struct FeedPushTokenRefresher {
    let credentials: KeychainCredentials
    let clientSessionDelegate: ClientSessionDelegate
    let userSettings: UserSettings
    let appHooks: AppHooks
    var clientFactory: any ClientFactoryProtocol & Sendable = ClientFactory()
    var flight = FeedPushRefreshFlight.shared

    /// The session's current token when it is not `rejected`; `nil` when there is none newer.
    func refreshedAccessToken(replacing rejected: String) async -> String? {
        if let token = keychainToken(replacing: rejected) { return token }
        let refreshed = await flight.run { [self] in
            // A refresh that ended after the read above has saved its token already.
            if let token = keychainToken(replacing: rejected) { return token }
            return await refreshThroughSDK(replacing: rejected)
        }
        // A push that waited on another push's refresh reads what that one saved.
        return keychainToken(replacing: rejected) ?? refreshed.flatMap { $0 == rejected ? nil : $0 }
    }

    private static let logTag = "[NSE][feed]"

    /// The NSE client loads one room; a feed push has none, so it names one
    /// that cannot exist and the client loads nothing.
    static func unknownRoomID(forUserID userID: String) -> String? {
        guard let colon = userID.firstIndex(of: ":") else { return nil }
        let serverName = userID[userID.index(after: colon)...]
        return serverName.isEmpty ? nil : "!spiral-feed-push:\(serverName)"
    }

    private func keychainToken(replacing rejected: String) -> String? {
        guard let token = try? clientSessionDelegate.retrieveSessionFromKeychain(userId: credentials.userID).accessToken,
              token != rejected else {
            return nil
        }
        MXLog.info("Feed push: the keychain holds a newer token")
        return token
    }

    private func refreshThroughSDK(replacing rejected: String) async -> String? {
        guard let roomID = Self.unknownRoomID(forUserID: credentials.userID) else { return nil }
        do {
            ExtensionLogger.logMemory(with: Self.logTag)
            let client = try await clientFactory.makeNSEClient(credentials: credentials,
                                                               roomID: roomID,
                                                               clientSessionDelegate: clientSessionDelegate,
                                                               userSettings: userSettings,
                                                               appHooks: appHooks,
                                                               lockHolder: .feedTokenRefresh)
            ExtensionLogger.logMemory(with: Self.logTag)
            do {
                // Any authenticated request does: this is one GET of the account's
                // ignored-user list, changes nothing, and a 404 is an answer too.
                _ = try await client.ignoredUsers()
            } catch {
                MXLog.info("Feed push: the token check failed: \(type(of: error))")
            }
            let token = try client.session().accessToken
            guard token != rejected else {
                MXLog.info("Feed push: the session has no newer token")
                return nil
            }
            return token
        } catch {
            MXLog.info("Feed push: could not restore the session: \(type(of: error))")
            return nil
        }
    }
}

/// One feed token refresh at a time in the process. iOS runs pushes
/// concurrently in one NSE process, and two refreshes there would each exchange
/// the same refresh token: MAS answers the second by revoking the pair the
/// first got, so the keychain could end up with a revoked pair and the app
/// signed out. The SDK's lock can't stop it — its lease is shared by every
/// client naming the same holder, and every feed refresher names the same one.
/// A push that needs a refresh while one runs waits for it.
actor FeedPushRefreshFlight {
    static let shared = FeedPushRefreshFlight()

    private var current: Task<String?, Never>?
    /// How many pushes waited on a refresh another push started.
    private(set) var waitedCount = 0

    func run(_ refresh: @escaping @Sendable () async -> String?) async -> String? {
        if let current {
            waitedCount += 1
            MXLog.info("Feed push: waiting for the token refresh in flight")
            return await current.value
        }
        let task = Task { await refresh() }
        current = task
        let token = await task.value
        current = nil
        return token
    }
}
