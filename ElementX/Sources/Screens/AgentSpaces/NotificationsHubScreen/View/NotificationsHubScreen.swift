//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreen.swift`.

import Compound
import SpiralComponents
import SwiftUI

struct NotificationsHubScreen: View {
    @Bindable var context: NotificationsHubScreenViewModel.Context
    /// Pinned in snapshots (`EnvironmentValues.relativeTimeAnchor`); the clock otherwise.
    @Environment(\.relativeTimeAnchor) private var timeAnchor

    var body: some View {
        // The times are relative («5 мин назад»), so they are read again while the hub is open.
        SwiftUI.TimelineView(AgentRelativeTime.refreshSchedule) { timeline in
            Form {
                if context.viewState.isNeedsActionFailed {
                    AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenNotificationsHubNeedsActionLoadFailure) {
                        context.send(viewAction: .retry)
                    }
                }
                if context.viewState.isEmpty {
                    emptySection
                } else {
                    if !context.viewState.needsAction.isEmpty {
                        needsActionSection(context.viewState.needsAction, now: timeAnchor ?? timeline.date)
                    }
                    if !context.viewState.visitorMessages.isEmpty {
                        visitorMessagesSection(context.viewState.visitorMessages, now: timeAnchor ?? timeline.date)
                    }
                    activityContent(now: timeAnchor ?? timeline.date)
                }
            }
            .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        }
        .navigationTitle(UntranslatedL10n.screenNotificationsHubTitle)
        .navigationBarTitleDisplayMode(.inline)
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Needs action (pinned)

    private func needsActionSection(_ items: [NeedsActionListItem], now: Date) -> some View {
        Section {
            ForEach(items) { item in
                ListRow(kind: .custom {
                    Button {
                        context.send(viewAction: .selectNeedsAction(id: item.id))
                    } label: {
                        needsActionRow(item, now: now)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.notificationsHubScreen.item(item.subjectID)) // AGENT-PLATFORM (decision 148)
                })
            }
        } header: {
            Text(UntranslatedL10n.screenNotificationsHubNeedsActionSection)
                .compoundListSectionHeader()
        }
    }

