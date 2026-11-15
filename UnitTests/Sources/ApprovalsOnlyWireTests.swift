//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (ADR-0087): the approvals-only platform's wire, as the
// backend serialises it, through the generated client and the service's
// mapping — the approval is the one consent record.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct ApprovalsOnlyWireTests {
    private let testID = UUID().uuidString
    private let service: AgentPlatformService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApprovalsWireURLProtocol.self]
        configuration.httpAdditionalHeaders = [ApprovalsWireURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = AgentPlatformService(client: client)
    }

    // MARK: - The hub

    /// `needs_action` has two families now; the copy of the contract that
    /// required `consultations` failed to decode exactly this body.
    @Test
    func theHubDecodesWithApprovalsAndVerificationsOnly() async throws {
        stub(Self.notificationsBody)

        let snapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()

        #expect(snapshot.needsAction.map(\.id) == ["approval-\(Self.approvalID)", "verification-\(Self.verificationID)"])
        guard case .approval(let approval) = snapshot.needsAction.first else {
            Issue.record("The first contact should be an approval in the hub")
            return
        }
        #expect(approval.draftBody == "Hi Bob — Alice is away today; can I take a message?")
        #expect(approval.targetRoomID == "!visitor:spiral.md")
        #expect(snapshot.unseenCount == 2)
        #expect(snapshot.lastSeenAt == nil)
        #expect(lastRequest?.url?.path() == "/api/v1/me/notifications")
    }

    /// An escalated action's activity row names the approval that decides it.
    @Test
    func theActivityRowNamesItsApproval() async throws {
        stub(Self.notificationsBody)

        let snapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()

        #expect(snapshot.activity.map(\.approvalID) == [Self.approvalID, nil])
        #expect(snapshot.activity.first?.policyDecision == .requiresOwnerConsent)
    }

    // MARK: - The approval card

    /// The card a first-contact push opens names the visitor, from the
    /// approval exactly as the platform escalates it.
    @Test
    func aFirstContactApprovalOpensAsAFirstContact() async throws {
        stub(Data(Self.firstContactApprovalJSON.utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .personalAgentFirstContact(visitorMXID: "@bob:spiral.md"))
        #expect(detail.state == .pending)
        #expect(detail.draftBody == "Hi Bob — Alice is away today; can I take a message?")
        #expect(lastRequest?.url?.path() == "/api/v1/approvals/\(Self.approvalID)")
    }

    /// An escalation without a visitor (an escalation rule) keeps the
    /// generic card.
    @Test
    func anApprovalWithoutAVisitorIsGeneric() async throws {
        let ruleMatch = Self.firstContactApprovalJSON
            .replacingOccurrences(of: #""escalation_reason": "personal_agent_first_contact""#, with: #""escalation_reason": "escalation_rule_match""#)
            .replacingOccurrences(of: #", "visitor_mxid": "@bob:spiral.md""#, with: "")
        stub(Data(ruleMatch.utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .generic(senderMXID: nil))
    }

    /// The hub's card says whom an escalation is about: the backend names the
    /// sender of the message it answers under `sender_mxid`. An approval
    /// stored before the field keeps the room label.
    @Test
    func aGenericEscalationInTheHubNamesItsSender() async throws {
        let ruleMatch = Self.firstContactApprovalJSON
            .replacingOccurrences(of: #""escalation_reason": "personal_agent_first_contact""#, with: #""escalation_reason": "escalation_rule_match""#)
            .replacingOccurrences(of: #""visitor_mxid": "@bob:spiral.md""#, with: #""sender_mxid": "@dan:spiral.md""#)
        stub(Data(#"{ "needs_action": { "approvals": [\#(ruleMatch)], "verifications": [] }, "visitor_messages": [], "activity": [], "unseen_count": 1 }"#.utf8))
        
        let snapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()
        guard case .approval(let approval) = snapshot.needsAction.first else {
            Issue.record("The escalation should be an approval in the hub")
            return
        }
        #expect(approval.counterpartMXID == "@dan:spiral.md")
        
        let older = Self.firstContactApprovalJSON
            .replacingOccurrences(of: #""escalation_reason": "personal_agent_first_contact""#, with: #""escalation_reason": "escalation_rule_match""#)
            .replacingOccurrences(of: #", "visitor_mxid": "@bob:spiral.md""#, with: "")
        stub(Data(#"{ "needs_action": { "approvals": [\#(older)], "verifications": [] }, "visitor_messages": [], "activity": [], "unseen_count": 1 }"#.utf8))
        
        let olderSnapshot = try await service.fetchNotifications(activityCursor: nil, limit: 25).get()
        guard case .approval(let olderApproval) = olderSnapshot.needsAction.first else {
            Issue.record("The older escalation should be an approval in the hub")
            return
        }
        #expect(olderApproval.counterpartMXID == nil)
    }
    
    @Test
    func aColdOutreachApprovalNamesItsTarget() async throws {
        // The outreach scheduler's snapshot (`worker/outreach_scheduler.rs`).
        let coldOutreach = Self.firstContactApprovalJSON
            .replacingOccurrences(of: #""context_snapshot": { "user_message": "Hi, is Alice around?", "visitor_mxid": "@bob:spiral.md" }"#,
                                  with: #""context_snapshot": { "kind": "cold_outreach", "target_mxid": "@carol:spiral.md", "outreach_target_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b09", "warnings": ["first_contact"], "draft_preview": "Hi Carol" }"#)
        stub(Data(coldOutreach.utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .coldOutreach(targetMXID: "@carol:spiral.md", warnings: ["first_contact"]))
    }

    // MARK: - A block request (decision 38)

    @Test
    func aBlockRequestOpensAsABlockRequest() async throws {
        stub(Data(Self.blockRequestJSON(status: "pending").utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .blockSender(ApprovalBlockRequest(targetMXID: "@spam:spiral.md",
                                                                    roomID: "!visitor:spiral.md",
                                                                    isDirectMessage: true,
                                                                    reason: "Sends the same advert again and again.",
                                                                    userMessage: "BUY NOW")))
        #expect(detail.escalation == .blockSender)
        #expect(detail.isBlockRequest)
    }

    /// The approval's own `draft_body` and `target_room_id` carry the reason
    /// and the room for a snapshot that lacks them; a group stays a group.
    @Test
    func aBlockRequestFallsBackToTheDraftAndTheTargetRoom() async throws {
        let sparse = Self.blockRequestJSON(status: "pending")
            .replacingOccurrences(of: #""room_id": "!visitor:spiral.md","#, with: "")
            .replacingOccurrences(of: #""room_kind": "direct_message""#, with: #""room_kind": "group_room""#)
            .replacingOccurrences(of: #""reason": "Sends the same advert again and again.","#, with: "")
            .replacingOccurrences(of: #""user_message": "BUY NOW""#, with: #""user_message": "  ""#)
        stub(Data(sparse.utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .blockSender(ApprovalBlockRequest(targetMXID: "@spam:spiral.md",
                                                                    roomID: "!visitor:spiral.md",
                                                                    isDirectMessage: false,
                                                                    reason: "Sends the same advert again and again.",
                                                                    userMessage: nil)))
    }

    /// Without the person to block the card could not say whom; the generic
    /// card shows the agent's reason instead.
    @Test
    func aBlockRequestWithoutItsPersonIsNotABlockCard() async throws {
        let anonymous = Self.blockRequestJSON(status: "pending")
            .replacingOccurrences(of: #""target_mxid": "@spam:spiral.md","#, with: "")
        stub(Data(anonymous.utf8))

        let detail = try await service.fetchApproval(id: Self.approvalID).get()

        #expect(detail.context == .unknown(rawKind: "block_sender"))
        #expect(detail.escalation == .blockSender)
    }

    // MARK: - Deciding a block request (decision 38)

    /// `applied` is the fifth `DeliveryResponse` member, again without a
    /// discriminator; the generated decoder used to throw on it.
    @Test
    func approvingABlockRequestAnswersApplied() async throws {
        stub(Data(#"{ "approval": \#(Self.blockRequestJSON(status: "approved")), "delivery": { "kind": "applied" } }"#.utf8))

        let result = try await service.decideApproval(id: Self.approvalID, decision: .approve).get()

        #expect(result.delivery == .applied)
        #expect(result.approval.state == .approved)
        #expect(lastRequest?.url?.path() == "/api/v1/approvals/\(Self.approvalID)/decide")
    }

    /// The four older members still decode as themselves now that the `oneOf`
    /// has five: the generated decoder tries them in spec order, and none has
    /// a discriminator to tell them apart.
    @Test(arguments: [
        (#"{ "kind": "sent", "event_id": "$final:spiral.md" }"#, ApprovalDecision.approve, "approved", ApprovalDeliveryOutcome.sent(eventID: "$final:spiral.md")),
        (#"{ "kind": "not_sent" }"#, .reject, "rejected", .notSent),
        (#"{ "kind": "send_failed", "reason": "homeserver unreachable" }"#, .approve, "approved", .sendFailed(reason: "homeserver unreachable")),
        (#"{ "kind": "deferred", "deferred_kind": "cold_outreach" }"#, .approve, "approved", .deferred(deferredKind: "cold_outreach"))
    ])
    func everyOlderDeliveryDecodesAsItself(delivery: String, decision: ApprovalDecision, status: String, expected: ApprovalDeliveryOutcome) async throws {
        let approval = Self.firstContactApprovalJSON
            .replacingOccurrences(of: #""state": { "status": "pending" }"#, with: #""state": { "status": "\#(status)" }"#)
        stub(Data(#"{ "approval": \#(approval), "delivery": \#(delivery) }"#.utf8))

        let result = try await service.decideApproval(id: Self.approvalID, decision: decision).get()

        #expect(result.delivery == expected)
        #expect(result.approval.state == (status == "rejected" ? .rejected : .approved))
    }

    /// The block could not be saved: nothing was decided and the request is
    /// still pending, to approve again.
    @Test
    func aBlockThatWasNotSavedIsAServerError() async {
        stub(Self.problem(status: 500, detail: "internal error"), status: 500)

        let result = await service.decideApproval(id: Self.approvalID, decision: .approve)

        guard case .failure(.serverError(status: 500)) = result else {
            Issue.record("Expected a 500, got \(result)")
            return
        }
    }

    /// A block request has no message to edit.
    @Test
    func editingABlockRequestIsRefused() async {
        stub(Self.problem(status: 400, detail: "a block request has no message to edit"), status: 400)

        let result = await service.decideApproval(id: Self.approvalID, decision: .edit(newBody: "Block them"))

        guard case .failure(.validation(let detail)) = result else {
            Issue.record("Expected a 400, got \(result)")
            return
        }
        #expect(detail == "a block request has no message to edit")
    }

    // MARK: - A refused approve (backend audit A16)

    /// An approve or edit of a cold-outreach card to someone the owner
    /// blocked is refused with its own type: the card is closed, nothing was
    /// sent. It used to share `/errors/conflict` with "already decided".
    @Test(arguments: [ApprovalDecision.approve, .edit(newBody: "Hi Carol")])
    func anApproveToABlockedPersonIsTargetBlocked(decision: ApprovalDecision) async {
        stub(Self.problem(type: "/errors/target-blocked", status: 409,
                          detail: "the person this card would message is blocked; the card is closed"),
             status: 409)

        let result = await service.decideApproval(id: Self.approvalID, decision: decision)

        guard case .failure(.targetBlocked) = result else {
            Issue.record("Expected .targetBlocked, got \(result)")
            return
        }
    }

    /// Every other 409 on decide still means the approval was decided already.
    @Test
    func anAlreadyDecidedApprovalIsAConflict() async {
        stub(Self.problem(type: "/errors/conflict", status: 409, detail: "approval has already been decided"), status: 409)

        let result = await service.decideApproval(id: Self.approvalID, decision: .approve)

        guard case .failure(.conflict(let detail)) = result else {
            Issue.record("Expected .conflict, got \(result)")
            return
        }
        #expect(detail == "approval has already been decided")
    }

    // MARK: - A missing approval

    /// The platform says an approval is gone with its own type: its person
    /// was erased, so the card was deleted and nothing was sent.
    @Test
    func aDecideOfAMissingApprovalIsApprovalNotFound() async {
        stub(Self.problem(type: "/errors/approval-not-found", status: 404, detail: "approval not found"), status: 404)

        let result = await service.decideApproval(id: Self.approvalID, decision: .approve)

        guard case .failure(.approvalNotFound) = result else {
            Issue.record("Expected .approvalNotFound, got \(result)")
            return
        }
    }

    @Test
    func aFetchOfAMissingApprovalIsApprovalNotFound() async {
        stub(Self.problem(type: "/errors/approval-not-found", status: 404, detail: "approval not found"), status: 404)

        let result = await service.fetchApproval(id: Self.approvalID)

        guard case .failure(.approvalNotFound) = result else {
            Issue.record("Expected .approvalNotFound, got \(result)")
            return
        }
    }

    /// A bare `/errors/not-found` is also what a route the platform does not
    /// serve answers; it says nothing about the approval.
    @Test
    func aBareNotFoundIsNotAMissingApproval() async {
        stub(Self.problem(type: "/errors/not-found", status: 404, detail: "no such route"), status: 404)

        let decided = await service.decideApproval(id: Self.approvalID, decision: .approve)
        let fetched = await service.fetchApproval(id: Self.approvalID)

        guard case .failure(.notFound) = decided, case .failure(.notFound) = fetched else {
            Issue.record("Expected .notFound twice, got \(decided) and \(fetched)")
            return
        }
    }

    // MARK: - Fixtures

    static let approvalID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b6a"
    static let verificationID = "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b70"

    /// A personal agent's first contact as the platform escalates it
    /// (`worker/reply/consent.rs`): `escalation_reason` names it, the
    /// snapshot carries the visitor under `visitor_mxid`.
    static let firstContactApprovalJSON = #"""
    {
      "id": "\#(approvalID)",
      "tenant_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b01",
      "agent_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
      "config_version_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b03",
      "owner_user_id": "@alice:spiral.md",
      "draft_body": "Hi Bob — Alice is away today; can I take a message?",
      "target_room_id": "!visitor:spiral.md",
      "triggering_event_id": "$first:spiral.md",
      "state": { "status": "pending" },
      "escalation_reason": "personal_agent_first_contact",
      "context_snapshot": { "user_message": "Hi, is Alice around?", "visitor_mxid": "@bob:spiral.md" },
      "expires_at": "2026-10-11T09:00:00.123456Z",
      "created_at": "2026-10-10T09:00:00.123456Z",
      "updated_at": "2026-10-10T09:00:00.123456Z"
    }
    """#

    /// A block request as the platform opens it (`domain/services/block_request.rs`):
    /// the agent's reason is also the draft, the room is where the contact wrote.
    static func blockRequestJSON(status: String) -> String {
        #"""
        {
          "id": "\#(approvalID)",
          "tenant_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b01",
          "agent_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
          "config_version_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b03",
          "owner_user_id": "@alice:spiral.md",
          "draft_body": "Sends the same advert again and again.",
          "target_room_id": "!visitor:spiral.md",
          "triggering_event_id": "$spam:spiral.md",
          "state": { "status": "\#(status)" },
          "escalation_reason": "block_sender",
          "context_snapshot": {
            "kind": "block_sender",
            "target_mxid": "@spam:spiral.md",
            "room_id": "!visitor:spiral.md",
            "room_kind": "direct_message",
            "reason": "Sends the same advert again and again.",
            "user_message": "BUY NOW"
          },
          "expires_at": "2026-10-12T09:00:00Z",
          "created_at": "2026-10-11T09:00:00Z",
          "updated_at": "2026-10-11T09:00:00Z"
        }
        """#
    }

    static func problem(status: Int, detail: String) -> Data {
        problem(type: status == 400 ? "/errors/validation-failed" : "/errors/internal", status: status, detail: detail)
    }

    static func problem(type: String, status: Int, detail: String) -> Data {
        Data(#"{ "type": "\#(type)", "title": "Problem", "status": \#(status), "detail": "\#(detail)" }"#.utf8)
    }

    static let notificationsBody = Data(#"""
    {
      "needs_action": {
        "approvals": [\#(firstContactApprovalJSON)],
        "verifications": [{
          "id": "\#(verificationID)",
          "agent_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
          "owner_user_id": "@alice:spiral.md",
          "requester_user_id": "@alice:spiral.md",
          "requester_device_id": "IPHONE15",
          "flow_id": { "kind": "to_device", "transaction_id": "txn-1" },
          "state": "pending_owner",
          "created_at": "2026-10-10T08:00:00Z",
          "deadline_at": "2026-10-10T08:10:00Z"
        }]
      },
      "activity": [{
        "id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b20",
        "agent_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
        "room_id": "!visitor:spiral.md",
        "capability_name": "messenger.reply_in_room",
        "input_redacted": { "body": { "sha256": "ab12", "len": 51 } },
        "reasoning_summary": "First contact from an unknown visitor.",
        "policy_decision": "requires_owner_consent",
        "policy_reason": "first_contact_with_unknown_visitor",
        "approval_id": "\#(approvalID)",
        "outcome": "executed",
        "outcome_event_id": "$reply:spiral.md",
        "created_at": "2026-10-10T09:00:00.100000Z",
        "resolved_at": "2026-10-10T09:05:00Z",
        "step_index": 0
      }, {
        "id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b21",
        "agent_id": "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
        "capability_name": "messenger.reply_in_room",
        "input_redacted": {},
        "reasoning_summary": "Replied directly.",
        "policy_decision": "allowed_direct",
        "policy_reason": "relationship_approved",
        "outcome": "executed",
        "created_at": "2026-10-10T07:00:00Z",
        "step_index": 0
      }],
      "last_seen_at": null,
      "visitor_messages": [],
      "unseen_count": 2
    }
    """#.utf8)

    // MARK: - Helpers

    private func stub(_ body: Data, status: Int = 200) {
        ApprovalsWireURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }

    private var lastRequest: URLRequest? {
        ApprovalsWireURLProtocol.requests.withLock { $0[testID]?.last }
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries.
private nonisolated class ApprovalsWireURLProtocol: URLProtocol {
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
