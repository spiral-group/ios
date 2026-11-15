//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): what every new row asks for comes from a cache that answers as the slow
// way would, and misses when it should.
//

import Foundation
@testable import Spiral
import Testing

struct TimelineRowCostTests {
    @Test
    func aTimeReadsTheSameFromTheCache() {
        let date = Date(timeIntervalSince1970: 1_700_000_123)
        
        #expect(date.formattedTime() == date.formatted(date: .omitted, time: .shortened))
        #expect(date.formattedTime() == date.formatted(date: .omitted, time: .shortened))
    }
    
    @Test
    func theNextMinuteIsAnotherTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_160)
        
        #expect(date.formattedTime() != date.addingTimeInterval(60).formattedTime())
        #expect(date.formattedTime() == date.addingTimeInterval(59).formattedTime())
    }
    
    @Test
    func aLocaleChangeEmptiesTheTimes() {
        let date = Date(timeIntervalSince1970: 1_700_000_220)
        _ = date.formattedTime()
        
        NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        
        #expect(date.formattedTime() == date.formatted(date: .omitted, time: .shortened))
    }
    
    @Test
    func aReservedSizeIsMeasuredOnce() {
        let key = reservedSizeKey(sendInfo: "once")
        var measures = 0
        
        for _ in 0..<3 {
            _ = TrailingReservedSizes.size(for: key) {
                measures += 1
                return .init(width: 40, height: 16)
            }
        }
        
        #expect(measures == 1)
    }
    
    @Test(arguments: [TrailingReservedSizes.Key(sendInfo: "10:01", pointSize: 12, hasIcon: false, hasTicks: false),
                      TrailingReservedSizes.Key(sendInfo: "10:00", pointSize: 14, hasIcon: false, hasTicks: false),
                      TrailingReservedSizes.Key(sendInfo: "10:00", pointSize: 12, hasIcon: true, hasTicks: false),
                      TrailingReservedSizes.Key(sendInfo: "10:00", pointSize: 12, hasIcon: false, hasTicks: true)])
    func anotherTimeTextSizeOrMarkMissesTheCache(key: TrailingReservedSizes.Key) {
        _ = TrailingReservedSizes.size(for: reservedSizeKey(sendInfo: "10:00")) { .init(width: 40, height: 16) }
        
        let size = TrailingReservedSizes.size(for: key) { .init(width: 99, height: 16) }
        
        #expect(size.width == 99)
    }
    
    @Test
    func aStringFollowsTheLanguage() {
        defer { Bundle.overrideLocalizations = nil }
        
        Bundle.overrideLocalizations = ["en"]
        let english = L10n.actionCancel
        Bundle.overrideLocalizations = ["de"]
        let german = L10n.actionCancel
        Bundle.overrideLocalizations = ["en"]
        
        #expect(english != german)
        #expect(L10n.actionCancel == english)
    }
    
    @Test
    func aStringWithSomethingToFillInIsNotKept() {
        #expect(L10n.commonReplies(1) != L10n.commonReplies(2))
    }
    
    private func reservedSizeKey(sendInfo: String) -> TrailingReservedSizes.Key {
        .init(sendInfo: sendInfo, pointSize: 12, hasIcon: false, hasTicks: false)
    }
}
