//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import XCTest

enum Application {
    static func launch(viewID: String, appearance: String? = nil) -> XCUIApplication {
        checkEnvironments()
        
        let app = XCUIApplication()
        
        var launchEnvironment = [
            "ACCESSIBILITY_VIEW": viewID
        ]
        // AGENT-PLATFORM (Brief 0083 L1c): Spiral's gate audits a preview in light and in dark.
        launchEnvironment["ACCESSIBILITY_APPEARANCE"] = appearance
        
        app.launchEnvironment = launchEnvironment
        app.launch()
        return app
    }
    
    private static func checkEnvironments() {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            XCTFail("Accessibility tests should be run on a phone.")
            fatalError("Accessibility tests should be run on a phone.")
        }
    }
}
