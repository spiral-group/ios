//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (coverage walk F3): a tab's badge was not in the
// accessibility tree; the tab reported only whether it was selected, so
// VoiceOver never said the count and a UI test could not read it.
//

import XCTest

@MainActor
class SpiralTabBadgeTests: XCTestCase {
    func testATabsBadgeCountIsItsAccessibilityValue() {
        let app = Application.launch(.spiralTabBarBadge)
        
        let agents = app.tabBars.buttons["Agents"]
        XCTAssertTrue(agents.waitForExistence(timeout: 10.0))
        let value = agents.value as? String ?? ""
        XCTAssertTrue(value.contains("3"), "the Agents tab reads \"\(value)\", not its badge count")
        
        let chats = app.tabBars.buttons["Chats"]
        XCTAssertFalse((chats.value as? String ?? "").contains("waiting"), "a tab with no badge says no count")
    }
}
