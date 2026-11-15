//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the agent's AI use against its weekly limit (Brief 0079 3c, question 394).
//

import Compound
import SpiralComponents
import SwiftUI

/// Shares of the agent's AI limit (concept A of `DESIGNS/spiral-limit-page.png`): the week's card, where it went and
/// the past weeks. No money: the limit is the platform's cost cap, not a price the person pays (operator decision 6).
///
/// Brief 0085, question 403 (L5 2.4): pushed from a call's Assistants sheet ("My limit"), the same page is drawn in the
/// call's glass, as every page of that sheet is; in the agent's settings it stays a settings page.
struct AgentUsageScreen: View {
    /// Where the page is shown.
    enum Presentation {
        /// The agent's settings: a grouped list under the navigation bar.
        case settings
        /// A call's Assistants sheet: the call's glass, its header with ‹ and ✕.
        case callSheet(onBack: () -> Void, onClose: () -> Void)
    }

    @Bindable var context: AgentUsageScreenViewModel.Context
    var presentation = Presentation.settings
    /// Pinned by the previews: the reset line names its day by distance from now.
    var now: () -> Date = { .now }

    var body: some View {
        switch presentation {
        case .settings:
            settingsBody
        case .callSheet(let onBack, let onClose):
            AgentUsageCallSheetPage(context: context, now: now, onBack: onBack, onClose: onClose)
        }
    }

    private var settingsBody: some View {
        Form {
            switch context.viewState.loadState {
            case .loading:
                loadingSections
            case .failure:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentUsageLoadFailure) {
                    context.send(viewAction: .retry)
                }
            case .loaded(let page):
                weekSection(page)
                if page.status == .limitReached {
                    whatWorksSection(page.current)
                }
                if !page.categories.isEmpty {
                    categoriesSection(page.categories)
                }
                if page.current.period == .week, !page.pastWeeks.isEmpty {
                    pastWeeksSection(page.pastWeeks)
                }
            }
        }
        .compoundList()
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .navigationTitle(UntranslatedL10n.screenAgentUsageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }

    // MARK: The week

