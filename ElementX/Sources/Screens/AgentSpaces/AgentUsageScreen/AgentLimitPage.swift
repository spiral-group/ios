//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 394): what the Limit page shows, worked out from one usage read.
//

import Foundation

/// The Limit page's content: the window's state, its categories and the past weeks.
nonisolated struct AgentLimitPage: Equatable {
    enum Status: Equatable {
        case normal
        /// 85% or more used: what is left, and the category taking most.
        case nearLimit(leftPercent: Double, biggest: AgentUsage.Category?)
        case limitReached
    }

    /// One category's row: its share of the whole limit and, when its cap is reached, its pause (decisions 14, 15).
    struct CategoryRow: Equatable, Identifiable {
        enum PauseLine: Equatable {
            /// The category waits while the rest works: the icon and the line.
            case active(AgentUsage.Pause)
            /// The whole limit is reached since: the line stays, grey and without the icon.
            case earlier(AgentUsage.Pause)
        }

        let category: AgentUsage.Category
        let usedPercent: Double
        var pause: PauseLine?

        var id: AgentUsage.Category {
            category
        }
    }

    /// One calendar week (Monday to Sunday, UTC) before the current one.
    struct PastWeek: Equatable, Identifiable {
        /// The first and last day the read covers: the oldest week can be partial.
        let firstDay: Date
        let lastDay: Date
        let usedPercent: Double
        /// The day the week's shares reached the limit.
        let limitUsedUpOn: Date?

        var id: Date {
            firstDay
        }
    }

    static let nearLimitPercent = 85.0

    let current: AgentUsage.Current
    let status: Status
    /// Largest first; 0% left out unless paused.
    let categories: [CategoryRow]
    /// The current window's first and last UTC day: its calendar week for a weekly limit.
    let firstDay: Date
    let lastDay: Date
    /// Newest first; only a weekly limit groups its days into weeks.
    let pastWeeks: [PastWeek]

    init(usage: AgentUsage) {
        current = usage.current
        let biggest = Self.sortedCategories(usage.current.categories).first { $0.usedPercent > 0 }?.category
        status = Self.status(of: usage.current, biggest: biggest)
        categories = Self.rows(usage.current.categories, limitReached: status == .limitReached)

        let calendar = Calendar.utcWeeks
        switch usage.current.period {
        case .week:
            let week = calendar.dateInterval(of: .weekOfYear, for: usage.current.startsAt)
            firstDay = week?.start ?? usage.current.startsAt
            lastDay = calendar.date(byAdding: .day, value: 6, to: firstDay) ?? firstDay
            pastWeeks = Self.pastWeeks(usage.days, before: firstDay, calendar: calendar)
        case .other:
            firstDay = calendar.startOfDay(for: usage.current.startsAt)
            lastDay = calendar.startOfDay(for: usage.current.resetsAt.addingTimeInterval(-1))
            pastWeeks = []
        }
    }

    // MARK: - Logic

    /// Largest share first; a paused row keeps its place by share and shows even at 0% (decision 14).
    static func rows(_ categories: [AgentUsage.CategoryShare], limitReached: Bool) -> [CategoryRow] {
        sortedCategories(categories).map { share in
            CategoryRow(category: share.category,
                        usedPercent: share.usedPercent,
                        pause: share.pause.map { limitReached ? .earlier($0) : .active($0) })
        }
    }

    static func sortedCategories(_ categories: [AgentUsage.CategoryShare]) -> [AgentUsage.CategoryShare] {
        let order = AgentUsage.Category.allCases
        return categories
            .filter { $0.usedPercent > 0 || $0.pause != nil }
            .sorted { lhs, rhs in
                if lhs.usedPercent != rhs.usedPercent {
                    return lhs.usedPercent > rhs.usedPercent
                }
                return (order.firstIndex(of: lhs.category) ?? 0) < (order.firstIndex(of: rhs.category) ?? 0)
            }
    }

    static func status(of current: AgentUsage.Current, biggest: AgentUsage.Category?) -> Status {
        if current.limitReached {
            return .limitReached
        }
        if current.usedPercent >= nearLimitPercent {
            return .nearLimit(leftPercent: max(0, 100 - current.usedPercent), biggest: biggest)
        }
        return .normal
    }

    /// Sums the days before the current week into calendar weeks from Monday. Weeks without use before the first used
    /// one are left out: a new agent's page lists no empty weeks.
    static func pastWeeks(_ days: [AgentUsage.Day], before currentWeekStart: Date, calendar: Calendar) -> [PastWeek] {
        let past = days.filter { $0.date < currentWeekStart }
        let byWeek = Dictionary(grouping: past) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        var weeks: [PastWeek] = byWeek.keys.sorted(by: >).compactMap { weekStart in
            let days = byWeek[weekStart, default: []].sorted { $0.date < $1.date }
            guard let first = days.first, let last = days.last else { return nil }
            var total = 0.0
            var usedUpOn: Date?
            for day in days {
                total += day.usedPercent
                if usedUpOn == nil, total >= 100 {
                    usedUpOn = day.date
                }
            }
            let sunday = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? last.date
            return PastWeek(firstDay: first.date,
                            lastDay: max(last.date, sunday),
                            usedPercent: total,
                            limitUsedUpOn: usedUpOn)
        }
        while weeks.last?.usedPercent == 0 {
            weeks.removeLast()
        }
        return weeks
    }
}

// MARK: - Words

extension AgentLimitWording {
    /// At 85% or more: «Осталось 15% на эту неделю. Больше всего уходит на перевод звонков.»
    static func nearLimitLine(leftPercent: Double, biggest: AgentUsage.Category?, period: AgentUsage.Period) -> String {
        let left = percent(leftPercent)
        let first = period == .week ? UntranslatedL10n.screenAgentUsageLeftThisWeek(left) : UntranslatedL10n.screenAgentUsageLeft(left)
        guard let biggest else { return first }
        return "\(first) \(mostGoesTo(biggest))"
    }
}
