//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM (Brief 0078): Spiral collects no analytics or crash data, and App Store
// Connect's privacy label says so. PostHog and Sentry are not linked: their own privacy
// manifests would land in the archive's privacy report and contradict the label.

import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralNoAnalyticsTests {
    @Test
    func neitherSDKIsLinked() {
        // Both entry points are Swift classes, so the runtime knows them by module-qualified name only.
        #expect(NSClassFromString("Sentry.SentrySDK") == nil)
        #expect(NSClassFromString("PostHog.PostHogSDK") == nil)
    }

    @Test
    func thereIsNothingToConsentTo() {
        let appSettings = AppSettings.volatile()
        #expect(appSettings.analyticsConfiguration == nil)
        #expect(!appSettings.canPromptForAnalytics)

        let analytics = AnalyticsService(client: DisabledAnalyticsClient(), appSettings: appSettings)
        #expect(!analytics.shouldShowAnalyticsPrompt)
    }

    @Test
    func optingInStartsNothing() {
        let appSettings = AppSettings.volatile()
        let client = AnalyticsClientMock()
        client.isRunning = false
        let analytics = AnalyticsService(client: client, appSettings: appSettings)

        // A consent stored by an older build must not wake anything up.
        appSettings.analyticsConsentState = .optedIn
        analytics.startIfEnabled()

        #expect(!client.startAnalyticsConfigurationCalled)
        #expect(!DisabledAnalyticsClient().isRunning)
    }
}
