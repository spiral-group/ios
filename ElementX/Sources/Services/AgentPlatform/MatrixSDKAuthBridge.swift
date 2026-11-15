//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: source of MAS bearer tokens for the Agent Platform
// REST API (`/api/v1/*`). Reads through to the live MatrixRustSDK
// session stored in the keychain by `UserSessionStore::userSession`.
//
// The token is the same `accessToken` Element X uses for every
// Matrix CS API call — backend `/api/v1/*` accepts it via the same
// MAS RFC 7662 introspection path (per
// `~/Projects/matrix-agent-platform/docs/MOBILE_INTEGRATION.md` §
// Authentication, ADR-0015 + S137 scope-or-client_id trust gate).
//
// Lifecycle:
//
//   * `UserSessionStore::buildUserSessionWithClient` instantiates
//     `MatrixSDKAuthBridge(clientProxy:, keychainController:)`
//     after MatrixRustSDK has the live session ready.
//   * Bridge exposes `AuthTokenProviding` to the
//     `AgentPlatformClient` constructor.
//   * Every REST call asks `currentAccessToken()`:
//       - Read `userID` from the weakly-held `ClientProxyProtocol`.
//       - Look up the `RestorationToken` in the keychain by that
//         userID via `KeychainControllerProtocol::restorationTokens()`
//         (the only currently-public lookup method on the protocol
//         — we filter the returned array client-side).
//       - Return the embedded `session.accessToken`.
//   * MAS token rotation: matrix-rust-sdk's
//     `ClientSessionDelegate::didReceiveAuthError` + the keychain
//     controller's `updateRestorationToken(...)` already update the
//     stored token. The bridge's next lookup transparently sees
//     the fresh value.
//   * A token lives five minutes, and the platform can refuse an
//     expired one before the SDK has refreshed it (the next sync's
//     own 401 can be half a minute away). After a platform 401,
//     `refreshedAccessToken(replacing:)` asks the SDK to refresh
//     now, one refresh at a time (Brief 0082 E2E, FD5).
//   * Logout / session swap: `ClientProxy` is deallocated, the
//     weak reference goes nil, and the bridge returns nil tokens
//     → REST calls go out unauthenticated → 401 → host triggers
//     re-login via Element X's existing flow.
//
// Trade-off: every `currentAccessToken()` call costs one keychain
// read (~0.1-0.5 ms on iPhone). In-bridge caching with a TTL
// aligned to MAS's rotation cadence would shave this — kept as a
// v1.1 follow-up since closed-beta REST volumes (≤ tens of calls
// per minute per user) don't justify the cache-invalidation
// complexity yet.

import AgentPlatformClient
import Foundation
import MatrixRustSDK

/// `AuthTokenProviding` impl backed by the active MatrixRustSDK
/// session, looked up through Element X's `KeychainController`.
///
/// Holds **weak** references to both `clientProxy` and the keychain
/// controller so it doesn't pin the user session in memory across
/// logout / session swap. Once those references go nil the bridge
/// returns nil tokens; AuthMiddleware sends the request without an
/// `Authorization` header; the backend 401s; the host triggers
/// Element X's existing re-login flow.
///
/// The bridge is `Sendable` (required by `AuthTokenProviding`):
/// `@MainActor` makes the class implicitly Sendable, and the
/// isolated async `currentAccessToken()` legally witnesses the
/// protocol's nonisolated async requirement (callers hop onto the
/// main actor for the duration of one keychain lookup). This became
/// necessary with upstream's Swift 6.2 migration — `ClientProxyProtocol`
/// members are main-actor-isolated under strict checking, so the
/// previous nonisolated read of `proxy.userID` no longer compiles.
@MainActor
final class MatrixSDKAuthBridge: AuthTokenProviding {
    private let resolveClientProxy: () -> ClientProxyProtocol?
    private let resolveKeychain: () -> KeychainControllerProtocol?
    /// The refresh in flight: the requests a token refused all wait on one.
    private var refresh: Task<String?, Never>?

    init(clientProxy: ClientProxyProtocol, keychainController: any KeychainControllerProtocol) {
        // Box the weak references inside ref-types so they survive
        // the closure capture. `WeakBox<AnyObject>` keeps the bridge's
        // public init signature clean — both inputs look like
        // ordinary protocol existentials at the call site.
        let proxyBox = WeakBox<AnyObject>(clientProxy as AnyObject)
        let keychainBox = WeakBox<AnyObject>(keychainController as AnyObject)
        resolveClientProxy = { proxyBox.value as? ClientProxyProtocol }
        resolveKeychain = { keychainBox.value as? KeychainControllerProtocol }
    }

    func currentAccessToken() async -> String? {
        keychainToken()
    }
    
    func refreshedAccessToken(replacing rejected: String) async -> String? {
        if let token = keychainToken(), token != rejected {
            return token
        }
        let refresh = refresh ?? startRefresh()
        let token = await refresh.value
        guard let token, token != rejected else {
            MXLog.info("AgentPlatform auth bridge: no newer access token after a 401")
            return nil
        }
        return token
    }
    
    private func startRefresh() -> Task<String?, Never> {
        let task = Task { [weak self] () -> String? in
            guard let self else { return nil }
            defer { refresh = nil }
            guard let proxy = resolveClientProxy() else { return nil }
            await proxy.refreshAccessTokenIfExpired()
            return keychainToken()
        }
        refresh = task
        return task
    }
    
    private func keychainToken() -> String? {
        guard let proxy = resolveClientProxy() else {
            // ClientProxy was deallocated (logout / session swap).
            // Returning nil tells the AuthMiddleware to send the
            // request unauthenticated; the server 401s and the
            // host service drives re-login.
            return nil
        }
        guard let keychain = resolveKeychain() else {
            MXLog.warning("AgentPlatform auth bridge has lost its keychain reference; agent will be unauthorised")
            return nil
        }

        // `restorationTokens()` is the only public read API on
        // `KeychainControllerProtocol` today (the typed
        // `restorationTokenForUsername(_:)` is internal to the
        // concrete `KeychainController` — see
        // ElementX/Sources/Services/Keychain/KeychainController.swift).
        // We filter by userID on the caller side; the array is
        // typically 1 entry (single logged-in account) so this is
        // O(1) in practice.
        let userID = proxy.userID
        let creds = keychain.restorationTokens()
        guard let match = creds.first(where: { $0.userID == userID }) else {
            MXLog.warning("AgentPlatform auth bridge: no keychain entry for userID \(userID)")
            return nil
        }
        return match.restorationToken.session.accessToken
    }
}

/// Tiny weak-reference container so we can store `AnyObject`
/// weakly inside a `@Sendable` closure's capture list. The class
/// itself is `@unchecked Sendable` because the only mutation
/// (`value` being set to nil by ARC when the referent drops) is
/// a thread-safe pointer write on every platform Swift runs on.
private nonisolated final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) {
        self.value = value
    }
}
