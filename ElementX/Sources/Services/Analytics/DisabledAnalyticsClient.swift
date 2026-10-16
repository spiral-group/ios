//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): Spiral links no analytics SDK — PostHog is gone with its
// package. Upstream's `AnalyticsService` stays because every screen reports through it;
// this client is where those reports end: nothing is kept and nothing leaves the device.

import AnalyticsEvents

/// An analytics client that never runs.
struct DisabledAnalyticsClient: AnalyticsClientProtocol {
    var isRunning: Bool {
        false
    }

    func start(analyticsConfiguration: AnalyticsConfiguration) { }

    func reset() { }

    func stop() { }

    func capture(_ event: AnalyticsEventProtocol) { }

    func screen(_ event: AnalyticsScreenProtocol) { }

    func updateUserProperties(_ event: AnalyticsEvent.UserProperties) { }
}
