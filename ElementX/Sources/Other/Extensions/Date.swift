//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

extension Date {
    // AGENT-PLATFORM: `now` is injectable so DateTests do not depend on the time they run at.
    /// The date formatted with the minimal necessary units given how long ago it occurred.
    nonisolated func formattedMinimal(now: Date = .now) -> String {
        let calendar = Calendar.current
        
        if calendar.isDate(self, inSameDayAs: now) { // AGENT-PLATFORM: was isDateInToday
            // Just the time if it was today.
            return formatted(date: .omitted, time: .shortened)
        } else if calendar.isDate(self, inDayBefore: now) { // AGENT-PLATFORM: was isDateInYesterday
            // Simply "Yesterday" if it was yesterday.
            guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { fatalError() }
            return yesterday.formatted(Date.RelativeFormatStyle(presentation: .named, capitalizationContext: .beginningOfSentence))
        } else if let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), // AGENT-PLATFORM: now
                  sixDaysAgo <= self {
            // The named day if it was in the last 6 days.
            return formatted(.dateTime.weekday(.wide))
        } else if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now), // AGENT-PLATFORM: now
                  oneYearAgo <= self {
            // The day and month if it was in the past year
            return formatted(.dateTime.day().month())
        } else {
            // The day, month and year if it is any older.
            return formatted(.dateTime.year().day().month())
        }
    }
    
    /// The date of an expiration formatted with the minimal necessary units given how long in the future it is.
    nonisolated func formattedExpiration() -> String {
        let calendar = Calendar.current
        let now = Date.now
        
        guard let tomorrow = calendar.date(byAdding: .hour, value: 24, to: now),
              let oneYearFromNow = calendar.date(byAdding: .year, value: 1, to: now) else {
            return formatted(date: .omitted, time: .shortened)
        }
        
        if self < tomorrow {
            return formatted(date: .omitted, time: .shortened)
        } else if self < oneYearFromNow {
            return formatted(.dateTime.day().month())
        } else {
            return formatted(.dateTime.year())
        }
    }
    
    // AGENT-PLATFORM: `now` is injectable so DateTests do not depend on the time they run at.
    /// Similar to ``formattedMinimal`` but returning "Today" instead of the time and
    /// including the year when it the date is from a previous year (rather than over a year ago).
    func formattedDateSeparator(now: Date = .now) -> String {
        let calendar = Calendar.current
        
        // AGENT-PLATFORM: today/yesterday are judged against `now`; the relative formatter reads the
        // wall clock, so it formats the wall-clock today or yesterday to get the "Today"/"Yesterday" word.
        if calendar.isDate(self, inSameDayAs: now) {
            // Simply "Today" if it was today.
            return DateFormatter.relative.string(from: .now)
        } else if calendar.isDate(self, inDayBefore: now),
                  let yesterday = calendar.date(byAdding: .day, value: -1, to: .now) {
            // Simply "Yesterday" if it was yesterday.
            return DateFormatter.relative.string(from: yesterday)
        } else if let sixDaysAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)), // AGENT-PLATFORM: now
                  sixDaysAgo <= self {
            // The named day if it was in the last 6 days.
            return formatted(.dateTime.weekday(.wide))
        } else if calendar.component(.year, from: self) == calendar.component(.year, from: now) { // AGENT-PLATFORM: now
            // The day and month if it was this year.
            return formatted(.dateTime.weekday(.wide).day().month(.wide))
        } else {
            // The day, month and year if it is any older.
            return formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        }
    }
    
    /// The date formatted as just the time, for use in timeline items specifically.
    nonisolated func formattedTime() -> String {
        formatted(date: .omitted, time: .shortened)
    }
    
    /// A fixed date used for mocks, previews etc.
    nonisolated static var mock: Date {
        DateComponents(calendar: .current, year: 2007, month: 1, day: 9, hour: 9, minute: 41).date ?? .now
    }
}

private extension DateFormatter {
    /// There doesn't appear to be a way to get "Today" out of
    /// `Date.RelativeFormatStyle` so use the old way instead 😐
    static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}

// AGENT-PLATFORM: `isDateInYesterday` for an injectable `now` (see `formattedMinimal(now:)`).
private extension Calendar {
    nonisolated func isDate(_ date: Date, inDayBefore now: Date) -> Bool {
        guard let dayBefore = self.date(byAdding: .day, value: -1, to: now) else { return false }
        return isDate(date, inSameDayAs: dayBefore)
    }
}