    private func weekSection(_ page: AgentLimitPage) -> some View {
        Section {
            ListRow(kind: .custom { weekCard(page) })
                .accessibilityIdentifier(A11yIdentifiers.agentUsageScreen.week)
        } footer: {
            // At the limit the "what still works" card says it.
            if page.status != .limitReached {
                Text(UntranslatedL10n.screenAgentUsageFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    private func weekCard(_ page: AgentLimitPage) -> some View {
        let current = page.current
        let reached = page.status == .limitReached
        return VStack(alignment: .leading, spacing: 12) {
            Text(Self.caption(page))
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)

            if reached {
                Text(current.period == .week ? UntranslatedL10n.screenAgentUsageLimitUsedUpThisWeek : UntranslatedL10n.screenAgentUsageLimitUsedUp)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgentLimitWording.percent(current.usedPercent))
                        .font(.compound.headingXLBold)
                        .foregroundStyle(.compound.textPrimary)
                    Text(current.period == .week ? UntranslatedL10n.screenAgentUsageOfWeeklyLimit : UntranslatedL10n.screenAgentUsageOfLimit)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textSecondary)
                }
            }

            AgentLimitBar(percent: current.usedPercent, height: 8)

            Text(reached ? AgentLimitWording.aiBackLine(current.resetsAt, now: now()) : AgentLimitWording.resetLine(current.resetsAt, now: now()))
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)

            if case let .nearLimit(left, biggest) = page.status {
                Divider()
                Label {
                    Text(AgentLimitWording.nearLimitLine(leftPercent: left, biggest: biggest, period: current.period))
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                } icon: {
                    CompoundIcon(\.info, size: .small, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ListRowPadding.insets)
        .accessibilityElement(children: .combine)
    }

    // MARK: At the limit

    private func whatWorksSection(_ current: AgentUsage.Current) -> some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenAgentUsageWorksChatsTitle,
                                    description: UntranslatedL10n.screenAgentUsageWorksChatsDetail,
                                    icon: \.chat),
                    kind: .label)
            let until = AgentLimitWording.until(current.resetsAt, now: now())
            ListRow(label: .default(title: UntranslatedL10n.screenAgentUsageWorksAiPausedTitle,
                                    description: UntranslatedL10n.screenAgentUsageWorksAiPausedDetail(until),
                                    icon: \.pause),
                    kind: .label)
        } header: {
            Text(UntranslatedL10n.screenAgentUsageWorksSection)
                .compoundListSectionHeader()
        }
    }

    // MARK: Where it went

    private func categoriesSection(_ rows: [AgentLimitPage.CategoryRow]) -> some View {
        Section {
            ForEach(rows) { row in
                ListRow(kind: .custom {
                    AgentLimitCategoryRow(name: AgentLimitWording.categoryName(row.category),
                                          percent: row.usedPercent,
                                          pause: row.pause.map { pauseRow($0) })
                })
            }
        } header: {
            Text(UntranslatedL10n.screenAgentUsageCategoriesSection)
                .compoundListSectionHeader()
        } footer: {
            // Only while a pause is the news: at the limit the card says what still works.
            if rows.contains(where: { $0.pause.map(pauseRow)?.isEarlier == false }) {
                Text(UntranslatedL10n.screenAgentUsagePausedFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    private func pauseRow(_ pauseLine: AgentLimitPage.CategoryRow.PauseLine) -> AgentLimitCategoryRow.Pause {
        switch pauseLine {
        case .active(let pause): .init(line: AgentLimitWording.pauseLine(pause, now: now()), isEarlier: false)
        case .earlier(let pause): .init(line: AgentLimitWording.pauseLine(pause, now: now()), isEarlier: true)
        }
    }

    // MARK: Past weeks

    private func pastWeeksSection(_ weeks: [AgentLimitPage.PastWeek]) -> some View {
        pastWeeksSection {
            ForEach(weeks) { week in
                pastWeekRow(title: AgentLimitWording.dayRange(from: week.firstDay, to: week.lastDay),
                            description: week.limitUsedUpOn.map { UntranslatedL10n.screenAgentUsageWeekLimitUsedUp(AgentLimitWording.onWeekday($0, calendar: .utcWeeks)) },
                            percent: AgentLimitWording.percent(week.usedPercent))
            }
        }
    }

    private func pastWeeksSection(@ViewBuilder rows: () -> some View) -> some View {
        Section {
            rows()
        } header: {
            Text(UntranslatedL10n.screenAgentUsagePastWeeksSection)
                .compoundListSectionHeader()
        }
    }

    private func pastWeekRow(title: String, description: String?, percent: String) -> some View {
        ListRow(label: .plain(title: title, description: description),
                details: .title(percent),
                kind: .label)
    }

    // MARK: Loading

    // AGENT-PLATFORM (Brief 0083, question 359): the week's card and three rows as placeholders, after a short delay
    // (decision 330).
    @ViewBuilder
    private var loadingSections: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    weekCard(Self.placeholderPage)
                }
            })
        }

        pastWeeksSection {
            ForEach(0..<3, id: \.self) { _ in
                SpiralPreloader(label: L10n.commonLoading) {
                    pastWeekRow(title: String(repeating: "0", count: 14), description: nil, percent: String(repeating: "0", count: 3))
                }
                .accessibilityHidden(true) // The card reads "Loading…" for the screen.
            }
        }
    }

    static var placeholderPage: AgentLimitPage {
        AgentLimitPage(usage: .init(current: .init(period: .week, startsAt: .now, resetsAt: .now, usedPercent: 0, limitReached: false, categories: []),
                                    days: []))
    }

    // MARK: Formatting

    /// «Эта неделя · 9–15 ноября»; a period without its own words shows its days alone.
    static func caption(_ page: AgentLimitPage) -> String {
        let days = AgentLimitWording.dayRange(from: page.firstDay, to: page.lastDay)
        return page.current.period == .week ? UntranslatedL10n.screenAgentUsageThisWeek(days) : days
    }

}

