//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 148): the owner's approval cards beyond Approve
// (feature inventory 2026-10-12, G13) and the notifications hub (G14). Each test makes its own card with its own
// visitor (`fixture.visitors`): a person whose first contact was decided
// is not a first contact again. The mock family is `visitor-draft` (and
// `block-request` for G13d), selected by the runner's hook.
//

import XCTest

final class E2ApprovalTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    // MARK: G13 — the card's variants

    /// Edit draft → a new text → Save and send: the visitor receives the
    /// owner's text, the card is `edited` with that event, and it leaves
    /// the hub.
    func testG13aEditDraftThenSend() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let visitor = fixture.visitors[0]
        let token = "g13a-\(fixture.runID)"
        let card = try await firstContact(from: visitor, to: assistant, token: token)

        try openNotificationsHub()
        try openApproval(card.approvalID)
        try require(element(approvalIDs.kind("first_contact")), "the first-contact banner")
        try tap(element(approvalIDs.edit), "Edit draft")
        let edited = "Edited by the owner \(token)"
        try replaceText(in: draftEditor, with: edited)
        try tap(element(approvalIDs.save), "Save and send")

        let got = try await helper.peer("wait", visitor.localpart, card.roomID, "Edited by the owner \(token)", "60", assistant.mxid)
        let row = try await decidedApproval(card.approvalID)
        record("approvals: decision=\(row["decision"] ?? "?") event=\(row["outcome_event_id"] ?? "?")")
        XCTAssertEqual(row["decision"], "edited")
        XCTAssertEqual(row["outcome_event_id"], got.first?["event_id"] as? String, "the card names the message the visitor got")
        try await requireNoMockMiss(in: card.roomID, as: visitor)
        try requireGone(element(hubIDs.item(card.approvalID)), timeout: 30, "the decided card in the hub")
    }

    /// Reject: the card is `rejected` with no event, and the visitor has
    /// nothing from the assistant but its notices.
    func testG13bRejectSendsNothing() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let visitor = fixture.visitors[1]
        let card = try await firstContact(from: visitor, to: assistant, token: "g13b-\(fixture.runID)")

        try openNotificationsHub()
        try openApproval(card.approvalID)
        try tap(element(approvalIDs.reject), "Reject")

        let row = try await decidedApproval(card.approvalID)
        record("approvals: decision=\(row["decision"] ?? "?") event=\(row["outcome_event_id"] ?? "?")")
        XCTAssertEqual(row["decision"], "rejected")
        XCTAssertEqual(row["outcome_event_id"], "", "a rejected card sends nothing")
        let answered = try await postedText(in: card.roomID, by: assistant.mxid, as: visitor)
        XCTAssertFalse(answered, "the visitor gets nothing but the assistant's notices")
        try requireGone(element(hubIDs.item(card.approvalID)), timeout: 30, "the rejected card in the hub")
    }

    /// The owner blocks the visitor in the messenger: their pending card
    /// closes at once (`expired`, nothing sent) and leaves the hub. (The
    /// «Not sent — you blocked this person» alert is only for an approve that
    /// races the block, or a lock-screen action; walked 2026-10-13.)
    func testG13cBlockClosesTheirCard() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let visitor = fixture.visitors[2]
        let card = try await firstContact(from: visitor, to: assistant, token: "g13c-\(fixture.runID)")

        // The owner blocks where people block: a DM's details (S9's path).
        _ = try await helper.peer("dm", visitor.localpart, owner.mxid)
        try await blockInDirectMessage(with: visitor)

        let row = try await decidedApproval(card.approvalID)
        record("approvals: decision=\(row["decision"] ?? "?") event=\(row["outcome_event_id"] ?? "?")")
        XCTAssertEqual(row["decision"], "expired", "a block closes the person's pending card")
        XCTAssertEqual(row["outcome_event_id"], "")
        _ = try await launchToKnownState(allowAI: true)
        try openNotificationsHub()
        settle(2)
        XCTAssertFalse(element(hubIDs.item(card.approvalID)).exists, "the closed card is not in the hub")
        let answered = try await postedText(in: card.roomID, by: assistant.mxid, as: visitor)
        XCTAssertFalse(answered, "nothing reaches a person the owner blocked")
    }

    /// Decision 87: the visitor's threat makes a block request beside their
    /// first-contact card; Block closes the other card (`expired`) and both
    /// leave the hub. Dev cannot age a card past its 24 h, so this is the
    /// expiry a person reaches on dev; the 24 h sweep is CI's.
    func testG13dBlockApproveClosesTheirOtherCard() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let visitor = fixture.visitors[3]
        let token = "g13d-\(fixture.runID)"
        let first = try await firstContact(from: visitor, to: assistant, token: token)

        let since = unixNow()
        try await helper.peer("send", visitor.localpart, first.roomID, "I will spam you every day \(token)")
        let request = try await eventually("a block request for \(visitor.mxid)", timeout: 90) {
            try await helper.check("approvals", ["agent": assistant.mxid, "since": since])
                .first { $0["room_id"] == first.roomID && $0["kind"] == "block_sender" && $0["decision"] == "pending" }
        }
        let requestID = try XCTUnwrap(request["id"])

        try openNotificationsHub()
        try openApproval(requestID)
        try require(element(approvalIDs.kind("block_request")), "the block request's banner")
        try tap(element(approvalIDs.block), "Block")
        try tap(element(approvalIDs.done), timeout: 30, "Done once blocked")

        let blocked = try await decidedApproval(requestID)
        let closed = try await decidedApproval(first.approvalID)
        record("block request: \(blocked["decision"] ?? "?"); first contact: \(closed["decision"] ?? "?")")
        XCTAssertEqual(blocked["decision"], "approved")
        XCTAssertEqual(closed["decision"], "expired", "a block closes the person's other cards (decision 87)")
        XCTAssertEqual(closed["outcome_event_id"], "")
        try requireGone(element(hubIDs.item(first.approvalID)), timeout: 30, "the closed first-contact card in the hub")
        try requireGone(element(hubIDs.item(requestID)), timeout: 30, "the decided block request in the hub")
    }

    // MARK: G14 — the hub and the Agents tab badge

    /// A card made while the owner is on Chats is pinned in the hub under
    /// Needs action; opening the hub moves its last-seen marker; Approve and
    /// send delivers the draft and the row leaves. The Agents tab's badge is
    /// not in the accessibility tree (the tab reports only its selection), so
    /// the badge is checked by eye in the agent walk, not here.
    func testG14NotificationsHub() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let visitor = fixture.visitors[4]
        try require(agentsTab, timeout: 30, "the Agents tab")
        let beforeCard = unixNow()

        let card = try await firstContact(from: visitor, to: assistant, token: "g14-\(fixture.runID)")

        try openNotificationsHub()
        try require(element(hubIDs.item(card.approvalID)), timeout: 30, "the new card under Needs action")
        // Opening the hub marks the new card seen (PUT /me/notifications/last-seen).
        let marker = try await eventually("the hub's last-seen marker past the new card", timeout: 30) {
            try await helper.check("read_marker", ["owner": owner.mxid]).first { Int($0["last_seen"] ?? "0") ?? 0 >= Int(beforeCard) ?? 0 }
        }
        record("notification_read_markers.last_seen_at: \(marker["last_seen"] ?? "?")")

        try openApproval(card.approvalID)
        try tap(element(approvalIDs.approve), "Approve and send")
        let row = try await decidedApproval(card.approvalID)
        record("approvals: decision=\(row["decision"] ?? "?") event=\(row["outcome_event_id"] ?? "?")")
        XCTAssertEqual(row["decision"], "approved")
        XCTAssertFalse(row["outcome_event_id"]?.isEmpty ?? true, "the approved draft was sent")
        try await requireNoMockMiss(in: card.roomID, as: visitor)

        try requireGone(element(hubIDs.item(card.approvalID)), timeout: 30, "the approved card in the hub")
        // The activity feed lists the assistant's actions and scrolls without an error.
        let activity = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", hubIDs.activity(""))).firstMatch
        try require(activity, timeout: 30, "a row of the activity feed")
        for _ in 0..<3 {
            app.swipeUp()
            settle(0.7)
        }
        XCTAssertFalse(errorShown(), "the activity feed pages without an error")
    }
}