    /// Brief 0083 (P4-D): as a mail row, the kind as the title with the time beside it, then the agent and the
    /// draft; the accent chip is gone.
    private func needsActionRow(_ item: NeedsActionListItem, now: Date) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                Text(Self.kindLabel(item.kind))
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Spacer(minLength: 0)
                Text(relativeDate(item.createdAt, now: now))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            }

            if let agentName = item.agentName {
                Text(agentName)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }

            Text(item.preview)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, ListRowPadding.horizontal)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - People the assistants don't answer

    private func visitorMessagesSection(_ items: [VisitorMessageListItem], now: Date) -> some View {
        Section {
            ForEach(items) { item in
                ListRow(kind: .custom {
                    Button {
                        context.send(viewAction: .selectVisitorMessage(id: item.id))
                    } label: {
                        visitorMessageRow(item, now: now)
                    }
                })
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(UntranslatedL10n.actionDismissVisitorMessage, role: .destructive) {
                        context.send(viewAction: .dismissVisitorMessage(id: item.id))
                    }
                }
                .contextMenu {
                    Button(UntranslatedL10n.actionDismissVisitorMessage, role: .destructive) {
                        context.send(viewAction: .dismissVisitorMessage(id: item.id))
                    }
                }
            }
        } header: {
            Text(UntranslatedL10n.screenNotificationsHubVisitorsSection)
                .compoundListSectionHeader()
        }
    }

    private func visitorMessageRow(_ item: VisitorMessageListItem, now: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CompoundIcon(item.kind == .missedCall ? \.voiceCall : \.chat, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(item.kind == .missedCall ? .compound.iconCriticalPrimary : .compound.iconSecondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.compound.bodyMDSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(relativeDate(item.createdAt, now: now))
                        .font(.compound.bodyXS)
                        .foregroundStyle(.compound.textSecondary)
                }
                Text(item.visitorName)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
                if let body = item.body {
                    Text(body)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                if let agentName = item.agentName {
                    Text(agentName)
                        .font(.compound.bodyXS)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Activity feed

    @ViewBuilder
    private func activityContent(now: Date) -> some View {
        switch context.viewState.activityState {
        case .loading where context.viewState.isNeedsActionFailed:
            // The read that failed brings the activity too: no empty card under its error while it's out.
            EmptyView()
        case .loading:
            // Decision 330: the activity's rows as placeholders, after a short delay.
            Section {
                ListRow(kind: .custom {
                    SpiralPreloader(label: L10n.commonLoading) {
                        SpiralPlaceholderRows(count: 3, leading: .icon)
                    }
                })
            }
        case .loaded(let items, _) where !items.isEmpty:
            activitySection(items, now: now)
            if let sentinel = context.viewState.sentinel {
                sentinelSection(sentinel)
            }
        case .loaded:
            EmptyView()
        case .failed:
            AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenNotificationsHubLoadFailed) {
                context.send(viewAction: .retry)
            }
        }
    }

    private func activitySection(_ items: [AgentActivityListItem], now: Date) -> some View {
        Section {
            ForEach(items) { item in
                // Same row anatomy as AgentActivityScreen (canon F5):
                // trailing outcome from the shared filter vocabulary.
                ListRow(label: .default(title: item.title,
                                        description: AgentActivityScreen.rowDescription(for: item, now: now),
                                        icon: AgentActivityScreen.icon(for: item)),
                        details: .title(AgentActivityScreen.outcomeLabel(for: item)),
                        kind: .label)
                    .accessibilityIdentifier(A11yIdentifiers.notificationsHubScreen.activity(item.id)) // AGENT-PLATFORM (decision 148)
            }
        } header: {
            Text(UntranslatedL10n.screenNotificationsHubActivitySection)
                .compoundListSectionHeader()
        }
    }

    private func sentinelSection(_ state: LoadMoreState) -> some View {
        Section {
            switch state {
            case .idle:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UntranslatedL10n.screenAgentActivityLoadMore)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .onAppear { context.send(viewAction: .loadMore) }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UntranslatedL10n.screenAgentActivityLoadMore)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            case .failed:
                Button {
                    context.send(viewAction: .loadMore)
                } label: {
                    HStack(spacing: 8) {
                        CompoundIcon(\.errorSolid, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconCriticalPrimary)
                        Text(UntranslatedL10n.screenAgentActivityLoadMoreFailed)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)
            case .exhausted:
                EmptyView()
            }
        }
    }

    // MARK: - Empty state

    private var emptySection: some View {
        Section {
            SpiralEmptyState(symbol: .bell,
                             title: UntranslatedL10n.screenNotificationsHubEmptyTitle,
                             message: UntranslatedL10n.screenNotificationsHubEmptySubtitle)
                .listRowBackground(Color.clear)
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date, now: Date) -> String {
        AgentRelativeTime.string(for: date, now: now)
    }

    static func kindLabel(_ kind: NeedsActionListItem.Kind) -> String {
        switch kind {
        case .approval: UntranslatedL10n.screenNotificationsHubKindApproval
        case .verification: UntranslatedL10n.screenNotificationsHubKindVerification
        }
    }
}

// MARK: - Previews

struct NotificationsHubScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let emptyViewModel = makeViewModel(needsAction: [], activity: [])
    static let contentViewModel = makeViewModel(needsAction: sampleNeedsAction, activity: sampleActivity)
    static let activityOnlyViewModel = makeViewModel(needsAction: [], activity: sampleActivity)
    static let errorViewModel = makeViewModel(needsAction: [], activity: [], failsActivity: true)
    static let needsActionFailedViewModel = makeViewModel(needsAction: [], activity: [], failsNeedsAction: true)
    static let visitorsViewModel = makeViewModel(needsAction: [], activity: [], visitorMessages: sampleVisitorMessages)

    static var previews: some View {
        // The activity feed loads on appear; snapshots wait for it so they
        // never catch the (delayed, invisible) spinner as an empty section.
        ElementNavigationStack {
            NotificationsHubScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: emptyViewModel.context.observe(\.viewState.isReadForPreview))
        .previewDisplayName("Empty")

        ElementNavigationStack {
            NotificationsHubScreen(context: contentViewModel.context)
        }
        .snapshotPreferences(expect: contentViewModel.context.observe(\.viewState.isReadForPreview))
        .previewDisplayName("Content")

        ElementNavigationStack {
            NotificationsHubScreen(context: activityOnlyViewModel.context)
        }
        .snapshotPreferences(expect: activityOnlyViewModel.context.observe(\.viewState.isReadForPreview))
        .previewDisplayName("Activity only")

        ElementNavigationStack {
            NotificationsHubScreen(context: errorViewModel.context)
        }
        .snapshotPreferences(expect: errorViewModel.context.observe(\.viewState.isReadForPreview))
        .previewDisplayName("Error")

        ElementNavigationStack {
            NotificationsHubScreen(context: needsActionFailedViewModel.context)
        }
        .snapshotPreferences(expect: needsActionFailedViewModel.context.observe(\.viewState.isNeedsActionFailed))
        .previewDisplayName("Needs action failed")

        ElementNavigationStack {
            NotificationsHubScreen(context: visitorsViewModel.context)
        }
        .snapshotPreferences(expect: visitorsViewModel.context.observe(\.viewState.isReadForPreview))
        .previewDisplayName("People")
    }

    // The hub reads "now" from a 30 s TimelineView schedule that started
    // before these dates were made, so its "now" lags theirs by up to 30 s.
    // Each offset sits 30 s into its unit (5 min 30 s, not 5 min), so the
    // relative time shown survives that lag or a 30 s render delay.
    static let sampleVisitorMessages: [VisitorMessage] = [
        VisitorMessage(id: "visitor-1", kind: .message, agentID: "agent-1", visitorMXID: "@bob:spiral.md", roomID: "!bob:spiral.md",
                       body: "Hi Anna, are we still on for Friday? I can bring the slides.", createdAt: PreviewClock.now.addingTimeInterval(-630)),
        VisitorMessage(id: "visitor-2", kind: .missedCall, agentID: "agent-1", visitorMXID: "@carol:example.org", roomID: "!carol:spiral.md",
                       body: "", createdAt: PreviewClock.now.addingTimeInterval(-7230))
    ]

    static let sampleNeedsAction: [NeedsActionItem] = [
        .approval(ApprovalSummary(id: "approval-1",
                                  agentID: "agent-1",
                                  draftBody: "Hi Bob — thanks for reaching out! Alice is away today; can I take a message?",
                                  targetRoomID: "!visitor:spiral.md",
                                  createdAt: PreviewClock.now.addingTimeInterval(-330))),
        .verification(VerificationSummary(id: "verification-1",
                                          requesterUserID: "@alice:spiral.md",
                                          requesterDeviceID: "IPHONE15",
                                          state: .pendingOwner,
                                          createdAt: PreviewClock.now.addingTimeInterval(-930),
                                          deadlineAt: PreviewClock.now.addingTimeInterval(600)))
    ]

    static let sampleActivity: [AgentActivityEntry] = [
        AgentActivityEntry(id: "row-1",
                           agentID: "agent-1",
                           roomID: "!example1:spiral.md",
                           capabilityName: "messenger.reply_in_room",
                           inputRedacted: [:],
                           reasoningSummary: "Replied directly: relationship is approved + visitor is known to owner.",
                           policyDecision: .allowedDirect,
                           policyReason: "relationship_approved",
                           approvalID: nil,
                           longFlowID: nil,
                           outcome: .executed,
                           outcomeEventID: "$ev1",
                           createdAt: PreviewClock.now.addingTimeInterval(-3630),
                           resolvedAt: PreviewClock.now.addingTimeInterval(-3620)),
        AgentActivityEntry(id: "row-2",
                           agentID: "agent-1",
                           roomID: "!example2:spiral.md",
                           capabilityName: "messenger.reply_in_room",
                           inputRedacted: [:],
                           reasoningSummary: "Visitor is on the blocked list; reply suppressed.",
                           policyDecision: .denied,
                           policyReason: "blocked_visitor",
                           approvalID: nil,
                           longFlowID: nil,
                           outcome: .denied,
                           outcomeEventID: nil,
                           createdAt: PreviewClock.now.addingTimeInterval(-86430),
                           resolvedAt: PreviewClock.now.addingTimeInterval(-86430))
    ]

    static func makeViewModel(needsAction: [NeedsActionItem],
                              activity: [AgentActivityEntry],
                              failsActivity: Bool = false,
                              failsNeedsAction: Bool = false,
                              visitorMessages: [VisitorMessage] = []) -> NotificationsHubScreenViewModel {
        let platformService = AgentPlatformServiceMock()
        // What waits is read with a page of one; the activity with a page of its own.
        platformService.fetchNotificationsActivityCursorLimitClosure = { _, limit in
            if failsActivity, limit > 1 {
                return .failure(.serverError(status: 500))
            }
            if failsNeedsAction {
                // What waits fails; the activity's read, which would bring it too, is still out.
                if limit > 1 {
                    try? await Task.sleep(for: .seconds(60))
                }
                return .failure(.serverError(status: 500))
            }
            return .success(.init(needsAction: needsAction,
                                  activity: activity,
                                  nextActivityCursor: nil,
                                  lastSeenAt: nil,
                                  unseenCount: 0,
                                  visitorMessages: visitorMessages))
        }
        platformService.markNotificationsSeenReturnValue = .success(Date())
        platformService.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "org-personal", name: "Personal", kind: .solo,
                                                                                     avatarMXC: nil, agentCount: 1)],
                                                                      provisioningStatus: .ready))
        platformService.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-personal", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                         industry: nil, website: nil,
                                                                         agents: [.init(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                                                        displayName: "Anna's assistant", avatarMXC: nil,
                                                                                        kind: "personal_assistant", visibility: "public",
                                                                                        lifecycleState: "active", roomCount: 1, activeToolCount: 0)]))

        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { $0 == "!example1:spiral.md" ? .mock(id: $0, name: "Book club") : nil }
        clientProxy.profileForClosure = { userID in
            userID == "@bob:spiral.md" ? .success(.init(userID: userID, displayName: "Bob")) : .failure(.sdkError(ClientProxyMockError.generic))
        }
        return NotificationsHubScreenViewModel(store: AgentsStore(service: platformService),
                                               agentPlatformService: platformService,
                                               clientProxy: clientProxy,
                                               userIndicatorController: UserIndicatorControllerMock())
    }
}

private extension NotificationsHubScreenViewState {
    /// The activity, what waits and the agents' names are read on their own: the snapshot waits for all three.
    var isReadForPreview: Bool {
        if case .loading = activityState { return false }
        return isNeedsActionRead && areAgentNamesRead
    }
}
