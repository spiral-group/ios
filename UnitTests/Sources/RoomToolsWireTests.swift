//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (ADR-0088): room tools against a stubbed transport — the
// room read, what goes on the wire for an edit, and how the backend's typed
// refusals come back from the arm, from keeping a call's translation as the
// room's rule, and from attaching an agent that is already in the call.
//

import AgentPlatformClient
@testable import ElementX
import Foundation
import Synchronization
import Testing

@MainActor
struct RoomToolsWireTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoomToolsURLProtocol.self]
        configuration.httpAdditionalHeaders = [RoomToolsURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    // MARK: - Edit

    @Test
    func anEditSendsTheReplacedToolID() async throws {
        stub(status: 200, contentType: "application/json", body: Self.applied)

        _ = try await service.armTool(agentID: "agent-1",
                                      roomID: "!room:platform.test",
                                      params: .translate(targetLanguage: "fr"),
                                      trigger: .onMessage(senderScope: .anyone),
                                      replacesToolID: "old-1").get()

        let body = try requestBody()
        #expect(body["replaces_tool_id"] as? String == "old-1")
        #expect((body["params"] as? [String: Any])?["kind"] as? String == "translate")
    }

    @Test
    func aNewToolSendsNoReplacedToolID() async throws {
        stub(status: 200, contentType: "application/json", body: Self.applied)

        _ = try await service.armTool(agentID: "agent-1",
                                      roomID: "!room:platform.test",
                                      params: .simplify,
                                      trigger: .onMessage(senderScope: .anyone),
                                      replacesToolID: nil).get()

        let body = try requestBody()
        #expect(body["replaces_tool_id"] == nil)
    }

    // MARK: - Refusals

    @Test
    func theCapRefusalIsTyped() async {
        stub(status: 409, contentType: "application/problem+json", body: Self.problem(type: "/errors/tool-cap-reached", status: 409))

        guard case .failure(.refused(.capReached)) = await arm() else {
            Issue.record("A 409 tool-cap-reached should be .capReached")
            return
        }
    }

    @Test
    func theDuplicateRefusalIsTyped() async {
        stub(status: 409, contentType: "application/problem+json", body: Self.problem(type: "/errors/tool-duplicate", status: 409))

        guard case .failure(.refused(.duplicate)) = await arm() else {
            Issue.record("A 409 tool-duplicate should be .duplicate")
            return
        }
    }

    @Test
    func theDoesNotFireHereRefusalIsTypedWithItsReason() async {
        stub(status: 422, contentType: "application/problem+json", body: Self.problem(type: "/errors/tool-does-not-fire-here", status: 422,
                                                                                      detail: "a text tool never fires in the owner DM"))

        guard case .failure(.refused(.doesNotFireHere(let reason))) = await arm() else {
            Issue.record("A 422 tool-does-not-fire-here should be .doesNotFireHere")
            return
        }
        #expect(reason == "a text tool never fires in the owner DM")
    }

    /// Decision 168: a call tool on a company agent is refused with the same
    /// typed 422, the contract's own detail kept for the log.
    @Test
    func aCallToolOnAnAgentThatJoinsNoCallsIsTheDoesNotFireHereRefusal() async {
        let detail = "tool `call_summary` never fires in the calls of an agent that does not join calls: company agents do not join calls in this version, so a call tool would never run."
        stub(status: 422, contentType: "application/problem+json", body: Self.problem(type: "/errors/tool-does-not-fire-here", status: 422,
                                                                                      detail: detail))

        guard case .failure(.refused(.doesNotFireHere(let reason))) = await arm() else {
            Issue.record("A 422 tool-does-not-fire-here should be .doesNotFireHere")
            return
        }
        #expect(reason == detail)
    }

    /// Review #4: the edited tool was turned off meanwhile; nothing changed.
    @Test
    func anEditOfAToolTurnedOffElsewhereIsReplacedGone() async {
        stub(status: 409, contentType: "application/problem+json", body: Self.problem(type: "/errors/tool-replaced-gone", status: 409))

        guard case .failure(.replacedGone) = await arm() else {
            Issue.record("A 409 tool-replaced-gone should be .replacedGone")
            return
        }
    }

    /// The prose is free to change; only the `type` names a refusal.
    @Test
    func aRefusalIsNotReadFromItsProse() async {
        stub(status: 409, contentType: "application/problem+json", body: Self.problem(type: "/errors/conflict", status: 409,
                                                                                      detail: "tool-cap-reached: 5 tools"))

        guard case .failure(.failed(.conflict)) = await arm() else {
            Issue.record("An untyped 409 should stay a plain conflict")
            return
        }
    }

    /// A stale token is retried once, as for every other platform call.
    @Test
    func anExpiredTokenIsRetriedOnce() async throws {
        stub(status: 401, contentType: "application/problem+json", body: Self.problem(type: "/errors/unauthorized", status: 401))

        guard case .failure(.failed(.unauthorized)) = await arm() else {
            Issue.record("A 401 should be .unauthorized")
            return
        }
        let requests = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID] })
        #expect(requests.count == 2)
    }

    @Test
    func aGateDenialStaysAValidationFailure() async {
        stub(status: 422, contentType: "application/problem+json", body: Self.problem(type: "/errors/unprocessable", status: 422,
                                                                                      detail: "denied by the gate"))

        guard case .failure(.failed(.validation(let detail))) = await arm() else {
            Issue.record("An untyped 422 should be .validation")
            return
        }
        #expect(detail == "denied by the gate")
    }

    // MARK: - Keeping a call's translation as the room's rule

    /// Refused like an arm; the words are the arm form's (`RoomToolRefusal.message`).
    @Test(arguments: [("/errors/tool-cap-reached", 409, RoomToolRefusal.capReached),
                      ("/errors/tool-duplicate", 409, .duplicate),
                      ("/errors/tool-does-not-fire-here", 422, .doesNotFireHere(reason: "x"))])
    func aRefusedRoomDefaultIsTyped(type: String, status: Int, refusal: RoomToolRefusal) async throws {
        stub(status: status, contentType: "application/problem+json", body: Self.problem(type: type, status: status))

        guard case .failure(.toolRefused(let received)) = await service.saveVoiceTranslationAsRoomDefault(sessionID: "session-1") else {
            Issue.record("A \(status) \(type) should be .toolRefused")
            return
        }
        #expect(received == refusal)
        let request = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID]?.last })
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/v1/voice-sessions/session-1/controls/translation/save-as-room-default")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mat_test")
    }

    @Test
    func aRoomDefaultWithNothingToSaveIsStillRejected() async {
        stub(status: 422, contentType: "application/problem+json", body: Self.problem(type: "/errors/unprocessable", status: 422))

        guard case .failure(.rejected) = await service.saveVoiceTranslationAsRoomDefault(sessionID: "session-1") else {
            Issue.record("An untyped 422 should stay .rejected")
            return
        }
    }

    @Test
    func aSavedRoomDefaultSucceeds() async throws {
        stub(status: 200, contentType: "application/json", body: Data(#"{"status":"promoted","action_log_id":"log-1"}"#.utf8))

        try await service.saveVoiceTranslationAsRoomDefault(sessionID: "session-1").get()
    }

    @Test
    func anEndedSessionIsGone() async {
        stub(status: 410, contentType: "application/problem+json", body: Self.problem(type: "/errors/gone", status: 410))

        guard case .failure(.gone) = await service.saveVoiceTranslationAsRoomDefault(sessionID: "session-1") else {
            Issue.record("A 410 should be .gone")
            return
        }
    }

    // MARK: - Call controls

    /// Review: the call controls documented a stale-token retry and ran once.
    @Test
    func aCallControlsReadRetriesOnceOnAStaleToken() async throws {
        stub(status: 401, contentType: "application/problem+json", body: Self.problem(type: "/errors/unauthorized", status: 401))

        guard case .failure = await service.voiceSessionControls(sessionID: "session-1") else {
            Issue.record("A 401 twice should fail")
            return
        }
        let requests = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID] })
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.path() == "/api/v1/voice-sessions/session-1/controls" })
    }

    /// A booth conflict has its own type (`/errors/booth-conflict`): change
    /// the configuration, do not retry. Its detail keeps only the human copy.
    @Test
    func aBoothConflictIsARejection() async {
        stub(status: 409, contentType: "application/problem+json",
             body: Self.problem(type: "/errors/booth-conflict", status: 409,
                                detail: "rejected: [booth-conflict agent=agent-2] Bob's Assistant already translates this speaker"))

        let result = await service.setVoiceSwitch(sessionID: "session-1", control: .conversation, enabled: true, revision: 3)

        guard case .failure(.rejected(let detail)) = result else {
            Issue.record("A booth conflict should be .rejected, got \(result)")
            return
        }
        #expect(detail == "Bob's Assistant already translates this speaker")
    }

    /// Any other 409 is the revision clash, whatever its prose says: the
    /// platform no longer sends a booth conflict as a plain conflict.
    @Test
    func aPlainConflictIsARevisionClash() async {
        stub(status: 409, contentType: "application/problem+json",
             body: Self.problem(type: "/errors/conflict", status: 409,
                                detail: "rejected: [booth-conflict agent=agent-2] Bob's Assistant already translates this speaker"))

        guard case .failure(.conflict) = await service.setVoiceSwitch(sessionID: "session-1", control: .conversation, enabled: true, revision: 3) else {
            Issue.record("A plain 409 should be .conflict")
            return
        }
    }

    // MARK: - Attaching an agent that is already in the call

    @Test
    func anActiveSessionIsJoined() async {
        stub(status: 409, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/voice-session-active","title":"x","status":409,"detail":"x","existing_session_id":"session-7"}"#.utf8))

        guard case .success("session-7") = await attach() else {
            Issue.record("A voice-session-active 409 should join the existing session")
            return
        }
    }

    /// Not a voice agent, or the running session could not be read back: a
    /// retry, never a join of whatever id happens to ride along.
    @Test
    func anyOtherAttachConflictIsARetry() async {
        stub(status: 409, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/conflict","title":"x","status":409,"detail":"x","existing_session_id":"session-7"}"#.utf8))

        guard case .failure(.conflict) = await attach() else {
            Issue.record("An untyped attach 409 should be .conflict")
            return
        }
    }

    // MARK: - Add agent (decision 180)

    /// WYSIWYG: every toggle of the sheet is on the wire, Conversation included.
    @Test
    func theAttachSendsConversationWithEveryOtherControl() async throws {
        stub(status: 202, contentType: "application/json", body: Self.accepted)

        _ = try await attach(conversation: true).get()

        let controls = try #require(try requestBody()["controls"] as? [String: [String: Any]])
        #expect(controls["conversation"]?["state"] as? String == "enabled")
        #expect(controls["translation"]?["state"] as? String == "disabled")
        #expect(controls["recording"]?["state"] as? String == "disabled")
        #expect(controls["summary"]?["state"] as? String == "enabled")
    }

    /// Off is the call's own rule, so the owner's own chat with the
    /// assistant still talks: `inherit`, never `disabled`.
    @Test
    func conversationOffIsTheCallsOwnRule() async throws {
        stub(status: 202, contentType: "application/json", body: Self.accepted)

        _ = try await attach(conversation: false).get()

        let controls = try #require(try requestBody()["controls"] as? [String: [String: Any]])
        #expect(controls["conversation"]?["state"] as? String == "inherit")
    }

    /// The languages come from the agent, with no session to ask.
    @Test
    func theCatalogIsReadForTheAgentWithoutASession() async throws {
        stub(status: 200, contentType: "application/json", body: Data(#"""
        {"controls":[],"params_schema":{},
         "voice_translation_languages":[{"code":"en","display_name":"English"},{"code":"uk","display_name":"Ukrainian"}]}
        """#.utf8))

        let catalog = try await service.voiceControlsCatalog(agentID: "agent-1").get()

        #expect(catalog.voiceTranslationLanguages == [.init(code: "en", label: "English"), .init(code: "uk", label: "Ukrainian")])
        let request = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID]?.last })
        #expect(request.url?.path == "/api/v1/agents/agent-1/voice-controls/catalog")
    }

    // MARK: - Room read

    /// The room read as the platform sends it: joined agents only, so no
    /// membership field (room-tools audit finding 12).
    @Test
    func aRoomReadDecodes() async throws {
        stub(status: 200, contentType: "application/json", body: Self.roomRead)

        let room = try await service.fetchRoomTools(roomID: "!room:platform.test").get()

        #expect(room == Self.expectedRoom)
    }

    // MARK: - Helpers

    private static let applied = Data(#"{"status":"applied","action_log_id":"log-1"}"#.utf8)

    /// An own agent with a full Tool and another owner's agent with a safe slice.
    private static let roomRead = Data(#"""
    {"room_id":"!room:platform.test","agents":[
      {"agent_id":"agent-1","matrix_user_id":"@assistant-alice:platform.test","display_name":"Alice's Assistant",
       "owner_user_id":"@alice:platform.test","is_mine":true,
       "tools":[{"id":"tool-1","tool_kind":"translate","trigger_kind":"on_message","target_language":"fr",
                 "params":{"kind":"translate","target_language":"fr"},
                 "trigger":{"kind":"on_message","sender_scope":"anyone"}}]},
      {"agent_id":"agent-2","matrix_user_id":"@assistant-bob:platform.test","display_name":"Bob's Assistant",
       "owner_user_id":"@bob:platform.test","is_mine":false,
       "tools":[{"id":null,"tool_kind":"summarize","trigger_kind":"on_message","target_language":null,
                 "params":null,"trigger":null}]}
    ]}
    """#.utf8)

    private static let expectedRoom = RoomToolsView(roomID: "!room:platform.test", agents: [
        RoomToolAgentEntry(agentID: "agent-1", matrixUserID: "@assistant-alice:platform.test", displayName: "Alice's Assistant",
                           ownerUserID: "@alice:platform.test", isMine: true,
                           tools: [RoomToolView(toolID: "tool-1", toolKind: "translate", triggerKind: "on_message", targetLanguage: "fr",
                                                params: .translate(targetLanguage: "fr"), trigger: .onMessage(senderScope: .anyone),
                                                safeSliceSalt: "0.0")]),
        RoomToolAgentEntry(agentID: "agent-2", matrixUserID: "@assistant-bob:platform.test", displayName: "Bob's Assistant",
                           ownerUserID: "@bob:platform.test", isMine: false,
                           tools: [RoomToolView(toolID: nil, toolKind: "summarize", triggerKind: "on_message", targetLanguage: nil,
                                                params: nil, trigger: nil, safeSliceSalt: "1.0")])
    ])

    private static func problem(type: String, status: Int, detail: String = "x") -> Data {
        Data(#"{"type":"\#(type)","title":"x","status":\#(status),"detail":"\#(detail)"}"#.utf8)
    }

    private func attach(conversation: Bool = false) async -> Result<String, VoiceControlsError> {
        await service.attachVoiceAgent(agentID: "agent-1",
                                       roomID: "!room:platform.test",
                                       params: VoiceAttachParams(translation: nil, recording: false, summary: true, conversation: conversation))
    }

    private static let accepted = Data(#"""
    {"session_id":"session-1","agent_mxid":"@assistant-alice:platform.test","room_id":"!room:platform.test",
     "state":"pending_consent","leave_policy":"call_end","call_in_progress":false}
    """#.utf8)

    private func arm() async -> Result<ControlSetResultView, RoomToolArmError> {
        await service.armTool(agentID: "agent-1",
                              roomID: "!room:platform.test",
                              params: .translate(targetLanguage: "fr"),
                              trigger: .onMessage(senderScope: .anyone),
                              replacesToolID: nil)
    }

    private func stub(status: Int, contentType: String, body: Data) {
        RoomToolsURLProtocol.stubs.withLock { $0[testID] = .init(status: status, contentType: contentType, body: body) }
    }

    private func requestBody() throws -> [String: Any] {
        let data = try #require(RoomToolsURLProtocol.bodies.withLock { $0[testID]?.last })
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries.
private nonisolated class RoomToolsURLProtocol: URLProtocol {
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

    /// URLSession hands a protocol the body as a stream, not as `httpBody`.
    /// The transport writes it while this reads, so read to the end: stopping
    /// at "no bytes yet" lost the body, and closing the stream under the
    /// writer crashed it (`wroteFinalChunk() called in invalid state: closed`).
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
