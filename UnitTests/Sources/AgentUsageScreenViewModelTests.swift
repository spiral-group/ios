//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its weekly limit (Brief 0079 3c, question 394).
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentUsageScreenViewModelTests {
    /// Monday 9 November 2026, 00:00 UTC.
    static let weekStart = Date(timeIntervalSince1970: 1_794_182_400)
    static let day: TimeInterval = 86400

    static let usage = usage(percent: 35, categories: [.init(category: .calls, usedPercent: 25),
                                                       .init(category: .messages, usedPercent: 10)])

    // MARK: - Loading

    @Test
    func loadsTheAgentsUsage() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", store: AgentsStore(service: service))
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(AgentLimitPage(usage: Self.usage)) }
        try await deferred.fulfill()

        #expect(service.fetchAgentUsageAgentIDReceivedAgentID == "agent-1")
    }

    @Test
    func aFailedLoadOffersARetryThatLoads() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 500))

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", store: AgentsStore(service: service))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .failure }
        try await failed.fulfill()

        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(AgentLimitPage(usage: Self.usage)) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }

    /// `agent.usage` reads it again while shown; a read that fails keeps the shown usage.
    @Test
    func theStreamsChangeReadsItAgainAndAFailureKeepsIt() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)
        let store = AgentsStore(service: service)

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(AgentLimitPage(usage: Self.usage)) }
        try await loaded.fulfill()

        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 503))
        store.apply([.agentUsage(agentID: "agent-1")])
        await store.settle()

        #expect(service.fetchAgentUsageAgentIDCallsCount == 2)
        #expect(viewModel.context.viewState.loadState == .loaded(AgentLimitPage(usage: Self.usage)))
    }

    // MARK: - Categories

    @Test
    func categoriesAreSortedByShareAndZeroIsHidden() {
        let page = AgentLimitPage(usage: Self.usage(percent: 40, categories: [.init(category: .posts, usedPercent: 2),
                                                                              .init(category: .callTranslation, usedPercent: 0),
                                                                              .init(category: .calls, usedPercent: 22),
                                                                              .init(category: .messages, usedPercent: 22),
                                                                              .init(category: .roomTools, usedPercent: 0.1)]))

        // Equal shares keep the categories' own order.
        #expect(page.categories.map(\.category) == [.messages, .calls, .posts, .roomTools])
    }

    // MARK: - States

    @Test
    func belowEightyFivePercentIsNormal() {
        #expect(AgentLimitPage(usage: Self.usage(percent: 84.9, categories: [])).status == .normal)
    }

    @Test
    func atEightyFivePercentItSaysWhatIsLeftAndTheBiggestCategory() {
        let page = AgentLimitPage(usage: Self.usage(percent: 85, categories: [.init(category: .calls, usedPercent: 22),
                                                                              .init(category: .callTranslation, usedPercent: 38)]))

        #expect(page.status == .nearLimit(leftPercent: 15, biggest: .callTranslation))
        let left = AgentLimitWording.percent(15)
        #expect(AgentLimitWording.nearLimitLine(leftPercent: 15, biggest: .callTranslation, period: .week)
            == "\(UntranslatedL10n.screenAgentUsageLeftThisWeek(left)) \(UntranslatedL10n.screenAgentUsageMostCallTranslation)")
        #expect(AgentLimitWording.nearLimitLine(leftPercent: 15, biggest: nil, period: .other) == UntranslatedL10n.screenAgentUsageLeft(left))
    }

    @Test
    func overTheLimitWithoutTheServersWordIsNearItWithNothingLeft() {
        #expect(AgentLimitPage(usage: Self.usage(percent: 104, categories: [])).status == .nearLimit(leftPercent: 0, biggest: nil))
    }

    @Test
    func theServersLimitReachedIsTheLimitState() {
        #expect(AgentLimitPage(usage: Self.usage(percent: 100, limitReached: true, categories: [])).status == .limitReached)
    }

    // MARK: - Past weeks

    @Test
    func pastDaysAreSummedIntoCalendarWeeksFromMonday() {
        // Thursday 12 Nov back 30 days: this week's four, three full weeks, then five days of 12–18 Oct.
        let percents: [Double] = [5, 5, 5, 5] + Array(repeating: 10, count: 7) + [0, 0, 30, 30, 20, 10, 10] + Array(repeating: 1, count: 12)
        let days = percents.enumerated().map { index, percent in
            let date = Self.weekStart.addingTimeInterval(Self.day * Double(3 - index))
            return AgentUsage.Day(id: "\(index)", date: date, usedPercent: percent, categories: [])
        }
        let page = AgentLimitPage(usage: Self.usage(percent: 20, categories: [], days: days))

        #expect(page.firstDay == Self.weekStart)
        #expect(page.lastDay == Self.weekStart.addingTimeInterval(6 * Self.day))
        #expect(page.pastWeeks.map(\.usedPercent) == [70, 100, 7, 5])
        #expect(page.pastWeeks.map(\.firstDay) == [-7, -14, -21, -26].map { Self.weekStart.addingTimeInterval(Self.day * $0) })
        #expect(page.pastWeeks.map(\.lastDay) == [-1, -8, -15, -22].map { Self.weekStart.addingTimeInterval(Self.day * $0) })
        // 26 Oct – 1 Nov reached 100% on Friday 30 Oct; no other week did.
        #expect(page.pastWeeks.map(\.limitUsedUpOn) == [nil, Self.weekStart.addingTimeInterval(-10 * Self.day), nil, nil])
    }

    @Test
    func aWindowAfterAResetStillShowsItsCalendarWeek() {
        let page = AgentLimitPage(usage: Self.usage(percent: 1, startsAt: Self.weekStart.addingTimeInterval(2.5 * Self.day), categories: []))
        #expect(page.firstDay == Self.weekStart)
    }

    @Test
    func aPeriodWithoutItsOwnWordsHasNoPastWeeksAndShowsItsDays() {
        let usage = AgentUsage(current: .init(period: .other, startsAt: Self.weekStart, resetsAt: Self.weekStart.addingTimeInterval(Self.day),
                                              usedPercent: 10, limitReached: false, categories: []),
                               days: [.init(id: "x", date: Self.weekStart.addingTimeInterval(-Self.day), usedPercent: 40, categories: [])])
        let page = AgentLimitPage(usage: usage)

        #expect(page.pastWeeks.isEmpty)
        #expect(page.firstDay == page.lastDay)
        #expect(AgentUsageScreen.caption(page) == AgentLimitWording.dayRange(from: page.firstDay, to: page.lastDay))
    }

    // MARK: - The reset names its day

    /// Hours before the reset, and how it is named. On the Monday the week began, "on Monday" would read as today: the
    /// date says it.
    nonisolated static let distances: [(hoursBefore: Double, expected: AgentLimitWording.Distance)] = [(0, .today), (20, .tomorrow), (96, .weekday),
                                                                                          (132, .weekday), (156, .date), (192, .date)]

    @Test(arguments: distances)
    func theResetIsNamedByDistance(hoursBefore: Double, expected: AgentLimitWording.Distance) {
        let resetsAt = Self.weekStart.addingTimeInterval(7 * Self.day) // Monday 16 Nov, 00:00 UTC
        let now = resetsAt.addingTimeInterval(-hoursBefore * 3600)
        #expect(AgentLimitWording.distance(of: resetsAt, from: now, calendar: Self.utc) == expected)
    }

    @Test
    func theResetLineSaysTheWeekdayAndTime() {
        let resetsAt = Self.weekStart.addingTimeInterval(7 * Self.day)
        let thursday = Self.weekStart.addingTimeInterval(3.5 * Self.day)
        let sunday = resetsAt.addingTimeInterval(-12 * 3600)
        let time = AgentLimitWording.time(resetsAt, calendar: Self.utc)
        let date = AgentLimitWording.date(resetsAt, calendar: Self.utc)

        #expect(AgentLimitWording.resetLine(resetsAt, now: thursday, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageResetsOnWeekday(UntranslatedL10n.screenAgentUsageOnMonday, time))
        #expect(AgentLimitWording.resetLine(resetsAt, now: sunday, calendar: Self.utc) == UntranslatedL10n.screenAgentUsageResetsTomorrow(time))
        #expect(AgentLimitWording.aiBackLine(resetsAt, now: thursday, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageAiBackOn(UntranslatedL10n.screenAgentUsageOnMonday, date, time))
        #expect(AgentLimitWording.aiBackLine(resetsAt, now: sunday, calendar: Self.utc) == UntranslatedL10n.screenAgentUsageAiBackTomorrow(time))
    }

    /// Monday 00:00 UTC is still Sunday evening west of Greenwich: the weekday is the person's own.
    @Test
    func theWeekdayIsTheLocalOne() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let resetsAt = Self.weekStart.addingTimeInterval(7 * Self.day)

        #expect(AgentLimitWording.onWeekday(resetsAt, calendar: newYork) == UntranslatedL10n.screenAgentUsageOnSunday)
        #expect(AgentLimitWording.untilWeekday(resetsAt, calendar: Self.utc) == UntranslatedL10n.screenAgentUsageUntilMonday)
    }

    // MARK: - Category pauses (decisions 14, 15)

    @Test
    func aPausedRowKeepsItsPlaceAndShowsEvenAtZero() {
        let monday = Self.weekStart.addingTimeInterval(7 * Self.day)
        let page = AgentLimitPage(usage: Self.usage(percent: 47, categories: [.init(category: .messages, usedPercent: 11),
                                                                              .init(category: .roomTools, usedPercent: 30, pause: .until(monday)),
                                                                              .init(category: .posts, usedPercent: 0, pause: .untilChanged),
                                                                              .init(category: .calls, usedPercent: 0)]))

        #expect(page.categories == [.init(category: .roomTools, usedPercent: 30, pause: .active(.until(monday))),
                                    .init(category: .messages, usedPercent: 11),
                                    .init(category: .posts, usedPercent: 0, pause: .active(.untilChanged))])
    }

    @Test
    func afterTheWholeLimitAnEarlierPauseStaysQuiet() {
        let monday = Self.weekStart.addingTimeInterval(7 * Self.day)
        let page = AgentLimitPage(usage: Self.usage(percent: 100, limitReached: true,
                                                    categories: [.init(category: .roomTools, usedPercent: 30, pause: .until(monday)),
                                                                 .init(category: .callTranslation, usedPercent: 70)]))

        #expect(page.status == .limitReached)
        #expect(page.categories.map(\.pause) == [nil, .earlier(.until(monday))])
    }

    /// The 85% hint is on the total only, and names the biggest category that has use, never a paused 0% one.
    @Test
    func theNearLimitHintNamesTheBiggestUsedCategory() {
        let page = AgentLimitPage(usage: Self.usage(percent: 90, categories: [.init(category: .posts, usedPercent: 0, pause: .untilChanged),
                                                                              .init(category: .calls, usedPercent: 60)]))
        #expect(page.status == .nearLimit(leftPercent: 10, biggest: .calls))
    }

    @Test
    func thePauseLineSaysUntilWhenInLocalTime() {
        let resetsAt = Self.weekStart.addingTimeInterval(7 * Self.day) // Monday 16 Nov, 00:00 UTC
        let thursday = Self.weekStart.addingTimeInterval(3.5 * Self.day)
        let time = AgentLimitWording.time(resetsAt, calendar: Self.utc)

        #expect(AgentLimitWording.pauseLine(.until(resetsAt), now: thursday, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsagePausedUntilWeekday(UntranslatedL10n.screenAgentUsageUntilMonday, time))
        #expect(AgentLimitWording.pauseLine(.until(resetsAt), now: resetsAt.addingTimeInterval(-12 * 3600), calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsagePausedUntilTomorrow(time))
        #expect(AgentLimitWording.pauseLine(.until(resetsAt), now: resetsAt.addingTimeInterval(-60), calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsagePausedUntilTomorrow(time))
        #expect(AgentLimitWording.pauseLine(.until(resetsAt.addingTimeInterval(9 * 3600)), now: resetsAt, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsagePausedUntilToday(AgentLimitWording.time(resetsAt.addingTimeInterval(9 * 3600), calendar: Self.utc)))
        #expect(AgentLimitWording.pauseLine(.until(resetsAt), now: Self.weekStart.addingTimeInterval(-3 * Self.day), calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsagePausedUntilDate(AgentLimitWording.date(resetsAt, calendar: Self.utc), time))
        #expect(AgentLimitWording.pauseLine(.untilChanged, now: thursday, calendar: Self.utc) == UntranslatedL10n.screenAgentUsagePaused)
    }

    @Test
    func theShortUntilNamesTheDayByDistance() {
        let resetsAt = Self.weekStart.addingTimeInterval(7 * Self.day)
        #expect(AgentLimitWording.until(resetsAt, now: Self.weekStart.addingTimeInterval(3.5 * Self.day), calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageUntilMonday)
        #expect(AgentLimitWording.until(resetsAt, now: resetsAt.addingTimeInterval(-3600), calendar: Self.utc) == UntranslatedL10n.screenAgentUsageUntilTomorrow)
        #expect(AgentLimitWording.until(resetsAt, now: resetsAt, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageUntilMoment(AgentLimitWording.time(resetsAt, calendar: Self.utc)))
    }

    /// The join check, the sheet and the notice card: the row's words after the category's name.
    @Test
    func aCategoryPauseNamesItsCategoryInTheRowsWords() {
        let monday = Self.weekStart.addingTimeInterval(7 * Self.day)
        let thursday = Self.weekStart.addingTimeInterval(3.5 * Self.day)
        let calls = UntranslatedL10n.screenAgentUsageCategoryCalls
        let time = AgentLimitWording.time(monday, calendar: Self.utc)

        #expect(AgentLimitWording.categoryPauseLine(.calls, .until(monday), now: thursday, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageCategoryPausedUntilWeekday(calls, UntranslatedL10n.screenAgentUsageUntilMonday, time))
        #expect(AgentLimitWording.categoryPauseLine(.calls, .untilChanged, now: thursday, calendar: Self.utc) == UntranslatedL10n.screenAgentUsageCategoryPaused(calls))
        #expect(AgentLimitWording.categoryPauseLine(.calls, nil, now: thursday, calendar: Self.utc) == UntranslatedL10n.screenAgentUsageCategoryPaused(calls))
        // A pause already over, on a card that stays in the timeline, names its date.
        #expect(AgentLimitWording.categoryPauseLine(.calls, .until(monday), now: monday.addingTimeInterval(3600), calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageCategoryPausedUntilDate(calls, AgentLimitWording.date(monday, calendar: Self.utc), time))
    }

    /// Unknown categories all read as other: one row, their shares added, a pause among them kept.
    @Test
    func sharesOfTheSameCategoryMergeIntoOneRow() {
        let merged = AgentUsage.CategoryShare.merged([.init(category: .other, usedPercent: 2),
                                                      .init(category: .calls, usedPercent: 5),
                                                      .init(category: .other, usedPercent: 3, pause: .untilChanged)])
        #expect(merged == [.init(category: .other, usedPercent: 5, pause: .untilChanged), .init(category: .calls, usedPercent: 5)])
    }

    /// A new agent's page lists no empty weeks before its first use.
    @Test
    func weeksWithoutUseBeforeTheFirstUsedOneAreLeftOut() {
        let percents: [Double] = [5, 5, 5, 5] + Array(repeating: 1, count: 7) + Array(repeating: 0, count: 19)
        let days = percents.enumerated().map { index, percent in
            AgentUsage.Day(id: "\(index)", date: Self.weekStart.addingTimeInterval(Self.day * Double(3 - index)), usedPercent: percent, categories: [])
        }
        #expect(AgentLimitPage(usage: Self.usage(percent: 20, categories: [], days: days)).pastWeeks.map(\.usedPercent) == [7])

        let unused = days.map { AgentUsage.Day(id: $0.id, date: $0.date, usedPercent: 0, categories: []) }
        #expect(AgentLimitPage(usage: Self.usage(percent: 0, categories: [], days: unused)).pastWeeks.isEmpty)
    }

    // MARK: - Helpers

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func usage(percent: Double,
                      limitReached: Bool = false,
                      startsAt: Date = weekStart,
                      categories: [AgentUsage.CategoryShare],
                      days: [AgentUsage.Day] = []) -> AgentUsage {
        AgentUsage(current: .init(period: .week,
                                  startsAt: startsAt,
                                  resetsAt: weekStart.addingTimeInterval(7 * day),
                                  usedPercent: percent,
                                  limitReached: limitReached,
                                  categories: categories),
                   days: days)
    }
}
