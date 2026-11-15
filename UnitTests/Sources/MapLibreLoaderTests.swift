//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

@MainActor
struct MapLibreLoaderTests {
    /// The shim is embedded but not linked, if it ever stops being copied into the app (or
    /// the class is renamed) the interactive map would silently stop working.
    // AGENT-PLATFORM: App Review F1 (decision 252): Spiral embeds no shim, and
    // `SpiralNoLocationSharingTests.theAppEmbedsNoMap` asserts the opposite.
    @Test(.disabled("Spiral ships without MapLibre (decision 252)"))
    func loadsTheShim() {
        #expect(MapLibreLoader.shim != nil)
    }
}
