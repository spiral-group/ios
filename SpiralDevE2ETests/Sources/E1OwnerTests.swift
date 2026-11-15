//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 146): the owner's scenarios of the pre-release
// walk (docs/project/PRERELEASE_WALK.md), one test per scenario. The owner
// is a dev password account the runner made; the second person is the peer,
// driven through the helper. Each test signs the owner in itself when it is
// not, so any one of them runs alone (`run-dev-e2e.sh --only S04`).
//

import XCTest

final class E1OwnerTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    private var peer: DevE2EFixture.Person {
        fixture.peer
    }

    private var now: String {
        String(Int(Date().timeIntervalSince1970) - 2)
    }

    /// The owner's DM with their assistant, by the name the backend gives it
    /// (`AssistantLocale::display_name`, English for a password account).
    private var ownerAssistantRoomName: String {
        "\(owner.displayName) · assistant"
    }

    // MARK: S2 + S3

    /// Password sign-in on the dev MAS, the onboarding prompts with Allow,
    /// the consent row at the current version, the assistant's invite.
    func testS02S03SignInOnboardingConsent() async throws {
        try await ensureSignedOut()
        try await signInWithPassword(owner)
        try completeOnboarding(allowAI: true)

        XCTAssertEqual(try currentAccount(), owner.mxid)

        let assistant = try await ownerAssistant()
        let room = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                                                                        A11yIdentifiers.homeScreen.roomNamePrefix + ":", ownerAssistantRoomName)).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 60), "the assistant's invite is on the Chats list")

        let status = try await helper.peer("consent", owner.localpart, "status").first ?? [:]
        let currentVersion = try XCTUnwrap(status["current_version"] as? String, "GET /me/ai-consent names the current version")
        let decision = try await eventually("an ai_consent_decisions row for the owner") {
            try await helper.check("ai_consent", ["mxid": owner.mxid]).first
        }
        record("ai_consent_decisions: granted=\(decision["granted"] ?? "?") version=\(decision["version"] ?? "?"); current \(currentVersion); assistant \(assistant.mxid)")
        XCTAssertEqual(decision["granted"], "t", "Allow stores a granted decision")
        XCTAssertEqual(decision["version"], currentVersion, "the decision is for the current disclosure")
    }

    // MARK: S4

    /// Accept the assistant's invite, the welcome notice, a message (in
    /// Ukrainian), the reply on screen and its audit row.
    func testS04AssistantChat() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        try openRoom(named: ownerAssistantRoomName)
        try require(element(A11yIdentifiers.roomScreen.spiralNotice("welcome")), timeout: 60, "the assistant's welcome notice")

        let since = now
        let before = Set(app.staticTexts.allElementsBoundByIndex.map(\.label))
        let token = "e2e-\(fixture.runID)"
        try send("Привіт! Це перевірка \(token). Відповідай коротко.")
        try require(timelineText(containing: token), timeout: 20, "the sent message in the timeline")

        let reply = try await eventually("an executed reply from the assistant", timeout: 120) {
            try await helper.check("agent_actions", ["agent": assistant.mxid, "since": since])
                .first { $0["capability_name"] == "messenger.reply_in_room" && $0["outcome"] == "executed" }
        }
        record("agent_action_log: \(reply["capability_name"] ?? "") \(reply["policy_decision"] ?? "") \(reply["outcome"] ?? "") event=\(reply["outcome_event_id"] ?? "")")
        XCTAssertEqual(reply["policy_decision"], "allowed_direct")
        XCTAssertFalse(reply["outcome_event_id"]?.isEmpty ?? true, "the reply names its event")

        let replyOnScreen = try await eventually("the assistant's reply on screen", timeout: 30) {
            app.staticTexts.allElementsBoundByIndex.first { $0.label.count > 12 && !$0.label.contains(token) && !before.contains($0.label) }
        }
        XCTAssertTrue(replyOnScreen.exists)
        try requireNoMockMiss(replyOnScreen.label, "the assistant's reply")
    }

    // MARK: S5

    /// A first contact to the owner's assistant: the peer is told the owner
    /// was asked, and an approval with a draft waits for the owner.
    func testS05FirstContactDraft() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        try await grantAIConsent()
        let since = now
        let dm = try await helper.peer("dm", peer.localpart, assistant.mxid, "--wait-joined")
        let roomID = try XCTUnwrap(dm.first?["room_id"] as? String)
        try await helper.peer("send", peer.localpart, roomID, "Hello, this is \(peer.displayName). Can we meet on Friday?")
        let answer = try await helper.peer("wait", peer.localpart, roomID, ".", "120", assistant.mxid)
        record("peer got: \(answer.first?["body"] as? String ?? "?")")
        try requireNoMockMiss(answer.first?["body"] as? String, "the assistant's answer to the peer")
        let approval = try await eventually("a pending approval with a draft", timeout: 60) {
            try await helper.check("approvals", ["agent": assistant.mxid, "since": since]).first
        }
        record("approvals: decision=\(approval["decision"] ?? "?") kind=\(approval["kind"] ?? "?") draft=\(approval["has_draft"] ?? "?")")
        XCTAssertEqual(approval["decision"], "pending")
        XCTAssertEqual(approval["has_draft"], "t")
        XCTAssertEqual(approval["mock_miss"], "f", "the card's draft is a scripted answer, not the AI mock's miss")
    }

    // MARK: S6

    /// The peer opens a DM with the owner; the owner accepts it, reads the
    /// message and replies; the peer receives the reply.
    func testS06PeerDirectMessage() async throws {
        try await ensureSignedIn(owner)
        let roomID = try await peerDM()
        let token = "s06-\(fixture.runID)"
        try await helper.peer("send", peer.localpart, roomID, "Hi owner, peer here \(token)")
        try openRoom(named: peer.displayName)
        try require(timelineText(containing: token), timeout: 30, "the peer's message in the room")

        try send("Відповідь власника \(token) ok")
        let got = try await helper.peer("wait", peer.localpart, roomID, "Відповідь власника \(token)", "30", owner.mxid)
        record("peer read: \(got.first?["event_id"] as? String ?? "?")")
        XCTAssertFalse(got.isEmpty)
    }

    // MARK: S8

    /// Report content on the peer's message: the reason reaches Synapse's
    /// event_reports for this event, reported by the owner.
    func testS08ReportContent() async throws {
        try await ensureSignedIn(owner)
        let roomID = try await peerDM()
        let token = "s08-\(fixture.runID)"
        let sent = try await helper.peer("send", peer.localpart, roomID, "Please report me \(token)")
        let eventID = try XCTUnwrap(sent.first?["event_id"] as? String)
        try openRoom(named: peer.displayName)

        let message = timelineText(containing: token)
        try require(message, timeout: 30, "the message to report")
        message.press(forDuration: 1.2)
        try tap(element(A11yIdentifiers.roomScreen.timelineItemActionMenuAction.reportContent), "the menu's Report content")
        let reason = "e2e report \(token)"
        let field = app.textViews[A11yIdentifiers.reportContent.reason].firstMatch.exists
            ? app.textViews[A11yIdentifiers.reportContent.reason].firstMatch
            : element(A11yIdentifiers.reportContent.reason)
        try tap(field, "the report's reason")
        settle(1)
        field.typeText(reason)
        try tap(element(A11yIdentifiers.reportContent.send), "the report's Send")
        try requireGone(element(A11yIdentifiers.reportContent.send), "the report screen")

        let row = try await eventually("an event_reports row for the message") {
            try await helper.check("event_reports", ["reporter": owner.mxid, "reason": reason]).first
        }
        record("synapse.event_reports: room=\(row["room_id"] ?? "") event=\(row["event_id"] ?? "")")
        XCTAssertEqual(row["event_id"], eventID)
        XCTAssertEqual(row["room_id"], roomID)
    }

    // MARK: S9

    /// The owner blocks the peer in the messenger: owner_blocked_at is set
    /// for the assistant's contact, the peer's message to the assistant is
    /// ignored as a blocked visitor, Unblock clears the block.
    func testS09OwnerBlockAndUnblock() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        try await grantAIConsent()
        let assistantDM = try await helper.peer("dm", peer.localpart, assistant.mxid, "--wait-joined")
        let toAssistant = try XCTUnwrap(assistantDM.first?["room_id"] as? String)
        _ = try await peerDM()
        try openRoom(named: peer.displayName)

        try tap(element(A11yIdentifiers.roomScreen.name), "the room's name")
        try scrollAndTap(element(A11yIdentifiers.roomDetailsScreen.blockUser), "Room details › Block user")
        let alert = app.alerts.firstMatch
        try require(alert, "the block alert")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'agents will ignore them too'")).firstMatch.exists,
                      "the alert says the owner's agents ignore the person too (decision 98)")
        try tap(alert.buttons["Block"].firstMatch, "the alert's Block")

        let blocked = try await eventually("owner_blocked_at set for the peer") {
            try await helper.check("owner_block", ["owner": owner.mxid, "contact": peer.mxid]).first { $0["owner_blocked"] == "t" }
        }
        record("agent_contact_relationships: trust=\(blocked["trust_level"] ?? "?") owner_blocked=\(blocked["owner_blocked"] ?? "?")")
        // A stale row is a defect of its own; the rest of the scenario still runs.
        continueAfterFailure = true
        XCTAssertTrue(element(A11yIdentifiers.roomDetailsScreen.unblockUser).waitForExistence(timeout: 30),
                      "the DM's details offer Unblock once the person is blocked")
        continueAfterFailure = false

        let since = now
        let sent = try await helper.peer("send", peer.localpart, toAssistant, "Are you there? s09-\(fixture.runID)")
        let ignored = try await eventually("the assistant ignoring the blocked peer", timeout: 60) {
            try await helper.check("agent_actions", ["agent": assistant.mxid, "since": since]).first { $0["policy_reason"] == "blocked_visitor" }
        }
        record("agent_action_log: \(ignored["capability_name"] ?? "") \(ignored["policy_decision"] ?? "") \(ignored["policy_reason"] ?? "")")
        let sentAt = (sent.first?["event_id"] as? String) ?? ""
        try await Task.sleep(for: .seconds(8))
        let after = try await helper.peer("read", peer.localpart, toAssistant, "10")
        let lastPeer = after.lastIndex { $0["event_id"] as? String == sentAt } ?? -1
        let answered = after.enumerated().contains { $0.offset > lastPeer && $0.element["sender"] as? String == assistant.mxid }
        XCTAssertFalse(answered, "the assistant must not answer a person its owner blocked")

        // Unblock from Settings › Privacy › Blocked users.
        try await launchApp()
        try openSettings()
        try scrollAndTap(element(A11yIdentifiers.settingsScreen.privacy), "Settings › Privacy")
        try scrollAndTap(element(A11yIdentifiers.advancedSettingsScreen.blockedUsers), "Settings › Privacy › Blocked users")
        try require(element(A11yIdentifiers.blockedUsersScreen.user(peer.mxid)), "the peer in Blocked users")
        // The relaunch sent the ignore list to the platform again: it must still name the peer.
        let relaunched = try await helper.check("owner_block", ["owner": owner.mxid, "contact": peer.mxid]).first
        XCTAssertEqual(relaunched?["owner_blocked"], "t", "a relaunch keeps the owner's block on the platform")
        try tap(element(A11yIdentifiers.blockedUsersScreen.user(peer.mxid)), "the peer in Blocked users")
        try tap(app.alerts.buttons["Unblock"].firstMatch, "the alert's Unblock")
        let cleared = try await eventually("owner_blocked_at cleared") {
            try await helper.check("owner_block", ["owner": owner.mxid, "contact": peer.mxid]).first { $0["owner_blocked"] == "f" }
        }
        record("after Unblock: trust=\(cleared["trust_level"] ?? "?") owner_blocked=\(cleared["owner_blocked"] ?? "?")")
    }

    // MARK: S11 (with an assistant)

    /// A catalogue link opens its template's page over the catalogue; with an
    /// assistant Fill in shows there, and Yours on the catalogue (decisions 129, 412).
    func testS11CatalogueLinkWithAssistant() async throws {
        try await ensureSignedIn(owner)
        _ = try await peerDM()
        try await openCatalogueLinkFromChats()
        XCTAssertTrue(element(A11yIdentifiers.interactivePostCatalogScreen.fillIn).exists, "Fill in shows for a template that asks")
        XCTAssertFalse(element(A11yIdentifiers.interactivePostCatalogScreen.assistantNote).exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try require(element(A11yIdentifiers.interactivePostCatalogScreen.yours), timeout: 10, "Yours on the catalogue with an assistant")
    }

    // MARK: S13

    /// Agents › the assistant › Usage loads, no error.
    func testS13Usage() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        let agentsTab = app.tabBars.buttons["Agents"].firstMatch
        try tap(agentsTab, "the Agents tab")
        try tap(element(A11yIdentifiers.agentSpacesScreen.agent(assistant.mxid)), timeout: 30, "the assistant's row")
        try tap(element(A11yIdentifiers.agentDetailScreen.usage), timeout: 30, "the Usage shortcut")
        try require(element(A11yIdentifiers.agentUsageScreen.week), timeout: 30, "the week's card")
        XCTAssertFalse(errorShown(), "Usage shows no error")

        let usage = try await helper.peer("api", owner.localpart, "GET", "/api/v1/agents/\(assistant.agentID)/usage")
        record("GET /agents/{id}/usage: http \(usage.first?["http"] ?? "?")")
        XCTAssertEqual(usage.first?["http"] as? Int, 200)
    }

    // MARK: S15

    /// In the assistant's DM: «+» › Agents opens the chat's tools with the
    /// assistant and «Add a tool» (question 359, item 12), which opens the
    /// kinds it can take here without an error.
    func testS15RoomToolsScreens() async throws {
        try await ensureSignedIn(owner)
        let assistant = try await ownerAssistant()
        try openRoom(named: ownerAssistantRoomName)
        try tap(element(A11yIdentifiers.roomScreen.composerToolbar.openComposeOptions), "the composer's +")
        try tap(element(A11yIdentifiers.roomScreen.attachmentPickerAgentTools), "+ › Agents")
        try require(element(A11yIdentifiers.agentSheetScreen.agent(assistant.mxid)), timeout: 30, "the assistant in the chat's tools")
        XCTAssertFalse(errorShown(), "the chat's tools show no error")
        try tap(element(A11yIdentifiers.agentSheetScreen.addTool), timeout: 30, "«Add a tool» under the assistant")
        try require(element(A11yIdentifiers.addToolScreen.kind("call_summary")), timeout: 30, "the kinds of tool for this chat")
        XCTAssertFalse(errorShown(), "the kinds of tool show no error")
    }

    // MARK: S16

    /// Settings › Your data › Export my data: the share sheet with the file,
    /// and the export's GDPR audit row.
    func testS16ExportYourData() async throws {
        try await ensureSignedIn(owner)
        let since = now
        try openSettings()
        try scrollAndTap(element(A11yIdentifiers.settingsScreen.yourData), "Settings › Your data")
        try tap(element(A11yIdentifiers.yourDataScreen.exportAccount), timeout: 30, "Export my data")
        let sheet = [app.otherElements["ActivityListView"].firstMatch,
                     app.buttons["Close"].firstMatch,
                     app.navigationBars["UIActivityContentView"].firstMatch]
        XCTAssertNotNil(firstAppearing(sheet, timeout: 60), "the share sheet with the export")
        let rows = try await eventually("a gdpr_tenant_export audit row") {
            try await helper.check("export_audit", ["mxid": owner.mxid, "since": since]).first { Int($0["exports"] ?? "0") ?? 0 > 0 }
        }
        record("gdpr_audit_log gdpr_tenant_export rows since the tap: \(rows["exports"] ?? "?")")
        if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap() }
    }

    // MARK: - Helpers
    
    /// An agent acts on a message only when its sender and the owner allowed
    /// third-party AI: the owner did in the app (S3), the peer does here.
    private func grantAIConsent() async throws {
        try await helper.peer("consent", peer.localpart, "grant")
        let owner = try await helper.peer("consent", owner.localpart, "status").first
        guard owner?["granted"] as? Bool == true else {
            throw DevE2EError.flow("the owner has not allowed AI")
        }
    }

    /// The peer's DM with the owner (the peer creates it once).
    private func peerDM() async throws -> String {
        let dm = try await helper.peer("dm", peer.localpart, owner.mxid)
        return try XCTUnwrap(dm.first?["room_id"] as? String, "the peer's DM with the owner")
    }

    private func openCatalogueLinkFromChats() async throws {
        // The peer's DM must be joined to be offered: open it once, then
        // start from a fresh Chats list as a link tapped elsewhere does.
        try openRoom(named: peer.displayName)
        try await launchApp()
        try require(homeAvatar, timeout: 60, "the Chats list after a relaunch")
        try await openCatalogueLink(roomNamed: peer.displayName)
    }
}

extension DevE2ETestCase {
    func requireGone(_ element: XCUIElement, timeout: TimeInterval = 20, _ what: String) throws {
        let end = Date().addingTimeInterval(timeout)
        while element.exists, Date() < end {
            settle(0.5)
        }
        if element.exists { throw DevE2EError.flow("\(what) did not close within \(Int(timeout)) s") }
    }
}
