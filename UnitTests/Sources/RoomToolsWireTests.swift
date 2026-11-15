//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (ADR-0088): room tools against a stubbed transport — the
// room read, what goes on the wire for an edit, and how the backend's typed
// refusals come back from the arm and from attaching an agent that is already
// in the call; and call translation's contract (ADR-0094 A.2, A.3, A.8).
//

import AgentPlatformClient
import Foundation
@testable import Spiral
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
        service = AgentPlatformService(client: client, serviceUnavailableRetryDelay: Self.retryDelay)
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

    /// ADR-0094 A.5 as the backend decodes it (implementation note 3): one language, and the scope a bare string.
    @Test
    func thePersonalCallTranslationToolSendsOneLanguageForAnyone() async throws {
        stub(status: 200, contentType: "application/json", body: Self.applied)

        _ = try await service.armTool(agentID: "agent-1",
                                      roomID: "!room:platform.test",
                                      params: .liveTranslate(language: "zh-Hans"),
                                      trigger: .onVoiceCall(speakerScope: .anyone),
                                      replacesToolID: nil).get()

        let body = try requestBody()
        let params = try #require(body["params"] as? [String: Any])
        #expect(NSDictionary(dictionary: params) == NSDictionary(dictionary: ["kind": "live_translate", "language": "zh-Hans"]))
        let trigger = try #require(body["trigger"] as? [String: Any])
        #expect(trigger["kind"] as? String == "on_voice_call")
        #expect(trigger["speaker_scope"] as? String == "anyone")
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

    // MARK: - ADR-0094 A.2: the translation writes

    /// Rows 7–8: the write is the intent alone — `for_language`, or the pocket interpreter — with the revision, in the
    /// catalog's exact codes; no `directions`, `style` or speaker scopes.
    @Test(arguments: [VoiceTranslationParams.forLanguage("zh-Hans"), .pocket("uk", "pt-BR")])
    func anEnablingWriteSendsTheIntentOnly(params: VoiceTranslationParams) async throws {
        let expected: [String: Any] = switch params {
        case .forLanguage(let language): ["kind": "translation", "for_language": language]
        case .pocket(let first, let second): ["kind": "translation", "pocket": [first, second]]
        }
        stub(status: 200, contentType: "application/json", body: Self.setControl)

        _ = try await service.setVoiceTranslation(sessionID: "session-1", params: params, revision: 4).get()

        let body = try requestBody()
        #expect(body["state"] as? String == "enabled")
        #expect(body["revision"] as? Int == 4)
        let sent = try #require(body["params"] as? [String: Any])
        #expect(NSDictionary(dictionary: sent) == NSDictionary(dictionary: expected))
        let request = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID]?.last })
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path() == "/api/v1/voice-sessions/session-1/controls/translation")
    }

    /// The attach carries the same intent under `controls.translation`.
    @Test
    func theAttachCarriesTheIntent() async throws {
        stub(status: 202, contentType: "application/json", body: Self.accepted)

        _ = try await service.attachVoiceAgent(agentID: "agent-1",
                                               roomID: "!room:platform.test",
                                               params: VoiceAttachParams(translation: .forLanguage("uk"), recording: false, summary: false, conversation: false)).get()

        let controls = try #require(try requestBody()["controls"] as? [String: [String: Any]])
        #expect(controls["translation"]?["state"] as? String == "enabled")
        let sent = try #require(controls["translation"]?["params"] as? [String: Any])
        #expect(NSDictionary(dictionary: sent) == NSDictionary(dictionary: ["kind": "translation", "for_language": "uk"]))
    }

    /// Row 12: a 503 is retried once after the contract's delay (`Retry-After: 5`; the backend's export declares no
    /// header, so the service holds the value), and the second answer is the answer.
    @Test
    func aServiceUnavailableEnablingWriteIsRetriedOnceAfterItsDelay() async throws {
        stub([.init(status: 503, contentType: "application/problem+json", body: Self.problem(type: "/errors/service-unavailable", status: 503),
                    headers: ["Retry-After": "5"]),
              .init(status: 200, contentType: "application/json", body: Self.setControl)])

        let started = ContinuousClock.now
        let controls = try await service.setVoiceTranslation(sessionID: "session-1", params: .forLanguage("uk"), revision: 1).get()

        #expect(controls.effective.forLanguage == "uk")
        #expect(RoomToolsURLProtocol.requests.withLock { $0[testID]?.count } == 2)
        #expect(ContinuousClock.now - started >= Self.retryDelay)
    }

    /// Only once: a second 503 is the answer — on the attach too, whose 503 the export leaves undeclared.
    @Test
    func aSecondServiceUnavailableIsTheAnswer() async {
        stub(status: 503, contentType: "application/problem+json", body: Self.problem(type: "/errors/service-unavailable", status: 503),
             headers: ["Retry-After": "5"])

        let result = await service.attachVoiceAgent(agentID: "agent-1",
                                                    roomID: "!room:platform.test",
                                                    params: VoiceAttachParams(translation: .forLanguage("uk"), recording: false, summary: false, conversation: false))

        guard case .failure(.serviceUnavailable(let retryAfter)) = result else {
            Issue.record("Two 503s should fail as service unavailable, got \(result)")
            return
        }
        #expect(retryAfter == Self.retryDelay)
        #expect(RoomToolsURLProtocol.requests.withLock { $0[testID]?.count } == 2)
    }

    /// Row 12: the two typed 422s, with their extension members; another 422 stays a plain rejection.
    @Test
    func theTranslationRefusalsAreTyped() async {
        stub(status: 422, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/translation-paused","title":"x","status":422,"detail":"x","reason":"call_cap","pause_until":null}"#.utf8))
        guard case .failure(.translationPaused(let paused)) = await service.setVoiceTranslation(sessionID: "s", params: .forLanguage("uk"), revision: 1) else {
            Issue.record("A translation-paused 422 should be typed")
            return
        }
        #expect(paused == VoiceTranslationRefusal(reason: .callCap, pauseUntil: nil))

        stub(status: 422, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/translation-paused","title":"x","status":422,"detail":"x","reason":"translation_paused","pause_until":"2026-11-16T00:00:00Z"}"#.utf8))
        guard case .failure(.translationPaused(let until)) = await service.setVoiceTranslation(sessionID: "s", params: .forLanguage("uk"), revision: 1) else {
            Issue.record("A translation-paused 422 should be typed")
            return
        }
        #expect(until == VoiceTranslationRefusal(reason: .translationPaused, pauseUntil: Date(timeIntervalSince1970: 1_794_787_200)))

        stub(status: 422, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/translation-intent-unavailable","title":"x","status":422,"detail":"x","room_kind":"owner_dm"}"#.utf8))
        guard case .failure(.intentUnavailable(let roomKind)) = await service.setVoiceTranslation(sessionID: "s", params: .forLanguage("uk"), revision: 1) else {
            Issue.record("A translation-intent-unavailable 422 should be typed")
            return
        }
        #expect(roomKind == "owner_dm")

        stub(status: 422, contentType: "application/problem+json", body: Self.problem(type: "/errors/validation-failed", status: 422, detail: "bad code"))
        guard case .failure(.rejected("bad code")) = await service.setVoiceTranslation(sessionID: "s", params: .forLanguage("uk"), revision: 1) else {
            Issue.record("Any other 422 stays rejected")
            return
        }
    }

    /// A.3: the owner's read — the intent, the lanes it holds (an unknown input left out), standby, the stop reason
    /// (an unknown one is `ended`) and syncing.
    @Test
    func theControlsReadTheEffectiveIntent() async throws {
        let effective = #"{"source":"room_tool","style":"simultaneous","for_language":"uk","pocket":null,"lanes":[{"speaker":"@john:x","input":"voice","language":"uk"},{"speaker":"@me:x","input":"device","language":"uk"}],"standby":false,"stopped_reason":"from_the_future","syncing":true,"paused":false,"pause_until":null,"paused_reason":null,"category":null}"#
        stub(status: 200, contentType: "application/json", body: Data(Self.controlsBody(effective: effective).utf8))

        let controls = try await service.voiceSessionControls(sessionID: "session-1").get()

        #expect(controls.effective == VoiceControlsEffective(source: "room_tool", style: "simultaneous", forLanguage: "uk", pocket: nil,
                                                             lanes: [.init(speaker: "@john:x", language: "uk")],
                                                             isStandby: false, stoppedReason: .ended, isSyncing: true, pause: nil))
    }


    // MARK: - Question 387: the join check (B4) and the ended session's reason (B1)

    @Test(arguments: [("ok", VoiceJoinCheckReason.ok), ("ask_to_join", .askToJoin), ("ai_consent_room", .aiConsentRoom),
                      ("from_the_future", .unknown("from_the_future"))])
    func theJoinCheckReadsItsReason(wire: String, reason: VoiceJoinCheckReason) async {
        stub(status: 200, contentType: "application/json", body: Data(#"{"reason":"\#(wire)"}"#.utf8))

        guard case .success(let read) = await service.voiceJoinCheck(agentID: "agent-1", roomID: "!room:example.org") else {
            Issue.record("The join check should decode")
            return
        }
        #expect(read == reason)
    }

    /// Question 395: Calls paused by their cap. The check names no date; the agent's usage does.
    @Test
    func theJoinCheckReadsACategoryPause() async {
        stub(status: 200, contentType: "application/json", body: Data(#"{"reason":"category_paused"}"#.utf8))

        guard case .success(let read) = await service.voiceJoinCheck(agentID: "agent-1", roomID: "!room:example.org") else {
            Issue.record("The join check should decode")
            return
        }
        #expect(read == .categoryPaused(nil))
    }

    /// Question 395: the controls say when Call translation is paused while the session goes on; `null` is no date.
    @Test(arguments: [(#""paused":true,"pause_until":"2026-11-16T00:00:00Z","paused_reason":"category_paused","category":"call_translation""#,
                       AILimitPause?.some(.until(Date(timeIntervalSince1970: 1_794_787_200)))),
                      (#""paused":true,"pause_until":null,"paused_reason":"category_paused","category":"call_translation""#, .some(.untilChanged)),
                      (#""paused":false,"pause_until":null,"paused_reason":null,"category":null"#, nil)])
    func theControlsSayWhenTranslationIsPaused(fields: String, pause: AILimitPause?) async {
        let body = Self.controlsBody(effective: #"{"source":"off","style":null,"lanes":[],"standby":false,"syncing":false,\#(fields)}"#)
        stub(status: 200, contentType: "application/json", body: Data(body.utf8))

        guard case .success(let controls) = await service.voiceSessionControls(sessionID: "session-1") else {
            Issue.record("The controls should decode")
            return
        }
        #expect(controls.effective.pause == pause)
        #expect(NativeAgentCenterTranslation(controls).pause == pause)
    }

    /// A check the backend could not make is no verdict.
    @Test
    func aJoinCheckThatCouldNotBeMadeIsUnavailable() async {
        stub(status: 503, contentType: "application/problem+json",
             body: Self.problem(type: "/errors/service-unavailable", status: 503, detail: "could not check"))

        guard case .failure(.unavailable) = await service.voiceJoinCheck(agentID: "agent-1", roomID: "!room:example.org") else {
            Issue.record("A 503 is unavailable, not a reason")
            return
        }
    }

    @Test(arguments: [(#""state":"pending_join""#, VoiceSessionProgress.joining),
                      (#""state":"active""#, .active),
                      (#""state":"ended","end_reason":"ai_consent_room""#, .ended(.aiConsentRoom)),
                      (#""state":"ended","end_reason":"notice_failed""#, .ended(.failed)),
                      (#""state":"ended","end_reason":"budget_reached""#, .ended(.budgetReached))])
    func theSessionSaysWhereItIs(fields: String, progress: VoiceSessionProgress) async {
        let body = #"{"id":"0190a3b2-0000-7000-8000-000000000001","agent_id":"0190a3b2-0000-7000-8000-000000000002","agent_mxid":"@a:example.org","room_id":"!r:example.org","voice_mode":"x","leave_policy":"call_end","was_room_member_before":false,"mode_state":{},"created_at":"2026-11-09T10:00:00Z",\#(fields)}"#
        stub(status: 200, contentType: "application/json", body: Data(body.utf8))

        guard case .success(let read) = await service.voiceSessionProgress(sessionID: "s") else {
            Issue.record("The session should decode")
            return
        }
        #expect(read == progress)
    }

    /// Question 395: a category's cap names the category; a newer one reads as other.
    @Test(arguments: [(#""category":"call_translation""#, AgentUsage.Category.callTranslation),
                      (#""category":"calls""#, .calls),
                      (#""category":"voice_cloning""#, .other),
                      (#""category":null"#, .other)])
    func aCategoryPauseNamesItsCategory(field: String, category: AgentUsage.Category) async {
        let body = #"{"id":"0190a3b2-0000-7000-8000-000000000001","agent_id":"0190a3b2-0000-7000-8000-000000000002","agent_mxid":"@a:example.org","room_id":"!r:example.org","voice_mode":"x","leave_policy":"call_end","was_room_member_before":false,"mode_state":{},"created_at":"2026-11-09T10:00:00Z","state":"ended","end_reason":"category_paused",\#(field)}"#
        stub(status: 200, contentType: "application/json", body: Data(body.utf8))

        guard case .success(let read) = await service.voiceSessionProgress(sessionID: "s") else {
            Issue.record("The session should decode")
            return
        }
        #expect(read == .ended(.categoryPaused(category)))
    }

    /// Every 409 of a write is the revision clash, whatever its prose says (ADR-0094 A.2: no translation conflicts).
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

    /// A.8: the catalog for anyone signed in, no agent and no session.
    @Test
    func theVoiceCatalogIsReadWithoutAnAgent() async throws {
        stub(status: 200, contentType: "application/json", body: Data(#"""
        {"languages":[{"code":"uk","display_name":"Ukrainian"},{"code":"zh-Hans","display_name":"Chinese (Simplified)"}]}
        """#.utf8))

        let catalog = try await service.voiceLanguages().get()

        #expect(catalog == [.init(code: "uk", label: "Ukrainian"), .init(code: "zh-Hans", label: "Chinese (Simplified)")])
        let request = try #require(RoomToolsURLProtocol.requests.withLock { $0[testID]?.last })
        #expect(request.url?.path == "/api/v1/voice/languages")
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

    /// `applies_to_viewer` is a plain string: a value this build doesn't know is `unknown`, and the read still decodes.
    @Test(arguments: [("yes", ToolAppliesToViewer.yes), ("no", .no), ("not_applicable", .notApplicable), ("unknown", .unknown), ("sometimes", .unknown)])
    func aToolSaysWhetherItTouchesTheReader(wire: String, value: ToolAppliesToViewer) async throws {
        let body = #"""
        {"room_id":"!room:platform.test","agents":[
          {"agent_id":"agent-2","matrix_user_id":"@assistant-bob:platform.test","display_name":"Bob's Assistant",
           "owner_user_id":"@bob:platform.test","is_mine":false,
           "tools":[{"id":null,"tool_kind":"summarize","trigger_kind":"on_message","target_language":null,
                     "params":null,"trigger":null,"applies_to_viewer":"\#(wire)"}]}
        ]}
        """#
        stub(status: 200, contentType: "application/json", body: Data(body.utf8))

        let room = try await service.fetchRoomTools(roomID: "!room:platform.test").get()

        #expect(room.agents.first?.tools.first?.appliesToViewer == value)
    }

    /// Question 404: the 409 of a second recording names the assistant that records and its owner, on a switch and on
    /// an add; either may be null, and it is still the covered recording; another 409 stays the plain conflict.
    @Test
    func aCoveredRecordingIsTyped() async {
        let covered = Data(#"{"type":"/errors/recording-covered","title":"Call already recorded","status":409,"detail":"another assistant already records this call","recording_agent":"@assistant-mira:platform.test","recording_owner":"@mira:platform.test"}"#.utf8)
        let expected = VoiceRecordingCover(agentMxid: "@assistant-mira:platform.test", ownerMxid: "@mira:platform.test")

        stub(status: 409, contentType: "application/problem+json", body: covered)
        guard case .failure(.recordingCovered(let cover)) = await service.setVoiceSwitch(sessionID: "s", control: .recording, enabled: true, revision: 1) else {
            Issue.record("A recording-covered 409 on the switch should be typed")
            return
        }
        #expect(cover == expected)

        stub(status: 409, contentType: "application/problem+json", body: covered)
        guard case .failure(.recordingCovered(let attachCover)) = await attach() else {
            Issue.record("A recording-covered 409 on an add should be typed")
            return
        }
        #expect(attachCover == expected)

        stub(status: 409, contentType: "application/problem+json",
             body: Data(#"{"type":"/errors/recording-covered","title":"x","status":409,"detail":"x","recording_agent":null,"recording_owner":null}"#.utf8))
        guard case .failure(.recordingCovered(let anonymous)) = await service.setVoiceSwitch(sessionID: "s", control: .recording, enabled: true, revision: 1) else {
            Issue.record("A recording-covered 409 naming no one should still be typed")
            return
        }
        #expect(anonymous == VoiceRecordingCover(agentMxid: nil, ownerMxid: nil))

        stub(status: 409, contentType: "application/problem+json", body: Self.problem(type: "/errors/conflict", status: 409))
        guard case .failure(.conflict) = await service.setVoiceSwitch(sessionID: "s", control: .recording, enabled: true, revision: 1) else {
            Issue.record("Another 409 should stay the conflict")
            return
        }
    }

    // MARK: - Helpers

    private static let applied = Data(#"{"status":"applied","action_log_id":"log-1"}"#.utf8)

    private static let retryDelay: Duration = .milliseconds(300)

    private static func controlsBody(effective: String) -> String {
        #"{"session_id":"session-1","room_id":"!r:example.org","effective":\#(effective),"overrides":[],"call_artifacts":{"recording_enabled":false,"summary_enabled":true,"recording_stopped":false,"recording_segment_count":0,"recording_segments_pending":0,"recording_segments_delivered":0,"recording_segments_failed":0},"conversation":{"active":false,"available":true,"revision":0}}"#
    }

    private static var setControl: Data {
        Data(#"{"status":"applied","action_log_id":"log-1","controls":\#(controlsBody(effective: #"{"source":"override","style":"simultaneous","for_language":"uk","lanes":[],"standby":true,"syncing":false,"paused":false}"#))}"#.utf8)
    }

    /// An own agent with a full Tool and another owner's agent with a safe slice.
    private static let roomRead = Data(#"""
    {"room_id":"!room:platform.test","agents":[
      {"agent_id":"agent-1","matrix_user_id":"@assistant-alice:platform.test","display_name":"Alice's Assistant",
       "owner_user_id":"@alice:platform.test","is_mine":true,
       "tools":[{"id":"tool-1","tool_kind":"translate","trigger_kind":"on_message","target_language":"fr",
                 "params":{"kind":"translate","target_language":"fr"},
                 "trigger":{"kind":"on_message","sender_scope":"anyone"},"applies_to_viewer":"yes"}]},
      {"agent_id":"agent-2","matrix_user_id":"@assistant-bob:platform.test","display_name":"Bob's Assistant",
       "owner_user_id":"@bob:platform.test","is_mine":false,
       "tools":[{"id":null,"tool_kind":"summarize","trigger_kind":"on_message","target_language":null,
                 "params":null,"trigger":null,"applies_to_viewer":"no"}]}
    ]}
    """#.utf8)

    private static let expectedRoom = RoomToolsView(roomID: "!room:platform.test", agents: [
        RoomToolAgentEntry(agentID: "agent-1", matrixUserID: "@assistant-alice:platform.test", displayName: "Alice's Assistant",
                           ownerUserID: "@alice:platform.test", isMine: true,
                           tools: [RoomToolView(toolID: "tool-1", toolKind: "translate", triggerKind: "on_message", targetLanguage: "fr",
                                                params: .translate(targetLanguage: "fr"), trigger: .onMessage(senderScope: .anyone),
                                                safeSliceSalt: "0.0", appliesToViewer: .yes)]),
        RoomToolAgentEntry(agentID: "agent-2", matrixUserID: "@assistant-bob:platform.test", displayName: "Bob's Assistant",
                           ownerUserID: "@bob:platform.test", isMine: false,
                           tools: [RoomToolView(toolID: nil, toolKind: "summarize", triggerKind: "on_message", targetLanguage: nil,
                                                params: nil, trigger: nil, safeSliceSalt: "1.0", appliesToViewer: .no)])
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

    private func stub(status: Int, contentType: String, body: Data, headers: [String: String] = [:]) {
        stub([.init(status: status, contentType: contentType, body: body, headers: headers)])
    }

    /// Answers in order; the last answers every request after it.
    private func stub(_ stubs: [RoomToolsURLProtocol.Stub]) {
        RoomToolsURLProtocol.stubs.withLock { $0[testID] = stubs }
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
        var headers: [String: String] = [:]
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: [Stub]]>([:])
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
        let stub = Self.stubs.withLock { stubs -> Stub? in
            guard var queue = stubs[testID], !queue.isEmpty else { return nil }
            let first = queue.count > 1 ? queue.removeFirst() : queue[0]
            stubs[testID] = queue
            return first
        } ?? Stub(status: 500, contentType: "application/problem+json", body: Data())

        let headers = stub.headers.merging(["Content-Type": stub.contentType]) { first, _ in first }
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers) else {
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
