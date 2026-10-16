//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: a profile opened from the room members' bottom sheet must
// still ask before acting. The dev-stack walk (2026-10-11) saw no erase
// confirmation on that path; these walk it — the push races the sheet's
// dismissal — and tap the row itself by its identifier.
//

import XCTest

@MainActor
class SpiralMemberProfileAlertTests: XCTestCase {
    func testAProfileOpenedFromTheMemberSheetCanStillShowAnAlert() {
        let app = Application.launch(.userSessionScreen)

        app.buttons[A11yIdentifiers.homeScreen.roomName("Foundation 🔭🪐🌌")].tap()
        let roomHeader = app.buttons[A11yIdentifiers.roomScreen.name]
        XCTAssertTrue(roomHeader.waitForExistence(timeout: 10.0))
        roomHeader.tap(.center)

        let peopleButton = app.buttons[A11yIdentifiers.roomDetailsScreen.people]
        var attempts = 0
        while !peopleButton.isHittable, attempts < 5 {
            app.swipeUp()
            attempts += 1
        }
        peopleButton.tap()

        let firstRoomMember = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstRoomMember.waitForExistence(timeout: 30.0))
        firstRoomMember.tap(.center)

        let viewProfileButton = app.buttons[A11yIdentifiers.manageRoomMemberSheet.viewProfile]
        XCTAssertTrue(viewProfileButton.waitForExistence(timeout: 10.0))
        viewProfileButton.tap()

        // Block or unblock, whichever the member needs: both ask first.
        let blockButton = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                           [A11yIdentifiers.roomMemberDetailsScreen.ignore,
                                                            A11yIdentifiers.roomMemberDetailsScreen.unignore])).firstMatch
        XCTAssertTrue(blockButton.waitForExistence(timeout: 10.0))
        blockButton.tap()

        let blockAlert = app.alerts.matching(NSPredicate(format: "label IN %@", ["Block user", "Unblock user"])).firstMatch
        XCTAssertTrue(blockAlert.waitForExistence(timeout: 5.0),
                      "the profile pushed from the member sheet could not present its alert")
        XCTAssertTrue(blockAlert.buttons.matching(NSPredicate(format: "label IN %@", ["Block", "Unblock"])).firstMatch.exists)
    }
    
    func testTheEraseRowAsksFirstOnAProfileOpenedFromTheMemberSheet() {
        let app = Application.launch(.roomMembersFlowWithAssistant)
        
        let alice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Alice")).firstMatch
        XCTAssertTrue(alice.waitForExistence(timeout: 10.0))
        alice.tap(.center)
        
        let viewProfileButton = app.buttons[A11yIdentifiers.manageRoomMemberSheet.viewProfile]
        XCTAssertTrue(viewProfileButton.waitForExistence(timeout: 10.0))
        viewProfileButton.tap()
        
        let eraseRow = app.buttons[A11yIdentifiers.roomMemberDetailsScreen.eraseAssistantMemory]
        XCTAssertTrue(eraseRow.waitForExistence(timeout: 10.0))
        eraseRow.tap()
        
        let confirmation = app.alerts["Erase what your assistants know about Alice?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5.0),
                      "tapping the erase row did not ask before erasing")
        XCTAssertTrue(confirmation.buttons["Erase"].exists)
    }
}
