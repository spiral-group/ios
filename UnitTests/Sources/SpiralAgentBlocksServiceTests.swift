//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 87): the two routes behind "Unblock" on a person's
// profile, against a stubbed transport — which of the person's agents block
// them, and undoing one agent's block.
//

import AgentPlatformClient
@testable import ElementX
import Foundation
import Synchronization
import Testing

@MainActor
struct SpiralAgentBlocksServiceTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentBlocksURLProtocol.self]
        configuration.httpAdditionalHeaders = [AgentBlocksURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    // MARK: - Which agents block a person

    @Test
    func theBlocksDecode() async throws {
        stub(status: 200, body: Data(#"""
        {"contact_mxid":"@bob:spiral.md","blocks":[
          {"agent_id":"\#(Self.agentID)","agent_mxid":"@assistant-alice:spiral.md","agent_name":"Aria","blocked_at":"2026-10-11T09:00:00Z"}
        ]}
        """#.utf8))

        let blocks = try await service.listAgentBlocks(ofContact: "@Bob:spiral.md").get()

        #expect(blocks == [AgentContactBlock(agentID: Self.agentID, agentMXID: "@assistant-alice:spiral.md", agentName: "Aria",
                                             blockedAt: Date(timeIntervalSince1970: 1_791_709_200))])
        let request = try #require(lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/api/v1/me/blocks")
        #expect(request.url?.queryItems["contact_mxid"] == "@Bob:spiral.md")
    }

    @Test
    func noBlocksIsAnEmptyList() async throws {
        stub(status: 200, body: Data(#"{"contact_mxid":"@bob:spiral.md","blocks":[]}"#.utf8))

        #expect(try await service.listAgentBlocks(ofContact: "@bob:spiral.md").get().isEmpty)
    }

    @Test
    func anMXIDThatDoesNotCanonicaliseIsAValidationError() async {
        stub(status: 400, body: problem(400, detail: "contact_mxid"))

        guard case .failure(.validation) = await service.listAgentBlocks(ofContact: "bob") else {
            Issue.record("A 400 should be .validation")
            return
        }
    }

    // MARK: - Unblocking

    @Test
    func anUnblockIsANoContentSuccess() async throws {
        stub(status: 204, body: Data())

        try await service.unblockContact("@bob:spiral.md", forAgent: Self.agentID).get()

        let request = try #require(lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path() == "/api/v1/agents/\(Self.agentID)/blocks")
        #expect(request.url?.queryItems["contact_mxid"] == "@bob:spiral.md")
    }

    @Test(arguments: [400, 403, 404, 500])
    func aRefusedUnblockIsAFailure(status: Int) async {
        stub(status: status, body: problem(status))

        let result = await service.unblockContact("@bob:spiral.md", forAgent: Self.agentID)

        switch (status, result) {
        case (400, .failure(.validation)), (403, .failure(.forbidden)), (404, .failure(.notFound)), (500, .failure(.serverError(status: 500))):
            break
        default:
            Issue.record("A \(status) mapped to \(result)")
        }
    }

    // MARK: - Helpers

    nonisolated static let agentID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02"

    private func stub(status: Int, body: Data) {
        AgentBlocksURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }

    private var lastRequest: URLRequest? {
        AgentBlocksURLProtocol.requests.withLock { $0[testID]?.last }
    }

    private func problem(_ status: Int, detail: String = "x") -> Data {
        Data(#"{"type":"/errors/x","title":"x","status":\#(status),"detail":"\#(detail)"}"#.utf8)
    }
}

private extension URL {
    var queryItems: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries.
private nonisolated class AgentBlocksURLProtocol: URLProtocol {
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
