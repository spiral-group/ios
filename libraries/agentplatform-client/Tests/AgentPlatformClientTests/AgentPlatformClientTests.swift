//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Test stub for the AgentPlatformClient package. Real coverage
// of the generated client lives in the host app's UnitTests
// target (via mocked `URLSession`-injected transport); this
// file ships a single smoke test that asserts the wiring
// compiles + the auth middleware injects the bearer header.

@testable import AgentPlatformClient
import HTTPTypes
import OpenAPIRuntime
import XCTest

final class AgentPlatformClientTests: XCTestCase {
    func testStaticAuthTokenProviderReturnsConstantToken() async {
        let provider = StaticAuthTokenProvider(token: "mat_abc")
        let token = await provider.currentAccessToken()
        XCTAssertEqual(token, "mat_abc")
    }

    func testStaticAuthTokenProviderReturnsNilForUnauthenticated() async {
        let provider = StaticAuthTokenProvider(token: nil)
        let token = await provider.currentAccessToken()
        XCTAssertNil(token)
    }

    func testClosureAuthTokenProviderEvaluatesClosureOnEachCall() async {
        let counter = Counter()
        let provider = ClosureAuthTokenProvider {
            await counter.increment()
            return "mat_dynamic"
        }
        _ = await provider.currentAccessToken()
        _ = await provider.currentAccessToken()
        _ = await provider.currentAccessToken()
        let count = await counter.value
        XCTAssertEqual(count, 3)
    }

    // MARK: - A 401 to an expired token

    /// Brief 0082 E2E (FD5): a MAS token lives five minutes, and the platform refused an expired one
    /// before the Matrix SDK had refreshed it, so the feed failed until the next sync's own 401.
    func testA401IsAnsweredOnceMoreWithTheRefreshedToken() async throws {
        let server = TokenServer(accepting: "mat_new")
        let refreshes = Counter()
        let middleware = AuthMiddleware(provider: ClosureAuthTokenProvider(resolve: { "mat_old" },
                                                                           refresh: { rejected in
                                                                               await refreshes.increment()
                                                                               return rejected == "mat_old" ? "mat_new" : nil
                                                                           }))

        let (response, _) = try await middleware.intercept(Self.request, body: HTTPBody("{}"), baseURL: Self.baseURL, operationID: "op") { request, _, _ in
            await server.answer(request)
        }

        XCTAssertEqual(response.status, .ok)
        let tokens = await server.tokens
        XCTAssertEqual(tokens, ["Bearer mat_old", "Bearer mat_new"])
        let refreshCount = await refreshes.value
        XCTAssertEqual(refreshCount, 1)
    }

    func testA401StandsWithoutANewerToken() async throws {
        let server = TokenServer(accepting: "mat_new")
        let middleware = AuthMiddleware(provider: ClosureAuthTokenProvider(resolve: { "mat_old" }, refresh: { _ in "mat_old" }))

        let (response, _) = try await middleware.intercept(Self.request, body: nil, baseURL: Self.baseURL, operationID: "op") { request, _, _ in
            await server.answer(request)
        }

        XCTAssertEqual(response.status, .unauthorized)
        let tokens = await server.tokens
        XCTAssertEqual(tokens, ["Bearer mat_old"])
    }

    func testABodySentOnlyOnceIsNotReplayed() async throws {
        let server = TokenServer(accepting: "mat_new")
        let middleware = AuthMiddleware(provider: ClosureAuthTokenProvider(resolve: { "mat_old" }, refresh: { _ in "mat_new" }))
        let body = HTTPBody(AsyncStream { $0.finish() }, length: .unknown, iterationBehavior: .single)

        let (response, _) = try await middleware.intercept(Self.request, body: body, baseURL: Self.baseURL, operationID: "op") { request, _, _ in
            await server.answer(request)
        }

        XCTAssertEqual(response.status, .unauthorized)
        let tokens = await server.tokens
        XCTAssertEqual(tokens, ["Bearer mat_old"])
    }

    private static let baseURL = URL(string: "https://platform.test")!
    private static let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v1/feed/notices")
}

/// Answers `200` to the one token it accepts and `401` to any other, recording each `Authorization`.
private actor TokenServer {
    private let accepted: String
    private(set) var tokens: [String] = []

    init(accepting accepted: String) {
        self.accepted = accepted
    }

    func answer(_ request: HTTPRequest) -> (HTTPResponse, HTTPBody?) {
        let authorization = request.headerFields[.authorization] ?? ""
        tokens.append(authorization)
        return (HTTPResponse(status: authorization == "Bearer \(accepted)" ? .ok : .unauthorized), nil)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}
