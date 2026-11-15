//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 148): the assistant's own rules. G06 — the AI
// toggle outside a call and decision 150's notice to a person who has not
// allowed AI; G17 — decision 153, the personal assistant has no Archive.
// No model is called: a message from a person without consent never
// reaches one, and the agent screens are reads.
//

import XCTest

final class E2AssistantTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    private var peer: DevE2EFixture.Person {
        fixture.peer
    }

    // MARK: G06 (decision 150)

    /// The owner turns Third-party AI off in Settings › Privacy and becomes a
    /// person without consent. Writing to their own assistant gets nothing
    /// (the owner is never sent the notice); writing twice to the peer's
    /// assistant gets one `ai_consent_needed` card and no reply. Its action
    /// opens the toggle; once AI is on, the card reads "You allowed AI" when
    /// it shows again, and the notice's claim is gone.
    func testG06ConsentNoticeForAVisitorWithoutAI() async throws {
        try await ensureSignedIn(owner)
        let ownAssistant = try await ownerAssistant()
        // The peer's assistant acts only while its own person allows AI.
        try await helper.peer("consent", peer.localpart, "grant")
        let peerAssistantLine = try await helper.peer("assistant", peer.localpart, "90")
        let peerAssistant = try XCTUnwrap(peerAssistantLine.first?["mxid"] as? String, "the peer's assistant")
        let token = "g06-\(fixture.runID)"

        try openRoom(named: "\(owner.displayName) · assistant") // accepts the invite when it is still one
        let ownDMLine = try await helper.peer("dm", owner.localpart, ownAssistant.mxid)
        let ownDM = try XCTUnwrap(ownDMLine.first?["room_id"] as? String, "the owner's DM with the assistant")
        try returnToChats()

        try await setAIConsentInSettings(false)
        do {
            try await withoutConsent(ownAssistant: ownAssistant, ownDM: ownDM, peerAssistant: peerAssistant, token: token)
        } catch {
            // Every later scenario needs the owner's consent back.
            _ = try? await helper.peer("consent", owner.localpart, "grant")
            throw error
        }
    }

    private func withoutConsent(ownAssistant: DevE2EAssistant, ownDM: String, peerAssistant: String, token: String) async throws {
        // The owner writes to their own assistant: no notice, no reply.
        try openRoom(named: "\(owner.displayName) · assistant")
        try send("Are you there? own \(token)")
        try require(timelineText(containing: "own \(token)"), timeout: 20, "the message in the owner's DM")
        try returnToChats()

        // The owner, as a visitor, writes twice to the peer's assistant.
        let visit = try await helper.peer("dm", owner.localpart, peerAssistant, "--wait-joined")
        let visitRoom = try XCTUnwrap(visit.first?["room_id"] as? String)
        let notice = element(A11yIdentifiers.roomScreen.spiralNotice("ai_consent_needed"))
        try openRoom(named: "\(peer.displayName) · assistant")
        try send("Hello there, first \(token)")
        try require(notice, timeout: 60, "the AI consent notice")
        try send("Hello again, second \(token)")
        _ = try await helper.peer("wait", owner.localpart, visitRoom, "second \(token)", "30", owner.mxid)
        // Once: the second message must not add a card (a short window, the
        // notice's claim is per agent and room).
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            let count = try await notices("ai_consent_needed", in: visitRoom, by: peerAssistant, as: owner)
            XCTAssertEqual(count, 1, "one notice per room, however often the person writes")
            try await Task.sleep(for: .seconds(1))
        }
        let replied = try await postedText(in: visitRoom, by: peerAssistant, as: owner)
        XCTAssertFalse(replied, "no reply to a person without consent")
        let claimed = try await helper.check("consent_notices", ["agent": peerAssistant, "room": visitRoom]).first?["notices"]
        XCTAssertEqual(claimed, "1", "the notice's claim for this agent and room")
        XCTAssertTrue(notice.label.contains("Open Settings"), "the card offers the way to the toggle")

        // The owner is never told: no claim for their own DM, nothing from the
        // assistant after their message (the DM may be encrypted: senders
        // only), and no card there in the app.
        let ownClaim = try await helper.check("consent_notices", ["agent": ownAssistant.mxid, "room": ownDM]).first?["notices"]
        XCTAssertEqual(ownClaim, "0", "no consent notice is claimed for the owner's own DM")
        let ownRoom = try await messages(in: ownDM, as: owner)
        let ownMessage = try XCTUnwrap(ownRoom.lastIndex { $0["sender"] as? String == owner.mxid },
                                       "the owner's message in their DM, as the API reads it")
        let answeredOwner = ownRoom[ownMessage...].contains { $0["sender"] as? String == ownAssistant.mxid }
        XCTAssertFalse(answeredOwner, "the assistant does not answer, or notify, its owner without consent")

        // The card's action opens the toggle; AI on.
        notice.tap()
        try await flipAIConsentToggle(to: true)
        try returnToRoom()

        // When the card shows again it says AI is allowed, and offers nothing.
        try await launchApp()
        try openRoom(named: "\(owner.displayName) · assistant")
        XCTAssertFalse(notice.exists, "no consent card in the owner's own DM")
        try returnToChats()
        try openRoom(named: "\(peer.displayName) · assistant")
        try require(notice, timeout: 30, "the AI consent notice again")
        let allowed = try await eventually("the notice reading that AI is allowed", timeout: 20) {
            notice.label.contains("You allowed AI") ? notice.label : nil
        }
        XCTAssertFalse(allowed.contains("Open Settings"), "an allowed reader is not asked again")
        let cleared = try await helper.check("consent_notices", ["agent": peerAssistant, "room": visitRoom]).first?["notices"]
        XCTAssertEqual(cleared, "0", "the grant clears the person's notice claims")
    }

    // MARK: G17 (decision 153)

    /// The personal assistant's screen has no '···' menu (so no Archive). Companies, whose agents had one, are
    /// hidden in 1.0.2 (question 396): the tab has no «+» to make them.
    func testG17PersonalAssistantHasNoArchive() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()

        try tap(app.tabBars.buttons["Agents"].firstMatch, "the Agents tab")
        try tap(element(A11yIdentifiers.agentSpacesScreen.agent(assistant.mxid)), timeout: 30, "the assistant's row")
        try require(element(A11yIdentifiers.agentDetailScreen.usage), timeout: 30, "the assistant's screen")
        XCTAssertFalse(element(A11yIdentifiers.agentDetailScreen.archive).exists, "the personal assistant has no Archive (decision 153)")

        try tap(app.navigationBars.buttons.element(boundBy: 0), "back to the list")
        XCTAssertFalse(element(A11yIdentifiers.agentSpacesScreen.addMenu).exists, "no «+»: companies are hidden (396)")
        record("personal assistant \(assistant.mxid): no Archive; Agents tab: no «+»")
    }

    // MARK: - Helpers

    /// Settings › Privacy › Third-party AI to `granted`, and the
    /// backend's latest decision with it; Settings closed again.
    private func setAIConsentInSettings(_ granted: Bool) async throws {
        try openSettings()
        try scrollAndTap(element(A11yIdentifiers.settingsScreen.privacy), "Settings › Privacy")
        try await flipAIConsentToggle(to: granted)
        try tap(app.navigationBars.buttons.element(boundBy: 0), "back to Settings")
        try closeSettings()
    }

    /// On Privacy: the toggle to `granted`, then the backend's
    /// latest `ai_consent_decisions` row says the same.
    private func flipAIConsentToggle(to granted: Bool) async throws {
        let id = A11yIdentifiers.advancedSettingsScreen.aiConsent
        let toggle = app.switches[id].exists ? app.switches[id].firstMatch : element(id)
        try require(toggle, timeout: 30, "the Third-party AI toggle (shown once the consent is read)")
        if toggle.value as? String != (granted ? "1" : "0") {
            // The row's frame is the whole row; only the switch at its trailing
            // edge flips it (a tap on the middle lands on the text).
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let expected = granted ? "t" : "f"
        let row = try await eventually("the consent decision granted=\(expected)") {
            try await helper.check("ai_consent", ["mxid": fixture.owner.mxid]).first { $0["granted"] == expected }
        }
        record("ai_consent_decisions: granted=\(row["granted"] ?? "?") version=\(row["version"] ?? "?")")
    }

    private func returnToChats() throws {
        for _ in 0..<4 where !(homeAvatar.exists && homeAvatar.isHittable) {
            if let back = app.navigationBars.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                back.tap()
            }
            settle(0.7)
        }
        try require(homeAvatar, timeout: 10, "the Chats list")
    }
}
