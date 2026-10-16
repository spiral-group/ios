//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

struct DateTests {
    let calendar = Calendar.current
    
    // AGENT-PLATFORM: every relative date is built from a fixed reference "now" instead of the
    // wall clock, so the suite passes whatever time it runs at. The reference day is mid-June
    // (no DST change, not in the first week of the year); the times cover just after midnight,
    // when the wall-clock version failed, and noon.
    nonisolated static let referenceTimes = [DateComponents(hour: 0, minute: 15), DateComponents(hour: 12, minute: 0)]
    
    func referenceNow(_ time: DateComponents) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: time.hour, minute: time.minute)))
    }
    
    func startOfToday(_ now: Date) -> Date {
        calendar.startOfDay(for: now)
    }
    
    func startOfYesterday(_ now: Date) throws -> Date {
        try calendar.startOfDay(for: #require(calendar.date(byAdding: .day, value: -1, to: now)))
    }
    
    @Test(arguments: referenceTimes)
    func minimalDateFormatting(at time: DateComponents) throws {
        let now = try referenceNow(time)
        
        let today = try #require(calendar.date(byAdding: DateComponents(hour: 9, minute: 30), to: startOfToday(now)))
        #expect(today.formattedMinimal(now: now) == today.formatted(date: .omitted, time: .shortened))
        
        let yesterday = try #require(calendar.date(byAdding: .hour, value: 1, to: startOfYesterday(now)))
        #expect(yesterday.formattedMinimal(now: now) == "Yesterday")
        
        let nearYesterday = try #require(calendar.date(byAdding: DateComponents(hour: -10), to: today))
        #expect(nearYesterday.formattedMinimal(now: now) == "Yesterday")
        
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: startOfToday(now)))
        #expect(threeDaysAgo.formattedMinimal(now: now) == threeDaysAgo.formatted(.dateTime.weekday(.wide)))
        
        let sometimeInTheLastYear = try #require(calendar.date(byAdding: .month, value: -10, to: startOfToday(now)))
        #expect(sometimeInTheLastYear.formattedMinimal(now: now) == sometimeInTheLastYear.formatted(.dateTime.day().month()))
        
        let theMillennium = try #require(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        #expect(theMillennium.formattedMinimal(now: now) == theMillennium.formatted(.dateTime.year().day().month()))
    }
    
    @Test
    func expirationDateFormatting() throws {
        // Within 24 hours → show time only
        let in23Hours = try #require(calendar.date(byAdding: .hour, value: 23, to: .now))
        #expect(in23Hours.formattedExpiration() == in23Hours.formatted(date: .omitted, time: .shortened))
        
        // Just over the 24h boundary → show day and month
        let in25Hours = try #require(calendar.date(byAdding: .hour, value: 25, to: .now))
        #expect(in25Hours.formattedExpiration() == in25Hours.formatted(.dateTime.day().month()))
        
        // Several months away → show day and month
        let inSixMonths = try #require(calendar.date(byAdding: .month, value: 6, to: .now))
        #expect(inSixMonths.formattedExpiration() == inSixMonths.formatted(.dateTime.day().month()))
        
        // More than a year away → show year only
        let inTwoYears = try #require(calendar.date(byAdding: .year, value: 2, to: .now))
        #expect(inTwoYears.formattedExpiration() == inTwoYears.formatted(.dateTime.year()))
    }
    
    @Test(arguments: referenceTimes)
    func dateSeparatorFormatting(at time: DateComponents) throws {
        let now = try referenceNow(time)
        
        let today = try #require(calendar.date(byAdding: DateComponents(hour: 9, minute: 30), to: startOfToday(now)))
        #expect(today.formattedDateSeparator(now: now) == "Today")
        
        let yesterday = try #require(calendar.date(byAdding: .hour, value: 1, to: startOfYesterday(now)))
        #expect(yesterday.formattedDateSeparator(now: now) == "Yesterday")
        
        let nearYesterday = try #require(calendar.date(byAdding: DateComponents(hour: -10), to: today))
        #expect(nearYesterday.formattedDateSeparator(now: now) == "Yesterday")
        
        let threeDaysAgo = try #require(calendar.date(byAdding: .day, value: -3, to: startOfToday(now)))
        #expect(threeDaysAgo.formattedDateSeparator(now: now) == threeDaysAgo.formatted(.dateTime.weekday(.wide)))
        
        let startOfTheYear = try #require(calendar.dateInterval(of: .year, for: startOfToday(now))?.start)
        #expect(startOfTheYear.formattedDateSeparator(now: now) == startOfTheYear.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        
        let theMillennium = try #require(calendar.date(from: DateComponents(year: 2000, month: 1, day: 1)))
        #expect(theMillennium.formattedDateSeparator(now: now) == theMillennium.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
    }
}
