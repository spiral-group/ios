//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its daily limit (Brief 0079 3c).
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct AgentUsageScreenViewModelTests {
    static let resetsAt = Date(timeIntervalSince1970: 1_791_676_800) // 2026-10-11 00:00 UTC

    static let usage = AgentUsage(today: .init(usedPercent: 35, limitReached: false, resetsAt: resetsAt),
                                  days: [.init(id: "2026-10-10",
                                               date: resetsAt.addingTimeInterval(-86400),
                                               usedPercent: 35,
                                               categories: [.init(category: .calls, usedPercent: 25),
                                                            .init(category: .messages, usedPercent: 10)])])

    @Test
    func loadsTheAgentsUsage() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", agentPlatformService: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.usage) }
        try await deferred.fulfill()

        #expect(service.fetchAgentUsageAgentIDReceivedAgentID == "agent-1")
    }

    @Test
    func aFailedLoadOffersARetryThatLoads() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .failure(.notFound)

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", agentPlatformService: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .failure }
        try await failed.fulfill()

        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.usage) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }

    @Test
    func aFailedRefreshKeepsTheShownUsage() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)

        let viewModel = AgentUsageScreenViewModel(agentID: "agent-1", agentPlatformService: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.usage) }
        try await loaded.fulfill()

        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 503))
        viewModel.context.send(viewAction: .refresh)
        try await Task.sleep(for: .milliseconds(50))

        #expect(service.fetchAgentUsageAgentIDCallsCount == 2)
        #expect(viewModel.context.viewState.loadState == .loaded(Self.usage))
    }

    @Test
    func anUnknownCategoryReadsAsOther() {
        #expect(AgentUsage.Category(serverValue: "room_tools") == .roomTools)
        #expect(AgentUsage.Category(serverValue: "something_new") == .other)
    }

    @Test
    func recentDaysAreNamedAndOlderOnesAreDatedInUTC() {
        let day = AgentUsage.Day(id: "2026-10-03",
                                 date: Self.resetsAt.addingTimeInterval(-86400 * 8),
                                 usedPercent: 10,
                                 categories: [])
        #expect(AgentUsageScreen.dayTitle(day, daysAgo: 0) == UntranslatedL10n.screenAgentUsageToday)
        #expect(AgentUsageScreen.dayTitle(day, daysAgo: 1) == UntranslatedL10n.screenAgentUsageYesterday)
        // Midnight UTC on 3 Oct stays 3 Oct west of Greenwich.
        #expect(AgentUsageScreen.dayTitle(day, daysAgo: 7).contains("3"))
    }

    @Test
    func categoriesReadAsOneLine() {
        let line = AgentUsageScreen.categoriesLine([.init(category: .calls, usedPercent: 25),
                                                    .init(category: .messages, usedPercent: 10.5)])
        #expect(line == "\(UntranslatedL10n.screenAgentUsageCategoryCalls) 25% · \(UntranslatedL10n.screenAgentUsageCategoryMessages) 10.5%")
    }
    
    // MARK: - The reset names its day
    
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    
    @Test
    func aResetTomorrowSaysTomorrow() {
        let now = Date(timeIntervalSince1970: 1_791_633_600) // 2026-10-10 12:00 UTC
        let resetsAt = Date(timeIntervalSince1970: 1_791_676_800) // 2026-10-11 00:00 UTC
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Self.utc.timeZone))
        
        #expect(AgentUsageScreen.resetLine(for: .init(usedPercent: 10, limitReached: false, resetsAt: resetsAt), now: now, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageResetsTomorrowAt(time))
        #expect(AgentUsageScreen.resetLine(for: .init(usedPercent: 101, limitReached: true, resetsAt: resetsAt), now: now, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageLimitReachedTomorrow(time))
    }
    
    @Test
    func aResetLaterTodayNamesOnlyTheTime() {
        let now = Date(timeIntervalSince1970: 1_791_676_800 - 3600) // 2026-10-10 23:00 UTC
        let resetsAt = Date(timeIntervalSince1970: 1_791_676_800 - 60) // 23:59 the same UTC day
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: Self.utc.timeZone))
        #expect(AgentUsageScreen.resetLine(for: .init(usedPercent: 10, limitReached: false, resetsAt: resetsAt), now: now, calendar: Self.utc)
            == UntranslatedL10n.screenAgentUsageResetsAt(time))
    }
}
