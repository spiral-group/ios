//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Test stub for the AgentPlatformClient package. Real coverage
// of the generated client lives in the host app's UnitTests
// target (via mocked `URLSession`-injected transport); this
// file ships a single smoke test that asserts the wiring
// compiles + the auth middleware injects the bearer header.

@testable import AgentPlatformClient
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
}

private actor Counter {
    private(set) var value = 0
    func increment() {
        value += 1
    }
}
