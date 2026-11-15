//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 235): a catalogue post's tap (G22, part). It runs
// before E3 on purpose, on the device S02 signed in and verified: S01 and
// G05 sign the owner out, and on the next, unverified device the app's
// identity confirmation (skippable only in debug builds) comes back on every
// change of the session's security state and clears the route — G22's room
// join closed the room under it (2026-10-21).
//

import XCTest

final class E2PostTests: DevE2ETestCase {
    private var owner: DevE2EFixture.Person {
        fixture.owner
    }

    // MARK: G22 (part)

    /// A catalogue post published into a chat runs, and a tap on it writes one
    /// move as the owner — the touch-gated write path of security pass 2
    /// (decision 235). «Dice» asks nothing, so no model is involved; playing
    /// together on two phones stays G22's walk.
    func testG22aCataloguePostTapWrites() async throws {
        try await ensureSignedIn(owner)
        // A chat of its own, unencrypted (the peer script's DM): the moves are
        // then readable to the helper as `com.spiral.app.action` — the peer's
        // DM is S06's, made in the app and encrypted. G13a's visitor writes
        // to the assistant only and is never blocked.
        let person = fixture.visitors[0]
        let dm = try await helper.peer("dm", person.localpart, owner.mxid)
        let roomID = try XCTUnwrap(dm.first?["room_id"] as? String, "a DM between the owner and \(person.mxid)")
        try openRoom(named: person.displayName)
        try await launchApp()
        try require(homeAvatar, timeout: 60, "the Chats list after a relaunch")
        try await openLink("spiral:///catalog/dice")
        let room = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                                                                        A11yIdentifiers.roomSelectionScreen.room(""), person.displayName)).firstMatch
        try tap(room, timeout: 30, "the chat picker's row '\(person.displayName)'")
        try tap(element(A11yIdentifiers.roomSelectionScreen.confirm), "the chat picker's Continue")
        let title = element(A11yIdentifiers.interactivePostCatalogScreen.currentTitle)
        try require(title, timeout: 30, "the catalogue on Dice")
        XCTAssertTrue(title.label.contains("Dice"), "the page on Dice: the post names itself (question 412, A1)")

        let since = unixNow()
        let publish = element(A11yIdentifiers.interactivePostCatalogScreen.publish)
        try require(publish, timeout: 30, "Publish")
        let ready = Date().addingTimeInterval(60)
        while !publish.isEnabled, Date() < ready { settle(1) } // the template downloads first
        publish.tap()

        let roll = app.webViews.buttons["Roll the die"].firstMatch
        try tap(roll, timeout: 90, "the post's «Roll the die»")
        let moves = try await eventually("the owner's move in the room", timeout: 60) {
            try await helper.check("post_actions", ["room": roomID, "sender": owner.mxid, "since": since])
                .first { Int($0["actions"] ?? "0") ?? 0 > 0 }
        }
        record("com.spiral.app.action events from the owner since the tap: \(moves["actions"] ?? "?")")
    }
}
