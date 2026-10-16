//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): how a presence reads under a
// name, which answers are the same to look at, and whose presence means anything.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct UserPresenceTests {
    static let alice = "@alice:spiral.md"
    
    // en_GB in UTC: fixed wording and a 24-hour clock (en_US puts a narrow
    // no-break space before AM/PM).
    let locale = Locale(identifier: "en_GB")
    let calendar: Calendar
    /// Sunday 4 October 2026, 15:00 UTC.
    let now: Date
    
    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        self.calendar = calendar
        now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 15)) ?? .distantPast
    }
    
    /// A date that fails to build reads as `distantPast`, which no expectation matches.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }
    
    /// Offline, last active at `lastActive`, as answered at `receivedAt`.
    private func seen(at lastActive: Date, receivedAt: Date? = nil, state: UserPresence.State = .offline) -> UserPresence {
        let receivedAt = receivedAt ?? now
        return UserPresence(userID: Self.alice, state: state, lastActiveAgo: receivedAt.timeIntervalSince(lastActive),
                            currentlyActive: false, receivedAt: receivedAt)
    }
    
    private func text(_ presence: UserPresence, at date: Date? = nil) -> String? {
        presence.statusText(now: date ?? now, calendar: calendar, locale: locale)
    }
    
    // MARK: - Exact
    
    @Test
    func onlineAndActiveReadsOnline() {
        let presence = UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 3, currentlyActive: true, receivedAt: now)
        #expect(presence.isOnline)
        #expect(text(presence) == "online")
    }
    
    @Test
    func underAMinuteIsJustNow() {
        #expect(text(seen(at: now)) == "last seen just now")
        #expect(text(seen(at: now.addingTimeInterval(-59))) == "last seen just now")
    }
    
    @Test
    func underAnHourCountsMinutes() {
        #expect(text(seen(at: now.addingTimeInterval(-60))) == "last seen 1 minute ago")
        #expect(text(seen(at: now.addingTimeInterval(-5 * 60))) == "last seen 5 minutes ago")
        #expect(text(seen(at: now.addingTimeInterval(-59 * 60))) == "last seen 59 minutes ago")
    }
    
    @Test
    func laterTodayAndYesterdayGiveTheTime() {
        #expect(text(seen(at: date(2026, 10, 4, 13, 5))) == "last seen today at 13:05")
        #expect(text(seen(at: date(2026, 10, 3, 21, 10))) == "last seen yesterday at 21:10")
        // The day's edges; how the locale pads midnight's hour is its own business.
        #expect(text(seen(at: date(2026, 10, 4, 0, 1)))?.hasPrefix("last seen today at ") == true)
        #expect(text(seen(at: date(2026, 10, 3, 0, 0)))?.hasPrefix("last seen yesterday at ") == true)
    }
    
    @Test
    func olderGivesTheDateAndTheYearOnlyWhenItDiffers() {
        #expect(text(seen(at: date(2026, 10, 2, 23, 59))) == "last seen on 2 October")
        #expect(text(seen(at: date(2026, 9, 12, 10))) == "last seen on 12 September")
        #expect(text(seen(at: date(2025, 3, 1, 12))) == "last seen on 1 March 2025")
    }
    
    @Test
    func justAfterMidnightAnHourAgoIsStillMinutes() {
        let lateNight = date(2026, 10, 4, 0, 20)
        #expect(text(seen(at: date(2026, 10, 3, 23, 50), receivedAt: lateNight), at: lateNight) == "last seen 30 minutes ago")
    }
    
    @Test
    func itAgesFromWhenTheAnswerArrived() {
        let presence = seen(at: now.addingTimeInterval(-30))
        #expect(text(presence) == "last seen just now")
        #expect(text(presence, at: now.addingTimeInterval(10 * 60)) == "last seen 10 minutes ago")
        #expect(text(presence, at: now.addingTimeInterval(3 * 60 * 60)) == "last seen today at 14:59")
    }
    
    @Test
    func onlineButIdleReadsAsLastSeen() {
        let presence = UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 3 * 60, currentlyActive: false, receivedAt: now)
        #expect(!presence.isOnline)
        #expect(text(presence) == "last seen 3 minutes ago")
    }
    
    @Test
    func withoutATimeThereIsNothingToSay() {
        let presence = UserPresence(userID: Self.alice, state: .offline, lastActiveAgo: nil, currentlyActive: false, receivedAt: now)
        #expect(text(presence) == nil)
    }
    
    // MARK: - Coarse
    
    @Test
    func aBucketIsShownAsGiven() {
        func coarse(_ bucket: UserPresence.LastSeenBucket) -> UserPresence {
            UserPresence(userID: Self.alice, state: .offline, lastActiveAgo: nil, currentlyActive: false, lastSeenBucket: bucket, receivedAt: now)
        }
        #expect(text(coarse(.recently)) == "last seen recently")
        #expect(text(coarse(.withinWeek)) == "last seen within a week")
        #expect(text(coarse(.withinMonth)) == "last seen within a month")
        #expect(text(coarse(.longAgo)) == "last seen a long time ago")
    }
    
    @Test
    func aBucketIsNeverOnline() {
        let presence = UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 1, currentlyActive: true,
                                    lastSeenBucket: .recently, receivedAt: now)
        #expect(!presence.isOnline, "«recently» includes «now» on purpose")
        #expect(text(presence) == "last seen recently")
    }
    
    // MARK: - Equivalence
    
    @Test
    func onlineIsOnlineWhateverTheLastActivity() {
        let first = UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 1, currentlyActive: true, receivedAt: now)
        let later = UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: now.addingTimeInterval(30))
        #expect(first.isEquivalent(to: later))
    }
    
    @Test
    func theSameLastActivityWithinTheJitterIsTheSame() {
        let lastActive = now.addingTimeInterval(-600)
        let first = seen(at: lastActive)
        #expect(first.isEquivalent(to: seen(at: lastActive.addingTimeInterval(2), receivedAt: now.addingTimeInterval(10))))
        #expect(!first.isEquivalent(to: seen(at: lastActive.addingTimeInterval(60), receivedAt: now.addingTimeInterval(10))))
    }
    
    @Test
    func aChangeOfStateOrBucketIsNews() {
        let lastActive = now.addingTimeInterval(-600)
        #expect(!seen(at: lastActive).isEquivalent(to: seen(at: lastActive, state: .unavailable)))
        
        var coarse = seen(at: lastActive)
        coarse.lastSeenBucket = .recently
        #expect(!seen(at: lastActive).isEquivalent(to: coarse))
        
        var coarser = coarse
        coarser.lastSeenBucket = .withinWeek
        #expect(!coarse.isEquivalent(to: coarser))
    }
    
    // MARK: - Policy
    
    @Test
    func agentsAndBridgeContactsHaveNoPresence() {
        for userID in ["@assistant-me:spiral.md",
                       "@telegram_123456:spiral.md", "@whatsapp_380501234567:spiral.md", "@instagram_17841400:spiral.md",
                       "@telegrambot:spiral.md", "@whatsappbot:spiral.md", "@instagrambot:spiral.md", "@instagram-login-bot:spiral.md",
                       "not-a-user-id"] {
            #expect(!SpiralPresencePolicy.hasPresence(userID), "\(userID)")
        }
    }
    
    @Test
    func peopleHavePresenceEvenWithABridgeLikeName() {
        for userID in [Self.alice, "@telegramfan:spiral.md", "@whatsapp:spiral.md", "@my_telegram_123:spiral.md"] {
            #expect(SpiralPresencePolicy.hasPresence(userID), "\(userID)")
        }
    }
}
