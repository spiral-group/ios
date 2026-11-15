//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (questions 394, 395): the AI limit's categories, a category's pause and how the app words when the
// limit or a pause ends. Shared with the NSE, which words the `ai_category_paused` notice in a push.
//

import Foundation

/// What the AI limit's use is split into (`GET /agents/{id}/usage`, question 395).
nonisolated enum AILimitCategory: String, Equatable, CaseIterable {
    case messages
    case roomTools = "room_tools"
    case posts
    case calls
    case callTranslation = "call_translation"
    case callSummaries = "call_summaries"
    case other

    /// A category this build does not know reads as other.
    init(serverValue: String) {
        self = AILimitCategory(rawValue: serverValue) ?? .other
    }
}

/// A category's pause (decisions 10, 14).
nonisolated enum AILimitPause: Equatable {
    /// Lifts at the window's end.
    case until(Date)
    /// No date: off until an admin changes it (a $0 cap).
    case untilChanged

    /// `paused` and `pause_until` as the server sends them; absent `paused` is no pause.
    init?(paused: Bool?, pauseUntil: Date?) {
        guard paused == true else { return nil }
        self = pauseUntil.map(AILimitPause.until) ?? .untilChanged
    }
}

/// How the page and the budget card say when the limit starts afresh: by distance, in the person's time.
nonisolated enum AgentLimitWording {
    enum Distance: Equatable {
        case today
        case tomorrow
        /// Within the coming week: the weekday names it.
        case weekday
        case date
    }

    /// A moment already past is named by its date: a card that stays in the timeline must not say "today" later.
    static func distance(of date: Date, from now: Date, calendar: Calendar) -> Distance {
        guard date >= now else { return .date }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .tomorrow
        case 2...6: return .weekday
        default: return .date
        }
    }

    /// «Обновится в понедельник в 3:00».
    static func resetLine(_ resetsAt: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = time(resetsAt, calendar: calendar)
        return switch distance(of: resetsAt, from: now, calendar: calendar) {
        case .today: UntranslatedL10n.screenAgentUsageResetsToday(time)
        case .tomorrow: UntranslatedL10n.screenAgentUsageResetsTomorrow(time)
        case .weekday: UntranslatedL10n.screenAgentUsageResetsOnWeekday(onWeekday(resetsAt, calendar: calendar), time)
        case .date: UntranslatedL10n.screenAgentUsageResetsOnDate(date(resetsAt, calendar: calendar), time)
        }
    }

    /// At the limit: «ИИ снова заработает в понедельник, 16 ноября, в 3:00.»
    static func aiBackLine(_ resetsAt: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = time(resetsAt, calendar: calendar)
        return switch distance(of: resetsAt, from: now, calendar: calendar) {
        case .today: UntranslatedL10n.screenAgentUsageAiBackToday(time)
        case .tomorrow: UntranslatedL10n.screenAgentUsageAiBackTomorrow(time)
        case .weekday, .date: UntranslatedL10n.screenAgentUsageAiBackOn(onWeekday(resetsAt, calendar: calendar), date(resetsAt, calendar: calendar), time)
        }
    }

    /// A paused row's line (decision 14): «На паузе до понедельника, 3:00», or «На паузе» without a date.
    static func pauseLine(_ pause: AILimitPause, now: Date = .now, calendar: Calendar = .current) -> String {
        guard case let .until(date) = pause else { return UntranslatedL10n.screenAgentUsagePaused }
        let time = time(date, calendar: calendar)
        return switch distance(of: date, from: now, calendar: calendar) {
        case .today: UntranslatedL10n.screenAgentUsagePausedUntilToday(time)
        case .tomorrow: UntranslatedL10n.screenAgentUsagePausedUntilTomorrow(time)
        case .weekday: UntranslatedL10n.screenAgentUsagePausedUntilWeekday(untilWeekday(date, calendar: calendar), time)
        case .date: UntranslatedL10n.screenAgentUsagePausedUntilDate(Self.date(date, calendar: calendar), time)
        }
    }

    /// One category's pause in a line of its own, the row's wording after its name (question 395): «Звонки на паузе до
    /// понедельника, 3:00», or «Звонки на паузе» without a date. The join check, the Assistants sheet and the notice
    /// card say it this way.
    static func categoryPauseLine(_ category: AILimitCategory, _ pause: AILimitPause?,
                                  now: Date = .now, calendar: Calendar = .current) -> String {
        let name = categoryName(category)
        guard case let .until(date) = pause else { return UntranslatedL10n.screenAgentUsageCategoryPaused(name) }
        let time = time(date, calendar: calendar)
        return switch distance(of: date, from: now, calendar: calendar) {
        case .today: UntranslatedL10n.screenAgentUsageCategoryPausedUntilToday(name, time)
        case .tomorrow: UntranslatedL10n.screenAgentUsageCategoryPausedUntilTomorrow(name, time)
        case .weekday: UntranslatedL10n.screenAgentUsageCategoryPausedUntilWeekday(name, untilWeekday(date, calendar: calendar), time)
        case .date: UntranslatedL10n.screenAgentUsageCategoryPausedUntilDate(name, Self.date(date, calendar: calendar), time)
        }
    }

    static func categoryName(_ category: AILimitCategory) -> String {
        switch category {
        case .messages: UntranslatedL10n.screenAgentUsageCategoryMessages
        case .roomTools: UntranslatedL10n.screenAgentUsageCategoryRoomTools
        case .posts: UntranslatedL10n.screenAgentUsageCategoryPosts
        case .calls: UntranslatedL10n.screenAgentUsageCategoryCalls
        case .callTranslation: UntranslatedL10n.screenAgentUsageCategoryCallTranslation
        case .callSummaries: UntranslatedL10n.screenAgentUsageCategoryCallSummaries
        case .other: UntranslatedL10n.screenAgentUsageCategoryOther
        }
    }

    /// "until Monday" by distance, for a line too short for the time: the call screen's.
    static func until(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        switch distance(of: date, from: now, calendar: calendar) {
        case .today: UntranslatedL10n.screenAgentUsageUntilMoment(time(date, calendar: calendar))
        case .tomorrow: UntranslatedL10n.screenAgentUsageUntilTomorrow
        case .weekday: untilWeekday(date, calendar: calendar)
        case .date: UntranslatedL10n.screenAgentUsageUntilMoment(Self.date(date, calendar: calendar))
        }
    }

    /// The budget card stays in the timeline, so it names the day absolutely: "today" would go stale.
    static func budgetCardBody(_ resetsAt: Date, calendar: Calendar = .current) -> String {
        UntranslatedL10n.noticeAiBudgetReachedBody(onWeekday(resetsAt, calendar: calendar), date(resetsAt, calendar: calendar), time(resetsAt, calendar: calendar))
    }


    static func mostGoesTo(_ category: AILimitCategory) -> String {
        switch category {
        case .messages: UntranslatedL10n.screenAgentUsageMostMessages
        case .roomTools: UntranslatedL10n.screenAgentUsageMostRoomTools
        case .posts: UntranslatedL10n.screenAgentUsageMostPosts
        case .calls: UntranslatedL10n.screenAgentUsageMostCalls
        case .callTranslation: UntranslatedL10n.screenAgentUsageMostCallTranslation
        case .callSummaries: UntranslatedL10n.screenAgentUsageMostCallSummaries
        case .other: UntranslatedL10n.screenAgentUsageMostOther
        }
    }

    /// "on Friday" with its preposition and case («в пятницу»): the weekday's own key per language.
    static func onWeekday(_ date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: UntranslatedL10n.screenAgentUsageOnSunday
        case 2: UntranslatedL10n.screenAgentUsageOnMonday
        case 3: UntranslatedL10n.screenAgentUsageOnTuesday
        case 4: UntranslatedL10n.screenAgentUsageOnWednesday
        case 5: UntranslatedL10n.screenAgentUsageOnThursday
        case 6: UntranslatedL10n.screenAgentUsageOnFriday
        default: UntranslatedL10n.screenAgentUsageOnSaturday
        }
    }

    /// "until Monday" («до понедельника»).
    static func untilWeekday(_ date: Date, calendar: Calendar) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: UntranslatedL10n.screenAgentUsageUntilSunday
        case 2: UntranslatedL10n.screenAgentUsageUntilMonday
        case 3: UntranslatedL10n.screenAgentUsageUntilTuesday
        case 4: UntranslatedL10n.screenAgentUsageUntilWednesday
        case 5: UntranslatedL10n.screenAgentUsageUntilThursday
        case 6: UntranslatedL10n.screenAgentUsageUntilFriday
        default: UntranslatedL10n.screenAgentUsageUntilSaturday
        }
    }

    /// "9–15 November", the window's UTC days.
    static func dayRange(from first: Date, to last: Date) -> String {
        if Calendar.utcWeeks.isDate(first, inSameDayAs: last) {
            var style = Date.FormatStyle.dateTime.day().month(.wide)
            style.timeZone = .gmt
            return first.formatted(style)
        }
        var style = Date.IntervalFormatStyle.interval.day().month(.wide)
        style.timeZone = .gmt
        return (first..<last).formatted(style)
    }

    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
    }

    static func date(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.day().month(.wide)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

extension Calendar {
    /// Weeks from Monday in UTC, the limit's own calendar.
    nonisolated static var utcWeeks: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        return calendar
    }
}
