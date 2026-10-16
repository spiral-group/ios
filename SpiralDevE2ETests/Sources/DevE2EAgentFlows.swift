//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 148): the steps the coverage lane's scenarios
// share — a visitor's first contact that makes an approval card, the
// Agents tab's bell and the notifications hub, the card's buttons, a block
// from a DM's details, the way back from a sheet to the room under it.
//

import XCTest

/// A first-contact card: the visitor's DM with the assistant and the
/// approval it made.
struct DevE2ECard {
    let roomID: String
    let approvalID: String
}

extension DevE2ETestCase {
    var approvalIDs: A11yIdentifiers.ApprovalDetailScreen {
        A11yIdentifiers.approvalDetailScreen
    }

    var hubIDs: A11yIdentifiers.NotificationsHubScreen {
        A11yIdentifiers.notificationsHubScreen
    }

    var agentsTab: XCUIElement {
        app.tabBars.buttons["Agents"].firstMatch
    }

    func unixNow() -> String {
        String(Int(Date().timeIntervalSince1970) - 2)
    }

    // MARK: - Cards

    /// `visitor` allows AI (an agent acts only on a consenting sender's
    /// message), opens a DM with the assistant and writes a first message
    /// the `visitor-draft` rules answer; the assistant tells them it passed
    /// it on, and a pending card with a draft waits for the owner.
    func firstContact(from visitor: DevE2EFixture.Person, to assistant: DevE2EAssistant, token: String) async throws -> DevE2ECard {
        try await helper.peer("consent", visitor.localpart, "grant")
        let since = unixNow()
        let dm = try await helper.peer("dm", visitor.localpart, assistant.mxid, "--wait-joined")
        let roomID = try XCTUnwrap(dm.first?["room_id"] as? String, "the visitor's DM with the assistant")
        try await helper.peer("send", visitor.localpart, roomID, "Hello, this is \(visitor.displayName). Can we meet on Friday? \(token)")
        let told = try await helper.peer("wait", visitor.localpart, roomID, ".", "120", assistant.mxid)
        try requireNoMockMiss(told.first?["body"] as? String, "the assistant's answer to the visitor")
        let card = try await eventually("a pending first-contact card for \(visitor.mxid)", timeout: 60) {
            try await helper.check("approvals", ["agent": assistant.mxid, "since": since])
                .first { $0["room_id"] == roomID && $0["decision"] == "pending" && $0["kind"] != "block_sender" }
        }
        record("approvals: id=\(card["id"] ?? "?") kind=\(card["kind"] ?? "?") draft=\(card["has_draft"] ?? "?")")
        XCTAssertEqual(card["has_draft"], "t", "a first-contact card carries a draft")
        XCTAssertEqual(card["mock_miss"], "f", "the draft is a scripted answer, not the AI mock's miss")
        return try DevE2ECard(roomID: roomID, approvalID: XCTUnwrap(card["id"]))
    }

    /// The card's row once it is decided: waits for the decision to land.
    func decidedApproval(_ id: String) async throws -> [String: String] {
        try await eventually("the decision on card \(id)", timeout: 30) {
            try await helper.check("approval", ["id": id]).first { $0["decision"] != "pending" }
        }
    }

    /// Agents tab › the bell › the notifications hub.
    func openNotificationsHub() throws {
        try tap(agentsTab, timeout: 30, "the Agents tab")
        try tap(element(A11yIdentifiers.agentSpacesScreen.approvalsBell), timeout: 30, "the Approvals bell")
        try require(app.navigationBars["Notifications"].firstMatch, timeout: 20, "the notifications hub")
    }

    /// From the hub, the card's row › its detail screen.
    func openApproval(_ id: String) throws {
        try tap(element(hubIDs.item(id)), timeout: 30, "the card \(id) in the hub's Needs action")
        try require(app.navigationBars["Approval"].firstMatch, timeout: 20, "the approval's screen")
    }

