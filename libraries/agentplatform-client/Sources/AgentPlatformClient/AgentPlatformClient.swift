//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AgentPlatformClient — public entry point for the iOS host app.
//
// Layers (top to bottom):
//
//   1. `AgentPlatformClient` (this file) — opaque facade that
//      hides the generated `Client` struct + middleware wiring.
//   2. `AuthMiddleware` (this file) — injects
//      `Authorization: Bearer <token>` on every request via the
//      caller-supplied `AuthTokenProviding`.
//   3. Generated `Client` (built by swift-openapi-generator from
//      `openapi.yaml`) — typed REST methods.
//   4. `URLSessionTransport` (swift-openapi-urlsession) — actual
//      network I/O.
//
// Until the generator plugin lands on first `swift build`, the
// `Client` symbol used below is a stub typealias to keep the
// crate compiling; first build flips it to the real generated
// type without any source change here.

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Public facade over the swift-openapi-generator-produced
/// REST client.
///
/// Construct once per user session (the auth provider already
/// holds the live MAS token); pass through to view models /
/// services that need typed `/api/v1/*` calls.
public struct AgentPlatformClient: Sendable {
    /// Generated client. Until swift-openapi-generator runs its
    /// build plugin, `Client` is a stub symbol; the operator's
    /// first `swift build` flips it to the real generated type.
    public let underlying: Client
    /// The session every request goes through.
    public let urlSession: URLSession

    private let serverURL: URL
    private let transport: URLSessionTransport
    private let authMiddleware: AuthMiddleware

    /// A GDPR export of every call a long-lived account ever had stays well
    /// below this; a larger body is refused rather than held in memory.
    static let maximumDocumentSize = 256 * 1024 * 1024

    /// Build a client against a backend base URL with a
    /// caller-supplied auth token source.
    ///
    /// - Parameters:
    ///   - serverURL: Backend root, e.g.
    ///                `URL(string: "https://agent-x.pp.ua")!`.
    ///                Generated paths are relative (`/api/v1/...`)
    ///                so the URL is the protocol + host only.
    ///   - authProvider: Resolves the bearer token per request.
    ///                   See `AuthTokenProviding` for guidance.
    ///   - urlSession: Inject a custom `URLSession` for testing
    ///                 (mocked `URLProtocol` subclass). Defaults to
    ///                 `makeUncachedURLSession()`.
    public init(serverURL: URL,
                authProvider: any AuthTokenProviding,
                urlSession: URLSession = makeUncachedURLSession()) throws {
        let transport = URLSessionTransport(configuration: .init(session: urlSession))
        let authMiddleware = AuthMiddleware(provider: authProvider)
        // Override the runtime's default ISO 8601 transcoder.
        // The backend emits `chrono::DateTime<Utc>` timestamps
        // with microsecond precision (`...866997Z`); Foundation's
        // strict ISO 8601 parser used by `ISO8601DateTranscoder`
        // rejects any fractional seconds. `FlexibleISO8601DateTranscoder`
        // accepts plain, millisecond, microsecond, and nanosecond
        // precision on decode. See its docs for the contract.
        let configuration = Configuration(dateTranscoder: FlexibleISO8601DateTranscoder())
        underlying = Client(serverURL: serverURL,
                            configuration: configuration,
                            transport: transport,
                            middlewares: [authMiddleware])
        self.serverURL = serverURL
        self.urlSession = urlSession
        self.transport = transport
        self.authMiddleware = authMiddleware
    }
    
    /// A session that keeps no copy of any response. Every `/api/v1/*` body
    /// carries personal data (a GDPR export is the whole account), and with
    /// `URLSession.shared` it would also land in the app's disk `URLCache`
    /// (`Library/Caches/…/Cache.db`) whenever the server sent no
    /// `Cache-Control`. The shared session's timeouts are kept.
    public static func makeUncachedURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = URLSession.shared.configuration.timeoutIntervalForRequest
        configuration.timeoutIntervalForResource = URLSession.shared.configuration.timeoutIntervalForResource
        return URLSession(configuration: configuration)
    }

    /// GETs a JSON document and returns its bytes exactly as the server sent
    /// them, with the same bearer token and transport as every typed call.
    ///
    /// For the GDPR exports (Brief 0078): the person receives the server's own
    /// file, and `GET /voice-sessions/{id}/export` documents its 200 without a
    /// body, so the generated operation drops it.
    ///
    /// - Parameter path: Absolute path under the server URL, e.g. `/api/v1/me/export`.
    public func jsonDocument(at path: String) async throws -> (status: Int, body: Data) {
        var request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: path)
        request.headerFields[.accept] = "application/json"
        let operationID = "json_document"

        let (response, body) = try await authMiddleware.intercept(request, body: nil, baseURL: serverURL, operationID: operationID) { request, body, baseURL in
            try await transport.send(request, body: body, baseURL: baseURL, operationID: operationID)
        }

        let data = if let body {
            try await Data(collecting: body, upTo: Self.maximumDocumentSize)
        } else {
            Data()
        }
        return (response.status.code, data)
    }
}

/// Inserts `Authorization: Bearer <token>` on every outgoing
/// request. Skipped silently when the provider returns `nil` —
/// the request goes out unauthenticated, and the server will
/// 401 it, which is the caller's cue to drive the OAuth2 re-
/// login flow.
///
/// Implemented as a `ClientMiddleware` (OpenAPIRuntime 1.x) so
/// the bearer-injection point is shared across every typed
/// operation; we never have to remember to add headers in the
/// generated call sites.
public struct AuthMiddleware: ClientMiddleware {
    private let provider: any AuthTokenProviding

    public init(provider: any AuthTokenProviding) {
        self.provider = provider
    }

    public func intercept(_ request: HTTPRequest,
                          body: HTTPBody?,
                          baseURL: URL,
                          operationID: String,
                          next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)) async throws -> (HTTPResponse, HTTPBody?) {
        var mutableRequest = request
        if let token = await provider.currentAccessToken() {
            mutableRequest.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(mutableRequest, body, baseURL)
    }
}

// `Client`, `Operations.<id>.{Input, Output}`, and every
// `Components.Schemas.<Name>` symbol referenced by the facade
// are emitted at build time by swift-openapi-generator from
// `Sources/AgentPlatformClient/openapi.yaml`. Run `swift build`
// at the package root to seed the build cache; subsequent
// rebuilds (including Xcode indexing) pick up the generated
// types automatically. Verified clean S146 on Swift 6.3 +
// Xcode 26.4.
