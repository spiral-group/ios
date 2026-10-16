//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its daily limit (Brief 0079 3c).
//

import Compound
import SwiftUI

/// Shares of the agent's daily AI limit — today with its reset time, then
/// the last 30 days by category. No money: the limit is the platform's
/// cost cap, not a price the person pays (operator decision 6).
struct AgentUsageScreen: View {
    @Bindable var context: AgentUsageScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.loadState {
            case .loading:
                loadingSection
            case .failure:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentUsageLoadFailure) {
                    context.send(viewAction: .retry)
                }
            case .loaded(let usage):
                todaySection(usage.today)
                    .accessibilityIdentifier(A11yIdentifiers.agentUsageScreen.today)
                daysSection(usage.days)
            }
        }
        .compoundList()
        .refreshable { context.send(viewAction: .refresh) }
        .navigationTitle(UntranslatedL10n.screenAgentUsageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }

    // MARK: Today

    private func todaySection(_ today: AgentUsage.Today) -> some View {
        Section {
            ListRow(kind: .custom {
                VStack(alignment: .leading, spacing: 8) {
                    Text(UntranslatedL10n.screenAgentUsageTodayPercent(Self.percent(today.usedPercent)))
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)

                    ProgressView(value: min(max(today.usedPercent, 0), 100), total: 100)
                        .tint(today.limitReached ? .compound.iconCriticalPrimary : .compound.iconAccentPrimary)
                        .accessibilityHidden(true)

                    Text(Self.resetLine(for: today))
                        .font(.compound.bodyMD)
                        .foregroundStyle(today.limitReached ? .compound.textCriticalPrimary : .compound.textSecondary)
                }
                .padding(ListRowPadding.insets)
                .accessibilityElement(children: .combine)
            })
        } header: {
            Text(UntranslatedL10n.screenAgentUsageTodaySection)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenAgentUsageFooter)
                .compoundListSectionFooter()
        }
    }

    // MARK: Last 30 days

    @ViewBuilder
    private func daysSection(_ days: [AgentUsage.Day]) -> some View {
        // The server sends today first: position names the recent days.
        let used = days.enumerated().filter { $0.element.usedPercent > 0 }
        Section {
            if used.isEmpty {
                ListRow(kind: .custom {
                    Text(UntranslatedL10n.screenAgentUsageDaysEmpty)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .padding(ListRowPadding.insets)
                })
            } else {
                ForEach(used, id: \.element.id) { index, day in
                    ListRow(label: .plain(title: Self.dayTitle(day, daysAgo: index),
                                          description: Self.categoriesLine(day.categories)),
                            details: .title(Self.percent(day.usedPercent)),
                            kind: .label)
                }
            }
        } header: {
            Text(UntranslatedL10n.screenAgentUsageDaysSection)
                .compoundListSectionHeader()
        }
    }

    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                DelayedProgressView()
                    .frame(minHeight: 80)
            })
        }
        .listRowBackground(Color.clear)
    }

    // MARK: Formatting

    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }

    /// The day is a UTC day: format it in UTC, or a person west of
    /// Greenwich would see the day before.
    /// When today's share resets, naming the day when it isn't today: the
    /// limit resets at midnight UTC, which is tomorrow morning in Europe.
    static func resetLine(for today: AgentUsage.Today, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = today.resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
        if calendar.isDate(today.resetsAt, inSameDayAs: now) {
            return today.limitReached ? UntranslatedL10n.screenAgentUsageLimitReached(time) : UntranslatedL10n.screenAgentUsageResetsAt(time)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(today.resetsAt, inSameDayAs: tomorrow) {
            return today.limitReached ? UntranslatedL10n.screenAgentUsageLimitReachedTomorrow(time) : UntranslatedL10n.screenAgentUsageResetsTomorrowAt(time)
        }
        let dateTime = today.resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: calendar.timeZone))
        return today.limitReached ? UntranslatedL10n.screenAgentUsageLimitReached(dateTime) : UntranslatedL10n.screenAgentUsageResetsAt(dateTime)
    }
    
    static func dayTitle(_ day: AgentUsage.Day, daysAgo: Int) -> String {
        switch daysAgo {
        case 0:
            return UntranslatedL10n.screenAgentUsageToday
        case 1:
            return UntranslatedL10n.screenAgentUsageYesterday
        default:
            var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            style.timeZone = .gmt
            return day.date.formatted(style)
        }
    }

    static func categoriesLine(_ categories: [AgentUsage.CategoryShare]) -> String {
        categories
            .map { "\(categoryName($0.category)) \(percent($0.usedPercent))" }
            .joined(separator: " · ")
    }

    static func categoryName(_ category: AgentUsage.Category) -> String {
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
}

// MARK: - Previews

struct AgentUsageScreen_Previews: PreviewProvider, TestablePreview {
    static let usedViewModel = makeViewModel(.success(usage(todayPercent: 35, limitReached: false)))
    static let limitViewModel = makeViewModel(.success(usage(todayPercent: 104.5, limitReached: true)))
    static let emptyViewModel = makeViewModel(.success(noUse))
    static let failureViewModel = makeViewModel(.failure(.notFound))

    static var previews: some View {
        ElementNavigationStack {
            AgentUsageScreen(context: usedViewModel.context)
        }
        .previewDisplayName("Used")
        .snapshotPreferences(expect: usedViewModel.context.observe(\.viewState.loadState).map { $0 != .loading })

        ElementNavigationStack {
            AgentUsageScreen(context: limitViewModel.context)
        }
        .previewDisplayName("Limit reached")
        .snapshotPreferences(expect: limitViewModel.context.observe(\.viewState.loadState).map { $0 != .loading })

        ElementNavigationStack {
            AgentUsageScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("No use")
        .snapshotPreferences(expect: emptyViewModel.context.observe(\.viewState.loadState).map { $0 != .loading })

        ElementNavigationStack {
            AgentUsageScreen(context: failureViewModel.context)
        }
        .previewDisplayName("Failure")
        .snapshotPreferences(expect: failureViewModel.context.observe(\.viewState.loadState).map { $0 != .loading })
    }

    static let resetsAt = Date(timeIntervalSince1970: 1_791_676_800) // 2026-10-11 00:00 UTC

    static func days(percents: [Double]) -> [AgentUsage.Day] {
        percents.enumerated().map { index, percent in
            let date = resetsAt.addingTimeInterval(-86400 * Double(index + 1))
            let categories: [AgentUsage.CategoryShare] = percent > 0
                ? [.init(category: .calls, usedPercent: (percent * 0.7).rounded()),
                   .init(category: .messages, usedPercent: (percent * 0.3).rounded())]
                : []
            return .init(id: date.formatted(.iso8601.year().month().day()),
                         date: date,
                         usedPercent: percent,
                         categories: categories)
        }
    }

    static let noUse = AgentUsage(today: .init(usedPercent: 0, limitReached: false, resetsAt: resetsAt),
                                  days: days(percents: Array(repeating: 0, count: 30)))

    static func usage(todayPercent: Double, limitReached: Bool) -> AgentUsage {
        var percents = Array(repeating: 0.0, count: 30)
        percents[0] = todayPercent
        percents[1] = 12
        percents[4] = 61.5
        return .init(today: .init(usedPercent: todayPercent, limitReached: limitReached, resetsAt: resetsAt),
                     days: days(percents: percents))
    }

    static func makeViewModel(_ result: Result<AgentUsage, AgentPlatformError>) -> AgentUsageScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = result
        return AgentUsageScreenViewModel(agentID: "agent-1", agentPlatformService: service)
    }
}
