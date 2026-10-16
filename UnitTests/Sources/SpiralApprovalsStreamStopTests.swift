//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 154): after a sign-out or an account deletion the
// notifications stream kept dialling with the ended session's token. Once the
// session stops, nothing reconnects.
//

import AgentPlatformClient
@testable import ElementX
import Foundation
import Synchronization
import Testing

@MainActor
struct SpiralApprovalsStreamStopTests {
    private let testID = UUID().uuidString
    private let stream: ApprovalsStreamService

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamOpenURLProtocol.self]
        configuration.httpAdditionalHeaders = [StreamOpenURLProtocol.testIDHeader: testID]
        stream = ApprovalsStreamService(agentPlatformService: AgentPlatformServiceMock(),
                                        authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                        baseURL: "https://platform.test",
                                        urlSession: URLSession(configuration: configuration))
    }

    /// The server refuses the ended session's token; the stream would retry
    /// after 0.7 s + 1 s. Stopped, it does not.
    @Test
    func aStoppedStreamDoesNotReconnect() async throws {
        stream.connect()
        try await waitUntil { opens == 1 }

        stream.stop()
        try await Task.sleep(for: .seconds(2.5))

        #expect(opens == 1)
        #expect(stream.connectionState == .disconnected)
    }

    /// A foreground or a reappearing screen calls `connect()`; after the stop it dials nothing.
    @Test
    func aStoppedStreamDoesNotConnectAgain() async throws {
        stream.stop()
        stream.connect()
        try await Task.sleep(for: .milliseconds(300))

        #expect(opens == 0)
        #expect(stream.connectionState == .disconnected)
    }

    private var opens: Int {
        StreamOpenURLProtocol.opens.withLock { $0[testID] ?? 0 }
    }

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            try #require(ContinuousClock.now < deadline, "timed out")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Answers every stream open with 401, counting the opens per test.
private nonisolated class StreamOpenURLProtocol: URLProtocol {
    static let testIDHeader = "X-Test-ID"
    static let opens = Mutex<[String: Int]>([:])

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let testID = request.value(forHTTPHeaderField: Self.testIDHeader) ?? ""
        if url.path() == "/api/v1/notifications/stream" {
            Self.opens.withLock { $0[testID, default: 0] += 1 }
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
