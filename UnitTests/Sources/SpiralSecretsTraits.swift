//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0067): Spiral ships `Secrets.swift` with every entry
// `nil` — there is no rageshake or MapTiler account behind this app, and the
// placeholders upstream commits made TestFlight testers see a bug report
// button that always failed. Upstream's tests assume the placeholders; the
// ones that exercise those endpoints are gated here instead of deleted, so an
// upstream sync keeps them and a future real endpoint re-enables them.
//
// Brief 0078: PostHog and Sentry are not linked at all, so the analytics
// consent tests can never run here; they stay, disabled, for the sync.
extension Trait where Self == ConditionTrait {
    /// Tests that need an analytics SDK and its configuration.
    static var requiresAnalyticsSDK: Self {
        .disabled("Spiral links no analytics SDK (Brief 0078).")
    }

    /// Tests that need a rageshake URL to exist.
    static var requiresRageshakeSecret: Self {
        .enabled(if: Secrets.rageshakeURL != nil,
                 "Spiral ships no rageshake endpoint (Secrets.rageshakeURL is nil).")
    }
}
