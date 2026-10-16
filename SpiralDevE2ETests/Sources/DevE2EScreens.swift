//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 146): steps inside a signed-in session that the
// scenarios share: rooms, the composer, Settings rows, the assistant.
//

import XCTest

struct DevE2EAssistant {
    let agentID: String
    let mxid: String
}

extension DevE2ETestCase {
    /// The owner's assistant as the platform lists it (waits for provisioning).
    func ownerAssistant() async throws -> DevE2EAssistant {
        let lines = try await helper.peer("assistant", fixture.owner.localpart, "90")
        guard let line = lines.first, let id = line["agent_id"] as? String, let mxid = line["mxid"] as? String else {
            throw DevE2EError.flow("the owner has no assistant listed")
        }
        return DevE2EAssistant(agentID: id, mxid: mxid)
    }

    /// Opens a room from the Chats list by (part of) its name; an invite
    /// opens its own screen first, where it is accepted.
    func openRoom(named name: String, timeout: TimeInterval = 60) throws {
        let cell = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                                                                        A11yIdentifiers.homeScreen.roomNamePrefix + ":", name)).firstMatch
        try require(cell, timeout: timeout, "the room '\(name)' on the Chats list")
        cell.tap()
        let accept = element(A11yIdentifiers.joinRoomScreen.acceptInvite)
        if firstAppearing([composer, accept], timeout: 20) == 1 {
            accept.tap()
        }
        try require(composer, timeout: 30, "the composer of '\(name)'")
    }
    
    /// The composer's text view (SwiftUI also reports a button with its id).
    var composer: XCUIElement {
        app.textViews[A11yIdentifiers.roomScreen.messageComposer].firstMatch
    }

    func send(_ text: String) throws {
        try tap(composer, "the composer")
        settle(1)
        dismissKeyboardTip()
        composer.typeText(text)
        settle(0.5)
        try tap(element(A11yIdentifiers.roomScreen.sendButton), "Send")
    }

    func timelineText(containing token: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", token)).firstMatch
    }

    /// Scrolls a list until the element can take a tap, then taps it.
    /// A list builds its rows lazily: swipe until the row exists and takes a tap.
    func scrollAndTap(_ element: XCUIElement, _ what: String, swipes: Int = 8) throws {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<swipes where !(element.exists && element.isHittable) {
            app.swipeUp()
            settle(0.7)
        }
        guard element.exists, element.isHittable else { throw DevE2EError.flow("\(what) could not be scrolled into reach") }
        element.tap()
    }

    func errorShown() -> Bool {
        element(A11yIdentifiers.agentSpacesScreen.error).exists
    }

    /// Opens a catalogue link the way a tap on it does, then picks the room.
    func openCatalogueLink(roomNamed roomName: String) async throws {
        try await openLink("spiral:///catalog/\(fixture.catalogTemplate)")
        let room = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                                                                        A11yIdentifiers.roomSelectionScreen.room(""), roomName)).firstMatch
        try tap(room, timeout: 30, "the chat picker's row '\(roomName)'")
        try tap(element(A11yIdentifiers.roomSelectionScreen.confirm), "the chat picker's Continue")
        let title = element(A11yIdentifiers.interactivePostCatalogScreen.currentTitle)
        try require(title, timeout: 30, "the catalogue on a template")
        XCTAssertEqual(title.label, "Poll with names", "the link must open the catalogue on its own template")
    }
}
