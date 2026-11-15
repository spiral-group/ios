//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): Spiral ships no `location` background mode while
// location sharing is off. CoreLocation throws if `allowsBackgroundLocationUpdates`
// is set without that mode, and `LiveLocationManager` is built for every session.

import Combine
import CoreLocation
@testable import Spiral
import Testing

@MainActor
struct SpiralLocationBackgroundModeTests {
    @Test
    func theAppDeclaresNoLocationBackgroundMode() {
        let modes = InfoPlistReader.main.backgroundModes
        #expect(modes.contains("voip"), "The host app's Info.plist should be the one read.")
        #expect(!modes.contains("location"))
    }

    @Test
    func theSessionsLocationManagerStaysInTheForeground() {
        let locationManager = makeManager(backgroundModes: InfoPlistReader.main.backgroundModes)
        #expect(locationManager.allowsBackgroundLocationUpdates == false)
    }

    @Test
    func backgroundUpdatesFollowTheDeclaredModes() {
        #expect(makeManager(backgroundModes: ["audio", "voip"]).allowsBackgroundLocationUpdates == false)
        #expect(makeManager(backgroundModes: ["audio", "location"]).allowsBackgroundLocationUpdates == true)
    }

    // MARK: - Helpers

    private func makeManager(backgroundModes: [String]) -> CLLocationManagerMock {
        let locationManager = CLLocationManagerMock(.init())
        _ = LiveLocationManager(appSettings: AppSettings.volatile(),
                                locationManager: locationManager,
                                backgroundModes: backgroundModes)
        return locationManager
    }
}
