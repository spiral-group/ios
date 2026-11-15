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
    func testATabsBadgeCountIsItsAccessibilityValue() throws {
        try skipOnIPad()
        let app = Application.launch(.spiralTabBarBadge)
        
        let agents = app.tabBars.buttons["Agents"]
        XCTAssertTrue(agents.waitForExistence(timeout: 10.0))
        let value = agents.value as? String ?? ""
        XCTAssertTrue(value.contains("3"), "the Agents tab reads \"\(value)\", not its badge count")
        
        let chats = app.tabBars.buttons["Chats"]
        XCTAssertFalse((chats.value as? String ?? "").contains("waiting"), "a tab with no badge says no count")
    }
    
    /// Brief 0082 E2E (FD1, FD3, FD8): a tab's identifier reached its button late on iOS 27, or never,
    /// and the scenarios could not find the Feed tab. It is there from the first look, badge or not.
    func testEveryTabHasItsIdentifierAsSoonAsItShows() throws {
        try skipOnIPad()
        let app = Application.launch(.spiralTabBarBadge)
        
        let agents = app.tabBars.buttons["Agents"]
        XCTAssertTrue(agents.waitForExistence(timeout: 10.0))
        let identifiers = app.tabBars.buttons.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(identifiers, [A11yIdentifiers.homeTabs.chats, A11yIdentifiers.feedScreen.tab, A11yIdentifiers.homeTabs.agents])
    }
    
    /// iPad shows the tabs in a sidebar or a top bar that has no tab bar element (Brief 0083 final verification, § 2).
    private func skipOnIPad() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Reads app.tabBars, which iPad doesn't have")
    }
}
