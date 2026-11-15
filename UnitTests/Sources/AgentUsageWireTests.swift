//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 394): `GET /agents/{id}/usage` decodes against a stubbed transport — the current window,
// a period or category this build does not know, and a failure that is no answer.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct AgentUsageWireTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentUsageURLProtocol.self]
        configuration.httpAdditionalHeaders = [AgentUsageURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    @Test
    func theCurrentWindowAndTheDaysDecode() async throws {
        stub(status: 200, body: Self.body(period: "week", category: "call_translation"))

        let usage = try await service.fetchAgentUsage(agentID: Self.agentID).get()

        #expect(usage.current == .init(period: .week,
                                       startsAt: Date(timeIntervalSince1970: 1_794_182_400),
                                       resetsAt: Date(timeIntervalSince1970: 1_794_787_200),
                                       usedPercent: 35,
                                       limitReached: false,
                                       categories: [.init(category: .callTranslation, usedPercent: 25)]))
        #expect(usage.days == [.init(id: "2026-11-11", date: Date(timeIntervalSince1970: 1_794_355_200), usedPercent: 35,
                                     categories: [.init(category: .callTranslation, usedPercent: 25)])])
        #expect(AgentUsageURLProtocol.requests.withLock { $0[testID]?.last?.url?.path() } == "/api/v1/agents/\(Self.agentID)/usage")
    }

    /// Forward tolerance (decision 96): a newer period reads as a neutral limit, a newer category as other.
    @Test(arguments: ["day", "fortnight"])
    func aPeriodWithoutItsOwnWordsReadsNeutral(period: String) async throws {
        stub(status: 200, body: Self.body(period: period, category: "voice_cloning"))

        let usage = try await service.fetchAgentUsage(agentID: Self.agentID).get()

        #expect(usage.current.period == .other)
        #expect(usage.current.categories.map(\.category) == [.other])
        #expect(usage.days.first?.categories.map(\.category) == [.other])
    }

    /// The server's 500 is "the limit could not be read": a failure, never a 0% page.
    @Test
    func anUnreadableLimitIsAFailure() async {
        stub(status: 500, body: Data(#"{"type":"/errors/internal","title":"x","status":500,"detail":"x"}"#.utf8))

        guard case .failure(.serverError(status: 500)) = await service.fetchAgentUsage(agentID: Self.agentID) else {
            Issue.record("A 500 should be a server error")
            return
        }
    }

    /// Question 395: the current window's categories say whether they are paused; a `null` date is a pause without one,
    /// and unknown categories merge into one other.
    @Test
    func pausesDecodeAndUnknownCategoriesMerge() async throws {
        stub(status: 200, body: Data(#"""
        {"current":{"period":"week","starts_at":"2026-11-09T00:00:00Z","resets_at":"2026-11-16T00:00:00Z",
          "used_percent":35.0,"limit_reached":false,"categories":[
            {"category":"room_tools","used_percent":30.0,"paused":true,"pause_until":"2026-11-16T00:00:00Z"},
            {"category":"posts","used_percent":0.0,"paused":true,"pause_until":null},
            {"category":"calls","used_percent":3.0,"paused":false},
            {"category":"voice_cloning","used_percent":1.0,"paused":false},
            {"category":"image_making","used_percent":1.0,"paused":true,"pause_until":null}]},
         "days":[]}
        """#.utf8))

        let usage = try await service.fetchAgentUsage(agentID: Self.agentID).get()

        #expect(usage.current.categories == [.init(category: .roomTools, usedPercent: 30, pause: .until(Date(timeIntervalSince1970: 1_794_787_200))),
                                             .init(category: .posts, usedPercent: 0, pause: .untilChanged),
                                             .init(category: .calls, usedPercent: 3),
                                             .init(category: .other, usedPercent: 2, pause: .untilChanged)])
    }

    // MARK: - Helpers

    nonisolated static let agentID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02"

    private static func body(period: String, category: String) -> Data {
        Data(#"""
        {"current":{"period":"\#(period)","starts_at":"2026-11-09T00:00:00Z","resets_at":"2026-11-16T00:00:00Z",
          "used_percent":35.0,"limit_reached":false,"categories":[{"category":"\#(category)","used_percent":25.0,"paused":false}]},
         "days":[{"date":"2026-11-11","used_percent":35.0,"categories":[{"category":"\#(category)","used_percent":25.0}]}]}
        """#.utf8)
    }

    private func stub(status: Int, body: Data) {
        AgentUsageURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }
}

/// Answers each test from its own stub, told apart by a header every request of that test's session carries.
private nonisolated class AgentUsageURLProtocol: URLProtocol {
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