/// A category's name and share over a small bar. Text never sits inside the bar, and at accessibility sizes the share
/// moves under the name. A paused category has a grey bar and its pause line under it; after the whole limit is reached
/// the line stays, grey and without the icon (decision 15).
struct AgentLimitCategoryRow: View {
    struct Pause {
        let line: String
        let isEarlier: Bool
    }

    let name: String
    let percent: Double
    var pause: Pause?
    /// In a call's glass a pause in force is the one problem on the page: red, and the bar neutral (DESIGN.md).
    var isInCallGlass = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(name)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                Text(AgentLimitWording.percent(percent))
                    .font(.compound.bodyLG)
                    .monospacedDigit()
                    .foregroundStyle(.compound.textSecondary)
            }
            AgentLimitBar(percent: percent, height: 4, isPaused: pause.map { !$0.isEarlier } ?? false,
                          fill: isInCallGlass ? .compound.iconPrimary : .compound.iconAccentPrimary)

            if let pause {
                let isCritical = isInCallGlass && !pause.isEarlier
                // Not a Label: a list tints a Label's icon with the accent. Spiral has no warning hue; the glyph marks it.
                HStack(spacing: 6) {
                    if !pause.isEarlier {
                        CompoundIcon(\.pause, size: .xSmall, relativeTo: .compound.bodyMD)
                            .foregroundStyle(isCritical ? Color.compound.iconCriticalPrimary : .compound.iconSecondary)
                    }
                    Text(pause.line)
                        .font(.compound.bodyMD)
                        .foregroundStyle(isCritical ? Color.compound.textCriticalPrimary : .compound.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ListRowPadding.insets)
        .accessibilityElement(children: .combine)
    }
}

