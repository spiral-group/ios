//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3, operator 2026-11-20): `GET /me/sign-in-methods` and `POST /me/apple-link` against a stubbed
// transport — a full answer, a missing field (unknown), an extra field (ignored), and an older server without the route.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct SignInMethodsWireTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SignInMethodsURLProtocol.self]
        configuration.httpAdditionalHeaders = [SignInMethodsURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client, identityHost: "id.platform.test")
    }

    @Test
    func aFullAnswerDecodes() async throws {
        stub(status: 200, body: #"{"phrase":false,"apple":true,"apple_available":true}"#)

        let methods = try await service.fetchSignInMethods().get()

        #expect(methods == SignInMethods(phrase: false, apple: true, appleAvailable: true))
        #expect(methods.addsFirstPhrase)
        #expect(methods.appleRow == .linked)
        #expect(lastRequest?.url?.path() == "/api/v1/me/sign-in-methods")
        #expect(lastRequest?.httpMethod == "GET")
    }

    /// The fields are required: an answer without one is a failure, which the screen reads as
    /// unknown (or keeps its cached answer), never as a «no».
    @Test
    func aMissingFieldIsAFailure() async {
        stub(status: 200, body: #"{"apple":false}"#)

        guard case .failure = await service.fetchSignInMethods() else {
            Issue.record("An answer without phrase should not decode")
            return
        }
    }
    
    /// identity-login could not be asked: a failure, not «no phrase».
    @Test
    func anUnreachableIdentityServiceIsAFailure() async {
        stub(status: 503, body: #"{"type":"/errors/unavailable","title":"x","status":503,"detail":"x"}"#)

        guard case .failure(.serverError(status: 503)) = await service.fetchSignInMethods() else {
            Issue.record("A 503 should be a server error")
            return
        }
    }

    /// Forward tolerance (decision 96): a field this build does not know is ignored.
    @Test
    func anExtraFieldIsIgnored() async throws {
        stub(status: 200, body: #"{"phrase":true,"apple":false,"apple_available":true,"passkeys":2,"google":{"linked":true}}"#)

        let methods = try await service.fetchSignInMethods().get()

        #expect(methods == SignInMethods(phrase: true, apple: false, appleAvailable: true))
        #expect(methods.appleRow == .add)
    }

    /// An older server answers 404: a failure, which the screen reads as unknown.
    @Test
    func anOlderServerIsAFailure() async {
        stub(status: 404, body: #"{"type":"/errors/not-found","title":"x","status":404,"detail":"x"}"#)

        guard case .failure(.notFound) = await service.fetchSignInMethods() else {
            Issue.record("A 404 should be not found")
            return
        }
    }

    /// Only an `https` page on the identity host opens; anything else is a failure before any web session.
    @Test(arguments: ["https://evil.test/link/apple?ticket=t1",
                      "http://id.platform.test/link/apple?ticket=t1",
                      "spiral://apple-linked?result=linked",
                      "javascript:alert(1)",
                      "not a url"])
    func anAppleLinkOffTheIdentityHostIsRefused(url: String) async {
        stub(status: 200, body: #"{"url":"\#(url)"}"#)

        guard case .failure(.validation) = await service.createAppleLink() else {
            Issue.record("\(url) should be refused")
            return
        }
    }
    
    /// New phrase's page gets the same check.
    @Test
    func aPhraseResetLinkIsCheckedToo() async throws {
        stub(status: 200, body: #"{"url":"spiral://phrase-changed?result=changed","expires_at":"2026-11-20T12:00:00Z"}"#)
        guard case .failure(.validation) = await service.createPhraseReset() else {
            Issue.record("A non-https phrase-reset link should be refused")
            return
        }
        
        stub(status: 200, body: #"{"url":"https://id.platform.test/rotate?ticket=t2","expires_at":"2026-11-20T12:00:00Z"}"#)
        let url = try await service.createPhraseReset().get()
        #expect(url.host() == "id.platform.test")
    }
    
    /// Without a known identity host (a platform URL of no known environment), `https` with a host is enough.
    @Test
    func anUnknownIdentityHostStillNeedsHttps() throws {
        #expect(try AgentPlatformService.identityPageURL("https://id.example.org/x", identityHost: nil).get().host() == "id.example.org")
        guard case .failure = AgentPlatformService.identityPageURL("https:///x", identityHost: nil),
              case .failure = AgentPlatformService.identityPageURL("ftp://id.example.org/x", identityHost: nil) else {
            Issue.record("A link without https and a host should be refused")
            return
        }
        #expect(try AgentPlatformService.identityPageURL("https://ID.Platform.test/x", identityHost: "id.platform.test").get().host() == "ID.Platform.test")
    }
    
    @Test
    func theAppleLinkIsTheIdentityPage() async throws {
        stub(status: 200, body: #"{"url":"https://id.platform.test/link/apple?ticket=t1","expires_at":"2026-11-20T12:00:00Z"}"#)

        let url = try await service.createAppleLink().get()

        #expect(url.absoluteString == "https://id.platform.test/link/apple?ticket=t1")
        #expect(lastRequest?.url?.path() == "/api/v1/me/apple-link")
        #expect(lastRequest?.httpMethod == "POST")
    }

    // MARK: - Helpers

    private var lastRequest: URLRequest? {
        SignInMethodsURLProtocol.requests.withLock { $0[testID]?.last }
    }

    private func stub(status: Int, body: String) {
        SignInMethodsURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: Data(body.utf8)) }
    }
}

/// Answers each test from its own stub, told apart by a header every request of that test's session carries.
private nonisolated class SignInMethodsURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: Stub]>([:])
    static let requests = Mutex<[String: [URLRequest]]>([:])

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let testID = request.value(forHTTPHeaderField: Self.testIDHeader) ?? ""
        Self.requests.withLock { $0[testID, default: []].append(request) }
        let stub = Self.stubs.withLock { $0[testID] } ?? Stub(status: 500, body: Data())

        let contentType = stub.status == 200 ? "application/json" : "application/problem+json"
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
