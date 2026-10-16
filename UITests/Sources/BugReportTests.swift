//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import XCTest

// AGENT-PLATFORM (Brief 0063 audit wave 8): distinct screenshot steps.

@MainActor
class BugReportTests: XCTestCase {
    func testInitialStateComponents() async throws {
        let app = Application.launch(.bugReport)
        
        // Initial state without a screenshot attached.
        try await app.assertScreenshot()
    }
    
    func testReportText() async throws {
        let app = Application.launch(.bugReport)
        
        // Type 4 characters and the send button should be disabled.
        app.textFields[A11yIdentifiers.bugReportScreen.report].clearAndTypeText("Text", app: app)
        XCTAssert(app.switches[A11yIdentifiers.bugReportScreen.sendLogs].isOn)
        XCTAssert(!app.switches[A11yIdentifiers.bugReportScreen.canContact].isOn)
        // Distinct steps or both screenshots compare against ONE reference —
        // which is how this test shipped, and it passed only while the
        // perceptual tolerance absorbed the difference between "Text" and
        // "Longer text" (audit wave 8 close-out).
        try await app.assertScreenshot(step: 1)
        
        // Type more than 4 characters and send the button should become enabled.
        app.textFields[A11yIdentifiers.bugReportScreen.report].clearAndTypeText("Longer text", app: app)
        XCTAssert(app.switches[A11yIdentifiers.bugReportScreen.sendLogs].isOn)
        XCTAssert(!app.switches[A11yIdentifiers.bugReportScreen.canContact].isOn)
        try await app.assertScreenshot(step: 2)
    }
}

private extension XCUIElement {
    var isOn: Bool {
        (value as? String) == "1"
    }
}
