//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 98): the owner's messenger ignore list, sent whole
// so that their agents ignore the same people, against a stubbed transport.
// Decision 136: a re-provisioned personal assistant gets it right away.
//

import AgentPlatformClient
import Combine
@testable import ElementX
import Foundation
import Synchronization
import Testing

@MainActor
struct SpiralOwnerBlocksServiceTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OwnerBlocksURLProtocol.self]
        configuration.httpAdditionalHeaders = [OwnerBlocksURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    @Test
    func theWholeListIsPutAndANoContentIsASuccess() async throws {
        stub(status: 204)

        try await service.syncIgnoredUsers(["@Bob:remote.org", "@eve:spiral.md"]).get()

        let request = try #require(lastRequest)
        #expect(request.method == "PUT")
        #expect(request.path == "/api/v1/me/ignored-users")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["user_ids"] as? [String] == ["@Bob:remote.org", "@eve:spiral.md"])
    }

    @Test
    func anEmptyListIsSentToo() async throws {
        stub(status: 204)

        try await service.syncIgnoredUsers([]).get()

        let request = try #require(lastRequest)
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["user_ids"] as? [String] == [])
    }

    @Test(arguments: [400, 500])
    func aRefusedListIsAFailure(status: Int) async {
        stub(status: status, body: problem(status))

        let result = await service.syncIgnoredUsers(["@bob:spiral.md"])

        switch (status, result) {
        case (400, .failure(.validation)), (500, .failure(.serverError(status: 500))):
            break
        default:
            Issue.record("A \(status) mapped to \(result)")
        }
    }

    // MARK: - Asking for the list again

    /// An erase of an assistant's memory about a person drops the rows the
    /// owner's block of them lived in.
    @Test
    func anEraseAsksForTheListAgain() async throws {
        var resyncs = 0
        let cancellable = service.ownerBlocksResyncPublisher.sink { resyncs += 1 }
        stub(status: 200, body: Data(#"""
        {"status":"purged","contact_mxid":"@bob:spiral.md","deleted_count":1,
         "erased":{"memory_entries":1,"relationships":1,"transcript_lines":0,"outreach_targets":0,"approvals":0,
                   "key_relay_rows":0,"action_log_entries_scrubbed":0,"session_controls_scrubbed":0,
                   "invite_redemptions_scrubbed":0,"verifications":0,"tool_scopes_rewritten":0,"tools_turned_off":0}}
        """#.utf8))

        _ = try await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md").get()

        #expect(resyncs == 1)
        _ = cancellable
    }

    @Test
    func aRefusedEraseAsksForNothing() async {
        var resyncs = 0
        let cancellable = service.ownerBlocksResyncPublisher.sink { resyncs += 1 }
        stub(status: 500, body: problem(500))

        _ = await service.eraseAssistantMemory(aboutContact: "@bob:spiral.md")

        #expect(resyncs == 0)
        _ = cancellable
    }

    /// A new company agent has none of the owner's blocks yet.
    @Test
    func aNewCompanyAgentAsksForTheListAgain() async throws {
        var resyncs = 0
        let cancellable = service.ownerBlocksResyncPublisher.sink { resyncs += 1 }
        stub(status: 201, body: Data(#"""
        {"agent_id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02","matrix_user_id":"@agent-acme-1:spiral.md","kind":"sales",
         "organization_id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b03","display_name":"Sales","visibility":"public",
         "lifecycle_state":"active","config_version_id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b04","config_version_number":1,
         "room_count":0,"active_tool_count":0,"paused":false}
        """#.utf8))

        try await service.createCompanyAgent(companyID: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b03", role: "sales", displayName: nil, roleBrief: nil).get()

        #expect(resyncs == 1)
        _ = cancellable
    }

    // MARK: - A new personal assistant (decision 136)

    /// Any response naming a personal assistant other than the last one seen
    /// asks for the list. The first one of a session is covered by the launch
    /// PUT, and a company space's agents are not the assistant.
    @Test
    func anotherAssistantAsksForTheListAgain() async throws {
        var resyncs = 0
        let cancellable = service.ownerBlocksResyncPublisher.sink { resyncs += 1 }
        stubPersonalSpace(assistantID: Self.assistantID)
        _ = try await service.fetchAgentSpace(orgID: Self.personalSpaceID).get()
        _ = try await service.listMyPersonalAgents().get()
        stub(path: "/api/v1/agent-spaces/\(Self.companySpaceID)", status: 200, body: Self.space(id: Self.companySpaceID, kind: "company",
                                                                                                agents: [Self.card(id: Self.reprovisionedID, kind: "sales")]))
        _ = try await service.fetchAgentSpace(orgID: Self.companySpaceID).get()
        #expect(resyncs == 0)

        stubPersonalSpace(assistantID: Self.reprovisionedID)
        _ = try await service.listMyPersonalAgents().get()

        #expect(resyncs == 1)
        _ = cancellable
    }

    /// Decision 153: the server keeps the personal assistant; its 409 is a
    /// conflict the screen names, not a failure to retry.
    @Test
    func archivingThePersonalAssistantIsRefused() async {
        stub(path: "/api/v1/agents/\(Self.assistantID)", status: 409, body: Data(#"""
        {"type":"/errors/personal-assistant-not-deletable","title":"Personal assistant cannot be deleted","status":409,
         "detail":"the personal assistant is created with your account and is deleted with it"}
        """#.utf8))

        let result = await service.archiveAgent(agentID: Self.assistantID)

        guard case .failure(.conflict(let detail)) = result else {
            Issue.record("expected a conflict, got \(result)")
            return
        }
        #expect(detail == "the personal assistant is created with your account and is deleted with it")
    }

    // MARK: - Helpers

    private static let personalSpaceID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b10"
    private static let companySpaceID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b11"
    private static let assistantID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b12"
    private static let reprovisionedID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b13"

    private func stub(status: Int, body: Data = Data()) {
        OwnerBlocksURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }

    private func stub(path: String, status: Int, body: Data = Data()) {
        OwnerBlocksURLProtocol.pathStubs.withLock { $0[testID, default: [:]][path] = .init(status: status, body: body) }
    }

    /// The directory and the Personal space, with the assistant when there is one.
    private func stubPersonalSpace(assistantID: String?) {
        let status = assistantID == nil ? "in_progress" : "ready"
        stub(path: "/api/v1/me/agent-spaces", status: 200, body: Data(#"""
        {"spaces":[{"org_id":"\#(Self.personalSpaceID)","name":"Personal","kind":"solo","agent_count":1}],
         "provisioning_status":"\#(status)"}
        """#.utf8))
        let agents = assistantID.map { [Self.card(id: $0, kind: "personal_assistant")] } ?? []
        stub(path: "/api/v1/agent-spaces/\(Self.personalSpaceID)", status: 200, body: Self.space(id: Self.personalSpaceID, kind: "solo", agents: agents))
    }

    private static func space(id: String, kind: String, agents: [String]) -> Data {
        Data(#"""
        {"org_id":"\#(id)","name":"Space","kind":"\#(kind)","owner_user_id":"@me:spiral.md","agents":[\#(agents.joined(separator: ","))]}
        """#.utf8)
    }

    private static func card(id: String, kind: String) -> String {
        #"""
        {"agent_id":"\#(id)","matrix_user_id":"@assistant-me:spiral.md","display_name":"Assistant","kind":"\#(kind)",
         "visibility":"private","lifecycle_state":"active","presence":"online","room_count":0,"active_tool_count":0,"paused":false}
        """#
    }

    private var lastRequest: OwnerBlocksURLProtocol.Recorded? {
        OwnerBlocksURLProtocol.requests.withLock { $0[testID]?.last }
    }

    private var recordedRequests: [OwnerBlocksURLProtocol.Recorded] {
        OwnerBlocksURLProtocol.requests.withLock { $0[testID] ?? [] }
    }

    private func problem(_ status: Int) -> Data {
        Data(#"{"type":"/errors/x","title":"x","status":\#(status),"detail":"user_ids"}"#.utf8)
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries, and keeps what each request sent.
private nonisolated class OwnerBlocksURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
    }

    struct Recorded {
        let method: String?
        let path: String?
        let body: Data
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: Stub]>([:])
    /// Per test, by path; the test's own stub answers every other path.
    static let pathStubs = Mutex<[String: [String: Stub]]>([:])
    static let requests = Mutex<[String: [Recorded]]>([:])

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
        let recorded = Recorded(method: request.httpMethod, path: url.path(), body: Self.body(of: request))
        Self.requests.withLock { $0[testID, default: []].append(recorded) }
        let stub = Self.pathStubs.withLock { $0[testID]?[url.path()] } ?? Self.stubs.withLock { $0[testID] } ?? Stub(status: 500, body: Data())

        let contentType = (200..<300).contains(stub.status) ? "application/json" : "application/problem+json"
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }

    /// A session hands the body over as a stream, not as `httpBody`.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