/// A share of the limit as a filled capsule; any use shows at least a dot. Decorative: the share is in the text.
struct AgentLimitBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let percent: Double
    let height: CGFloat
    /// A paused category's share no longer grows: grey, not the accent.
    var isPaused = false
    /// The fill where the share is not paused: the accent in settings; in a call's glass the neutral ink, as blue there
    /// is for actions only (DESIGN.md).
    var fill = Color.compound.iconAccentPrimary

    /// The empty part of the track. In light the subtle fill is the card's own white, so the track takes the tertiary grey.
    private var trackColor: Color {
        colorScheme == .light ? .compound.bgActionTertiarySelected : .compound.bgSubtlePrimary
    }

    var body: some View {
        Capsule()
            .fill(trackColor)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    let fraction = min(max(percent, 0), 100) / 100
                    Capsule()
                        .fill(isPaused ? Color.compound.iconTertiary : fill)
                        .frame(width: fraction > 0 ? max(height, proxy.size.width * fraction) : 0)
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

struct AgentUsageScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let normalViewModel = makeViewModel(.success(usage(percent: 34, categories: [.messages: 18, .roomTools: 7, .calls: 5, .callTranslation: 3, .posts: 1])))
    static let nearLimitViewModel = makeViewModel(.success(usage(percent: 85, categories: [.callTranslation: 38, .calls: 22, .messages: 17, .roomTools: 6, .posts: 2])))
    static let limitViewModel = makeViewModel(.success(usage(percent: 100, limitReached: true,
                                                             categories: [.callTranslation: 38, .messages: 30, .calls: 22, .roomTools: 8, .posts: 2])))
    static let pausedViewModel = makeViewModel(.success(usage(percent: 47, categories: [.roomTools: 30, .messages: 11, .calls: 4, .callTranslation: 2],
                                                              pauses: [.roomTools: .until(weekStart.addingTimeInterval(7 * 86400))])))
    static let pausedOffViewModel = makeViewModel(.success(usage(percent: 34, categories: [.messages: 18, .roomTools: 7, .calls: 5, .callTranslation: 3, .posts: 0],
                                                                 pauses: [.posts: .untilChanged])))
    static let pausedThenLimitViewModel = makeViewModel(.success(usage(percent: 100, limitReached: true,
                                                                       categories: [.roomTools: 30, .callTranslation: 28, .messages: 24, .calls: 16, .posts: 2],
                                                                       pauses: [.roomTools: .until(weekStart.addingTimeInterval(7 * 86400))])))
    static let noUseViewModel = makeViewModel(.success(usage(percent: 0, categories: [:], history: false)))
    static let failureViewModel = makeViewModel(.failure(.serverError(status: 500)))
    static let loadingViewModel = makeLoadingViewModel()

    static var previews: some View {
        screen(normalViewModel, "Normal")
        screen(nearLimitViewModel, "Near the limit")
        screen(limitViewModel, "Limit reached")
        screen(pausedViewModel, "Category paused")
        screen(pausedOffViewModel, "Category paused without a date")
        screen(pausedThenLimitViewModel, "Category paused, then the limit reached")
        screen(noUseViewModel, "No use")
        screen(failureViewModel, "Failure")

        ElementNavigationStack {
            AgentUsageScreen(context: loadingViewModel.context) { now }
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
    }

    private static func screen(_ viewModel: AgentUsageScreenViewModel, _ name: String) -> some View {
        ElementNavigationStack {
            AgentUsageScreen(context: viewModel.context) { now }
        }
        .previewDisplayName(name)
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.loadState).map { $0 != .loading })
    }

    /// Monday 9 November 2026, 00:00 UTC: the board's week.
    static let weekStart = Date(timeIntervalSince1970: 1_794_182_400)
    /// Thursday 12 November, midday.
    static let now = weekStart.addingTimeInterval(3 * 86400 + 12 * 3600)

    static func usage(percent: Double,
                      limitReached: Bool = false,
                      categories: [AgentUsage.Category: Double],
                      pauses: [AgentUsage.Category: AgentUsage.Pause] = [:],
                      history: Bool = true) -> AgentUsage {
        let shares = categories.map { AgentUsage.CategoryShare(category: $0.key, usedPercent: $0.value, pause: pauses[$0.key]) }
        // 30 days, newest first: this week's four, then three full weeks (61%, 100% used up on the Friday, 42%) and five days of a partial one.
        let pastPercents: [Double] = [9, 8, 9, 10, 8, 9, 8, 0, 0, 30, 30, 20, 10, 10, 6, 6, 6, 6, 6, 6, 6, 4, 2, 3, 0, 1]
        let days = (0..<30).map { index in
            let date = weekStart.addingTimeInterval(86400 * Double(3 - index))
            let used = !history ? 0 : index < 4 ? percent / 4 : pastPercents[index - 4]
            return AgentUsage.Day(id: date.formatted(.iso8601.year().month().day()), date: date, usedPercent: used, categories: [])
        }
        return AgentUsage(current: .init(period: .week,
                                         startsAt: weekStart,
                                         resetsAt: weekStart.addingTimeInterval(7 * 86400),
                                         usedPercent: percent,
                                         limitReached: limitReached,
                                         categories: shares),
                          days: days)
    }

    static func makeViewModel(_ result: Result<AgentUsage, AgentPlatformError>) -> AgentUsageScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchAgentUsageAgentIDReturnValue = result
        return AgentUsageScreenViewModel(agentID: "agent-1", store: AgentsStore(service: service))
    }

    static func makeLoadingViewModel() -> AgentUsageScreenViewModel {
        let service = AgentPlatformServiceMock()
        // The snapshot suites share this view model in one run, which can outlast a minute.
        service.fetchAgentUsageAgentIDClosure = { _ in
            try? await Task.sleep(for: .seconds(24 * 3600))
            return .failure(.serverError(status: 0))
        }
        return AgentUsageScreenViewModel(agentID: "agent-1", store: AgentsStore(service: service))
    }
}
