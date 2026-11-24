//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (1.0.3). A post the server stamped a moment ahead of the
// phone's clock read «in 0 s» right after it was published (Stage-B, 2026-11-23).
//

import Foundation
@testable import Spiral
import Testing

struct FeedShortTimeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func aPostStampedAheadOfTheClockIsShownASecondOld() {
        let ahead = now.addingTimeInterval(0.8)
        #expect(FeedShortTime.shownDate(ahead, now: now) == now.addingTimeInterval(-1))
    }

    @Test
    func aPastPostKeepsItsOwnTime() {
        let past = now.addingTimeInterval(-90)
        #expect(FeedShortTime.shownDate(past, now: now) == past)
    }

    @Test(arguments: [0.8, 0.0])
    func aNewPostReadsAsPastNotFuture(secondsAhead: Double) {
        let ahead = now.addingTimeInterval(secondsAhead)
        let shown = FeedShortTime.shownDate(ahead, now: now)
        let style = Date.AnchoredRelativeFormatStyle(anchor: shown, presentation: .numeric, unitsStyle: .wide)
            .locale(Locale(identifier: "en_US"))
        #expect(!style.format(now).hasPrefix("in "))
    }

    @Test(arguments: [0.8, 120.0])
    func voiceOverNeverSaysANewPostIsInTheFuture(secondsAhead: Double) {
        let spoken = FeedShortTime.spokenTime(now.addingTimeInterval(secondsAhead), now: now)
        #expect(!spoken.lowercased().contains("in "))
    }
}