    /// The pinned rows of the hub, by the id their identifier carries.
    func hubItemIDs() -> [String] {
        let prefix = hubIDs.item("")
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
            .map { String($0.identifier.dropFirst(prefix.count)) }
    }

    // MARK: - The card's screen

    /// The draft editor (a vertical text field, which XCUITest may report
    /// as a text view).
    var draftEditor: XCUIElement {
        let id = approvalIDs.draftField
        let view = app.textViews[id].firstMatch
        return view.exists ? view : app.textFields[id].firstMatch
    }

    /// Empties a text field and types `text` into it.
    func replaceText(in field: XCUIElement, with text: String) throws {
        try require(field, "the text field to edit")
        // The caret at the end, then delete everything before it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.9)).tap()
        settle(1)
        dismissKeyboardTip()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 4))
        settle(0.5)
        field.typeText(text)
        settle(0.5)
        guard let value = field.value as? String, value.contains(text), value.count <= text.count + 2 else {
            throw DevE2EError.flow("the field did not end up holding only the new text")
        }
    }

    /// The title of the alert on screen, once one shows.
    func alertTitle(timeout: TimeInterval = 20) throws -> String {
        let alert = app.alerts.firstMatch
        try require(alert, timeout: timeout, "an alert")
        return alert.label
    }

    // MARK: - Blocks

    /// Opens the DM with `person` from the Chats list and blocks them from
    /// its details (S9's path); waits for the backend to mirror the block.
    func blockInDirectMessage(with person: DevE2EFixture.Person) async throws {
        try openRoom(named: person.displayName)
        try tap(element(A11yIdentifiers.roomScreen.name), "the room's name")
        try scrollAndTap(element(A11yIdentifiers.roomDetailsScreen.blockUser), "Room details › Block user")
        let alert = app.alerts.firstMatch
        try require(alert, "the block alert")
        try tap(alert.buttons["Block"].firstMatch, "the alert's Block")
        let blocked = try await eventually("owner_blocked_at set for \(person.mxid)") {
            try await helper.check("owner_block", ["owner": fixture.owner.mxid, "contact": person.mxid]).first { $0["owner_blocked"] == "t" }
        }
        record("agent_contact_relationships: trust=\(blocked["trust_level"] ?? "?") owner_blocked=\(blocked["owner_blocked"] ?? "?")")
    }

    // MARK: - Messages as the API sees them

    /// What `person` reads in `roomID`, as the peer script reports it.
    func messages(in roomID: String, as person: DevE2EFixture.Person, limit: Int = 30) async throws -> [[String: Any]] {
        try await helper.peer("read", person.localpart, roomID, String(limit))
    }

    /// Whether `sender` posted anything but a client-rendered notice in `roomID`.
    func postedText(in roomID: String, by sender: String, as person: DevE2EFixture.Person) async throws -> Bool {
        try await messages(in: roomID, as: person).contains {
            $0["sender"] as? String == sender && $0["msgtype"] as? String != "com.spiral.notice"
        }
    }

    /// The notices of `kind` that `sender` posted in `roomID`.
    func notices(_ kind: String, in roomID: String, by sender: String, as person: DevE2EFixture.Person) async throws -> Int {
        try await messages(in: roomID, as: person).count {
            $0["sender"] as? String == sender && $0["notice_kind"] as? String == kind
        }
    }

    // MARK: - Navigation

    /// Back to the room's timeline from whatever sheet or pushed screen is
    /// on top of it (Settings opened from a notice's action).
    func returnToRoom() throws {
        for _ in 0..<5 {
            if composer.exists, composer.isHittable { return }
            let done = element(A11yIdentifiers.settingsScreen.done)
            if done.exists, done.isHittable {
                done.tap()
            } else if let back = app.navigationBars.buttons.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                back.tap()
            }
            settle(1)
        }
        try require(composer, timeout: 10, "the room under the sheet")
    }
}
