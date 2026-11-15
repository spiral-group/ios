//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403, L5 2.4): the agent's limit page as a page of the call's Assistants sheet,
// where "My limit" pushes it. The same view model and the same facts as the settings page, drawn in the call's glass:
// the call sheet's header (‹, ✕, one status line), glass blocks and rows instead of white cards on grey, blue only for
// an action, red only for the limit reached or a pause in force, and placeholders at the final size while it loads.

import Compound
import SpiralComponents
import SwiftUI

struct AgentUsageCallSheetPage: View {
    @Bindable var context: AgentUsageScreenViewModel.Context
    let now: () -> Date
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        NativeCallSheetPage {
            NativeCallSheetHeader(title: UntranslatedL10n.screenAgentUsageTitle,
                                  status: status,
                                  isLoading: context.viewState.loadState == .loading,
                                  onBack: onBack,
                                  onClose: onClose) { EmptyView() }
        } content: {
            switch context.viewState.loadState {
            case .loading:
                loading
            case .failure:
                NativeCallSheetNotice(systemImage: "exclamationmark.circle", title: UntranslatedL10n.screenAgentUsageLoadFailure, detail: nil)
                NativeCallSheetSecondaryButton(title: L10n.actionRetry) { context.send(viewAction: .retry) }
            case .loaded(let page):
                loaded(page)
            }
        }
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .animation(NativeCallAssistantsMotion.change, value: context.viewState.loadState)
    }

    /// The week the page is about: «Эта неделя · 9–15 ноября».
    private var status: String? {
        guard case .loaded(let page) = context.viewState.loadState else { return nil }
        return AgentUsageScreen.caption(page)
    }

    // MARK: Loaded

    @ViewBuilder
    private func loaded(_ page: AgentLimitPage) -> some View {
        weekBlock(page)
        if page.status != .limitReached {
            NativeCallSheetCaption(text: UntranslatedL10n.screenAgentUsageFooter)
        } else {
            NativeCallSheetSectionTitle(text: UntranslatedL10n.screenAgentUsageWorksSection)
            NativeCallSheetRow(icon: "bubble.left.and.bubble.right",
                               title: UntranslatedL10n.screenAgentUsageWorksChatsTitle,
                               detail: UntranslatedL10n.screenAgentUsageWorksChatsDetail)
            NativeCallSheetNotice(systemImage: "pause.fill",
                                  title: UntranslatedL10n.screenAgentUsageWorksAiPausedTitle,
                                  detail: UntranslatedL10n.screenAgentUsageWorksAiPausedDetail(AgentLimitWording.until(page.current.resetsAt, now: now())))
        }
        if !page.categories.isEmpty {
            NativeCallSheetSectionTitle(text: UntranslatedL10n.screenAgentUsageCategoriesSection)
            ForEach(page.categories) { row in
                AgentLimitCategoryRow(name: AgentLimitWording.categoryName(row.category),
                                      percent: row.usedPercent,
                                      pause: row.pause.map(pause),
                                      isInCallGlass: true)
                    .glassBlock()
            }
            if page.categories.contains(where: { $0.pause.map(pause)?.isEarlier == false }), page.status != .limitReached {
                NativeCallSheetCaption(text: UntranslatedL10n.screenAgentUsagePausedFooter)
            }
        }
        if page.current.period == .week, !page.pastWeeks.isEmpty {
            NativeCallSheetSectionTitle(text: UntranslatedL10n.screenAgentUsagePastWeeksSection)
            ForEach(page.pastWeeks) { week in
                NativeCallSheetRow(icon: nil,
                                   title: AgentLimitWording.dayRange(from: week.firstDay, to: week.lastDay),
                                   detail: week.limitUsedUpOn.map { UntranslatedL10n.screenAgentUsageWeekLimitUsedUp(AgentLimitWording.onWeekday($0, calendar: .utcWeeks)) },
                                   value: AgentLimitWording.percent(week.usedPercent))
            }
        }
    }

    /// The week: the share used, or that the limit is used up (red: the problem), the bar, and when it comes back.
    private func weekBlock(_ page: AgentLimitPage) -> some View {
        let current = page.current
        let reached = page.status == .limitReached
        return VStack(alignment: .leading, spacing: 12) {
            if reached {
                Text(current.period == .week ? UntranslatedL10n.screenAgentUsageLimitUsedUpThisWeek : UntranslatedL10n.screenAgentUsageLimitUsedUp)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textCriticalPrimary)
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

            AgentLimitBar(percent: current.usedPercent, height: 8,
                          fill: reached ? .compound.iconCriticalPrimary : .compound.iconPrimary)

            Text(reached ? AgentLimitWording.aiBackLine(current.resetsAt, now: now()) : AgentLimitWording.resetLine(current.resetsAt, now: now()))
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)

            if case let .nearLimit(left, biggest) = page.status {
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
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space4X)
        .nativeCallSurface(in: RoundedRectangle(cornerRadius: NativeCallSheetMetrics.rowHeight / 2, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.agentUsageScreen.week)
    }

    private func pause(_ pauseLine: AgentLimitPage.CategoryRow.PauseLine) -> AgentLimitCategoryRow.Pause {
        switch pauseLine {
        case .active(let pause): .init(line: AgentLimitWording.pauseLine(pause, now: now()), isEarlier: false)
        case .earlier(let pause): .init(line: AgentLimitWording.pauseLine(pause, now: now()), isEarlier: true)
        }
    }

    // MARK: Loading

    /// The week's block and three rows, at their final size (loading rule).
    @ViewBuilder
    private var loading: some View {
        weekBlock(AgentUsageScreen.placeholderPage)
            .spiralLoadingSlot(true, label: L10n.commonLoading)
        NativeCallSheetSectionTitle(text: UntranslatedL10n.screenAgentUsageCategoriesSection)
            .spiralLoadingSlot(true, label: L10n.commonLoading)
            .accessibilityHidden(true)
        ForEach(0..<3, id: \.self) { _ in
            NativeCallSheetPlaceholderRow()
                .accessibilityHidden(true) // The week's block reads "Loading…" for the page.
        }
    }
}

private extension View {
    /// A block of the page on the call's glass, a row's radius.
    func glassBlock() -> some View {
        nativeCallSurface(in: RoundedRectangle(cornerRadius: NativeCallSheetMetrics.rowHeight / 2, style: .continuous))
    }
}

// MARK: - Previews

/// Not a snapshot preview yet: the redesign records its references once, at its end stage (decision 324).
struct AgentUsageCallSheetPage_Previews: PreviewProvider {
    static var previews: some View {
        page(AgentUsageScreen_Previews.normalViewModel, "Normal")
        page(AgentUsageScreen_Previews.limitViewModel, "Limit reached")
        page(AgentUsageScreen_Previews.pausedViewModel, "Category paused")
        page(AgentUsageScreen_Previews.loadingViewModel, "Loading")
            .environment(\.spiralPreloaderDelay, .zero)
    }

    private static func page(_ viewModel: AgentUsageScreenViewModel, _ name: String) -> some View {
        AgentUsageScreen(context: viewModel.context, presentation: .callSheet(onBack: { }, onClose: { })) { AgentUsageScreen_Previews.now }
            .previewDisplayName(name)
    }
}
