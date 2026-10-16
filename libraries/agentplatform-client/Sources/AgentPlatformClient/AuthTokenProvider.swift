//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Authentication for the Agent Platform REST API (`/api/v1/*`).
//
// The backend accepts MAS-issued bearer tokens — either OAuth2
// access tokens (`mat_…`) or Matrix compatibility tokens (`mct_…`
// from `/_matrix/client/v3/login`). Both pass through MAS's
// RFC 7662 introspection endpoint and produce the same
// `AuthContext` server-side; from the client's perspective they
// are opaque bearer credentials.
//
// Element X iOS retrieves the active session's access token from
// the MatrixRustSDK `Client::session()` API; we wrap that here so
// the generated OpenAPI client doesn't have to depend on the SDK
// directly.

import Foundation

/// Source of bearer tokens for the Agent Platform REST API.
///
/// Conforming types resolve the caller's MAS-issued token on
/// demand. Typically this reads through to `Client::session()`
/// on the Element X user session; tests can stub it with a
/// static token.
///
/// The protocol is `Sendable` so the URLSession-backed transport
/// can hold it across actor boundaries.
public protocol AuthTokenProviding: Sendable {
    /// Resolve the current MAS access token. Returning `nil`
    /// signals "no active session — send the request without an
    /// `Authorization` header" (the server will reject with 401,
    /// which is the caller's cue to drive the OAuth2 re-login
    /// flow).
    ///
    /// Implementations should be fast — this is called on every
    /// REST request. Caching is the implementation's
    /// responsibility; the upstream MAS session token is typically
    /// long-lived (≥ 1 hour) so caching is safe within that
    /// window.
    func currentAccessToken() async -> String?
}

// MARK: - Static token provider (testing)

/// Trivial provider that always returns the same token. Useful
/// for unit tests that exercise the generated client against a
/// mock transport — no MatrixRustSDK dependency required.
public struct StaticAuthTokenProvider: AuthTokenProviding {
    private let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func currentAccessToken() async -> String? {
        token
    }
}

// MARK: - Closure-based provider (host-app integration)

/// Provider that defers to a closure on every call. The host app
/// passes a closure that reaches into its `UserSession` /
/// `ClientProxy` to extract `client.session().accessToken`. We
/// keep the closure async so the host can do whatever bridging
/// it needs (the MatrixRustSDK `session()` method is sync, but
/// future SDK revisions may go async).
///
/// Wiring example in the host app:
///
/// ```swift
/// let provider = ClosureAuthTokenProvider { [weak userSession] in
///     // `userSession?.clientProxy.client.session()` is the
///     // shape today; double-check against the active
///     // matrix-rust-components-swift pin before relying on it.
///     guard let sdkClient = userSession?.clientProxy.client else { return nil }
///     return try? sdkClient.session().accessToken
/// }
/// let agentClient = AgentPlatformClient(
///     serverURL: URL(string: "https://agent-x.pp.ua")!,
///     authProvider: provider
/// )
/// ```
public struct ClosureAuthTokenProvider: AuthTokenProviding {
    private let resolve: @Sendable () async -> String?

    public init(resolve: @escaping @Sendable () async -> String?) {
        self.resolve = resolve
    }

    public func currentAccessToken() async -> String? {
        await resolve()
    }
}
