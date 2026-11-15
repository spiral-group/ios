//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, questions 398 and 413). Spiral's own viewer replaced QuickLook: close sits alone on
// the left of the top bar, and info in the bottom bar opens the file's details.
//

import XCTest

@MainActor
class MediaViewerTests: XCTestCase {
    func testInfoSitsInTheBottomBarAndOpensTheDetails() {
        let app = Application.launch(.mediaViewer)

        let info = app.buttons[A11yIdentifiers.mediaViewer.info]
        XCTAssertTrue(info.waitForExistence(timeout: 10.0), "the info button is not in the viewer")
        let close = app.buttons["Close"]
        XCTAssertTrue(close.exists, "the viewer has no close button")
        XCTAssertGreaterThan(info.frame.minY, close.frame.maxY, "info is not below close")

        info.tap()
        XCTAssertTrue(app.staticTexts["Alex Sample"].waitForExistence(timeout: 5.0), "the details sheet did not show the sender")
    }
}
