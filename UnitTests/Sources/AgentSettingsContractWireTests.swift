//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decisions 193-196): the agent settings contract against a
// stubbed transport — what the read-model, the cards and the rooms carry, what
// an edit puts on the wire, and how the new refusals come back.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct AgentSettingsContractWireTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsContractURLProtocol.self]
        configuration.httpAdditionalHeaders = [SettingsContractURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    // MARK: - The read-model

    @Test
    func theReadModelCarriesThePauseTheCallLanguageAndTheVisitorPolicy() async throws {
        stub(status: 200, body: Self.readModel(paused: true, voiceLanguage: #""ru""#, visitorPolicy: "off"))

        let readModel = try await service.fetchAgentReadModel(agentID: Self.agentID).get()

        #expect(readModel.paused)
        #expect(readModel.voiceLanguage == .ru)
        #expect(readModel.visitorPolicy == .off)
    }

    /// Decision 96: a newer value reads as not set, and the screen offers no change.
    @Test
    func valuesThisBuildDoesNotKnowReadAsNotSet() async throws {
        stub(status: 200, body: Self.readModel(paused: false, voiceLanguage: #""de""#, visitorPolicy: "screen_first"))

        let readModel = try await service.fetchAgentReadModel(agentID: Self.agentID).get()

        #expect(!readModel.paused)
        #expect(readModel.voiceLanguage == nil)
        #expect(readModel.visitorPolicy == nil)
    }

    @Test
    func anAssistantWithoutVoiceHasNoCallLanguage() async throws {
        stub(status: 200, body: Self.readModel(paused: false, voiceLanguage: "null", visitorPolicy: "ask_first"))

        let readModel = try await service.fetchAgentReadModel(agentID: Self.agentID).get()

        #expect(readModel.voiceLanguage == nil)
        #expect(readModel.visitorPolicy == .askFirst)
    }

    @Test
    func aSpaceCardSaysTheAgentIsPaused() async throws {
        stub(status: 200, body: Data(#"""
        {"org_id":"org-1","name":"Acme","kind":"company","owner_user_id":"@me:spiral.md","agents":[
         {"agent_id":"a-1","matrix_user_id":"@agent-acme-1:spiral.md","display_name":"Sales","kind":"sales",
          "visibility":"public","lifecycle_state":"suspended","presence":"offline","last_active_at":"2026-10-31T07:00:00Z","room_count":0,"active_tool_count":0,"paused":true},
         {"agent_id":"a-2","matrix_user_id":"@agent-acme-2:spiral.md","display_name":"Support","kind":"support",
          "visibility":"public","lifecycle_state":"active","presence":"online","last_active_at":"2026-10-31T07:04:00Z","room_count":1,"active_tool_count":0,"paused":false}]}
        """#.utf8))

        let detail = try await service.fetchAgentSpace(orgID: "org-1").get()

        #expect(detail.agents.map(\.isPaused) == [true, false])
    }

    // MARK: - The edit

    @Test
    func anEditSendsThePauseTheCallLanguageAndTheVisitorPolicy() async throws {
        stub(status: 200, body: Self.readModel(paused: true, voiceLanguage: #""uk""#, visitorPolicy: "reply"))

        _ = try await service.editAgent(agentID: Self.agentID,
                                        patch: AgentEditPatch(voiceLanguage: .uk, visitorPolicy: .reply, paused: true)).get()

        let body = try requestBody()
        #expect(body["paused"] as? Bool == true)
        #expect(body["voice_language"] as? String == "uk")
        #expect((body["persona"] as? [String: Any])?["visitor_policy"] as? String == "reply")
        #expect(lastRequest?.httpMethod == "PATCH")
    }

    /// The visitor policy rides in the persona group, next to any text.
    @Test
    func theVisitorPolicyJoinsThePersonaGroup() async throws {
        stub(status: 200, body: Self.readModel(paused: false, voiceLanguage: "null", visitorPolicy: "off"))

        _ = try await service.editAgent(agentID: Self.agentID,
                                        patch: AgentEditPatch(persona: .init(visitorGreeting: "Hi"), visitorPolicy: .off)).get()

        let persona = try #require(try requestBody()["persona"] as? [String: Any])
        #expect(persona["visitor_policy"] as? String == "off")
        #expect(persona["visitor_greeting"] as? String == "Hi")
        #expect(persona["tone"] == nil)
    }

    /// A pause alone sends no persona group: the server refuses one for a role agent.
    @Test
    func aPauseAloneSendsNothingElse() async throws {
        stub(status: 200, body: Self.readModel(paused: true, voiceLanguage: "null", visitorPolicy: "ask_first"))

        _ = try await service.editAgent(agentID: Self.agentID, patch: AgentEditPatch(paused: true)).get()

        #expect(try requestBody().keys.sorted() == ["paused"])
    }

    // MARK: - The agent's rooms

    @Test
    func aRoomToolCarriesItsTriggerAndAudience() async throws {
        stub(status: 200, body: Data(#"""
        {"agent_id":"\#(Self.agentID)","rooms":[{"room_id":"!team:spiral.md","display_name":"Team","kind":"group","active_tools":[
          {"tool_id":"t1","tool_kind":"translate","target_languages":["en"],"trigger_kind":"on_message","audience":"everyone_except",
           "audience_members":["@bob:spiral.md"],"params_summary":"Translate → en","trigger_summary":"on message · everyone except"},
          {"tool_id":"t2","tool_kind":"call_summary","target_languages":[],"trigger_kind":"on_hologram","audience":"owner_only",
           "audience_members":[],"params_summary":"Summary","trigger_summary":"on call"}]}]}
        """#.utf8))

        let tools = try #require(try await service.fetchAgentRooms(agentID: Self.agentID).get().first?.activeTools)

        #expect(tools.map(\.firing) == [.onMessage, nil])
        #expect(tools.map(\.audience) == [.everyoneExcept(members: ["@bob:spiral.md"]), .ownerOnly])
    }

    // MARK: - The agent's blocks

    @Test
    func theBlocksArePagedByCursor() async throws {
        stub(status: 200, body: Data(#"""
        {"blocks":[{"contact_mxid":"@bob:spiral.md","display_name":"Bob","blocked_at":"2026-10-15T10:00:00Z"},
                   {"contact_mxid":"@eve:spiral.md","blocked_at":"2026-10-14T10:00:00Z"}],"next_cursor":"c2"}
        """#.utf8))

        let page = try await service.listBlockedContacts(agentID: Self.agentID, cursor: "c1", limit: 50).get()

        #expect(page.blocks.map(\.name) == ["Bob", "@eve:spiral.md"])
        #expect(page.nextCursor == "c2")
        let url = try #require(lastRequest?.url)
        #expect(url.path() == "/api/v1/agents/\(Self.agentID)/blocks")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "cursor" }?.value == "c1")
        #expect(query.first { $0.name == "limit" }?.value == "50")
    }

    // MARK: - The notifications hub

    @Test
    func theHubCarriesTheVisitorsEntries() async throws {
        stub(status: 200, body: Data(#"""
        {"needs_action":{"approvals":[],"verifications":[]},"activity":[],"unseen_count":2,"visitor_messages":[
          {"id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b10","kind":"message","agent_id":"\#(Self.agentID)","visitor_mxid":"@bob:spiral.md",
           "room_id":"!bob:spiral.md","body":"Are we on for Friday?","created_at":"2026-10-16T09:00:00Z"},
          {"id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b11","kind":"missed_call","agent_id":"\#(Self.agentID)","visitor_mxid":"@carol:spiral.md",
           "room_id":"!carol:spiral.md","body":"","created_at":"2026-10-16T08:00:00Z"}]}
        """#.utf8))

        let snapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()

        #expect(snapshot.visitorMessages.map(\.kind) == [.message, .missedCall])
        #expect(snapshot.visitorMessages.first?.body == "Are we on for Friday?")
        #expect(snapshot.visitorMessages.first?.visitorMXID == "@bob:spiral.md")
        #expect(snapshot.visitorMessages.last?.roomID == "!carol:spiral.md")
    }

    /// Decision 96: a kind newer than this build still decodes the hub, and
    /// its entry is the generic row asking to update.
    @Test
    func aNewerKindDecodesAndIsAGenericRow() async throws {
        stub(status: 200, body: Data(#"""
        {"needs_action":{"approvals":[],"verifications":[]},"activity":[],"unseen_count":1,"visitor_messages":[
          {"id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b12","kind":"voicemail","agent_id":"\#(Self.agentID)","visitor_mxid":"@dave:spiral.md",
           "room_id":"!dave:spiral.md","body":"…","created_at":"2026-10-16T07:00:00Z"}]}
        """#.utf8))

        let snapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()
        #expect(snapshot.visitorMessages.map(\.kind) == [.other("voicemail")])

        let platformService = AgentPlatformServiceMock()
        platformService.fetchNotificationsActivityCursorLimitReturnValue = .success(snapshot)
        platformService.markNotificationsSeenReturnValue = .success(Date())
        platformService.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForClosure = { .success(UserProfile(userID: $0, displayName: nil)) }
        let viewModel = NotificationsHubScreenViewModel(store: AgentsStore(service: platformService),
                                                        agentPlatformService: platformService,
                                                        clientProxy: clientProxy,
                                                        userIndicatorController: UserIndicatorControllerMock())
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.visitorMessages)) { !$0.isEmpty }
        try await shown.fulfill()

        let row = try #require(viewModel.context.viewState.visitorMessages.first)
        #expect(row.title == UntranslatedL10n.screenNotificationsHubVisitorOther)
        #expect(row.body == UntranslatedL10n.screenNotificationsHubVisitorOtherBody)
    }

    @Test
    func aDismissDeletesTheEntry() async throws {
        stub(status: 204)

        try await service.dismissVisitorMessage(id: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b10").get()

        #expect(lastRequest?.httpMethod == "DELETE")
        #expect(lastRequest?.url?.path() == "/api/v1/me/notifications/visitor-messages/0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b10")
    }

    @Test
    func aDismissOfAnEntryAlreadyGoneIsNotFound() async throws {
        problem(status: 404, type: "/errors/not-found")

        let result = await service.dismissVisitorMessage(id: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b10")

        guard case .failure(.notFound) = result else {
            Issue.record("Expected not found, got \(result)")
            return
        }
    }

    // MARK: - A paused agent

    @Test
    func anApproveWhilePausedIsItsOwnRefusal() async throws {
        problem(status: 409, type: "/errors/agent-paused")

        let result = await service.decideApproval(id: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b20", decision: .approve)

        guard case .failure(.agentPaused) = result else {
            Issue.record("Expected agent paused, got \(result)")
            return
        }
    }

    /// The other 409 still means "already decided".
    @Test
    func anAlreadyDecidedApproveStaysAConflict() async throws {
        problem(status: 409, type: "/errors/conflict")

        let result = await service.decideApproval(id: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b20", decision: .edit(newBody: "Hi"))

        guard case .failure(.conflict) = result else {
            Issue.record("Expected conflict, got \(result)")
            return
        }
    }

    @Test
    func anAttachWhilePausedIsItsOwnRefusal() async throws {
        problem(status: 409, type: "/errors/agent-paused")

        let result = await service.attachVoiceAgent(agentID: Self.agentID,
                                                    roomID: "!room:spiral.md",
                                                    params: VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: false))

        guard case .failure(.agentPaused) = result else {
            Issue.record("Expected agent paused, got \(result)")
            return
        }
        #expect(NativeAgentCenterError(.agentPaused).localizedDescription == UntranslatedL10n.screenNativeCallAgentCenterErrorAgentPaused)
    }

    // MARK: - Fixtures

    static let agentID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b01"

    static func readModel(paused: Bool, voiceLanguage: String, visitorPolicy: String) -> Data {
        Data(#"""
        {"agent_id":"\#(agentID)","matrix_user_id":"@assistant-me:spiral.md","kind":"personal_assistant",
         "organization_id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b03","display_name":"Assistant","visibility":"private",
         "lifecycle_state":"\#(paused ? "suspended" : "active")","config_version_id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b04",
         "config_version_number":3,"room_count":1,"active_tool_count":0,"paused":\#(paused),"voice_language":\#(voiceLanguage),
         "persona":{"owner_display_name":"Anna","tone":"Friendly","greeting":"Hi","visitor_greeting":"Hello",
                    "visitor_policy":"\#(visitorPolicy)"}}
        """#.utf8)
    }

    // MARK: - Stubbing

    func stub(status: Int, contentType: String = "application/json", body: Data = Data()) {
        SettingsContractURLProtocol.stubs.withLock { $0[testID] = .init(status: status, contentType: contentType, body: body) }
    }

    func problem(status: Int, type: String) {
        stub(status: status,
             contentType: "application/problem+json",
             body: Data(#"{"type":"\#(type)","title":"Conflict","status":\#(status),"detail":"refused"}"#.utf8))
    }

    var lastRequest: URLRequest? {
        SettingsContractURLProtocol.requests.withLock { $0[testID]?.last }
    }

    func requestBody() throws -> [String: Any] {
        let data = try #require(SettingsContractURLProtocol.bodies.withLock { $0[testID]?.last })
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries.
private nonisolated class SettingsContractURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let contentType: String
        let body: Data
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: Stub]>([:])
    static let bodies = Mutex<[String: [Data]]>([:])
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
        Self.bodies.withLock { $0[testID, default: []].append(Self.bodyData(of: request)) }
        let stub = Self.stubs.withLock { $0[testID] } ?? Stub(status: 500, contentType: "application/problem+json", body: Data())

        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": stub.contentType]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }

    /// URLSession hands a protocol the body as a stream; read it to the end.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
