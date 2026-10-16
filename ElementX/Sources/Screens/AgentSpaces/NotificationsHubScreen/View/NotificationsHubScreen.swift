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
import SwiftUI

struct NotificationsHubScreen: View {
    @Bindable var context: NotificationsHubScreenViewModel.Context

    var body: some View {
        // The times are relative («5 мин назад»), so they are read again while the hub is open.
        SwiftUI.TimelineView(AgentRelativeTime.refreshSchedule) { timeline in
            Form {
                connectionSection

                if context.viewState.isEmpty {
                    emptySection
                } else {
                    if !context.viewState.needsAction.isEmpty {
                        needsActionSection(context.viewState.needsAction, now: timeline.date)
                    }
                    if !context.viewState.visitorMessages.isEmpty {
                        visitorMessagesSection(context.viewState.visitorMessages, now: timeline.date)
                    }
                    activityContent(now: timeline.date)
                }
            }
            .compoundList()
        }
        .navigationTitle(UntranslatedL10n.screenNotificationsHubTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .retry) }
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Connection banner

    @ViewBuilder
    private var connectionSection: some View {
        switch context.viewState.connectionIndicator {
        case .hidden:
            EmptyView()
        case .connecting:
            connectionBanner(title: UntranslatedL10n.screenApprovalsListConnectingTitle,
                             subtitle: UntranslatedL10n.screenNotificationsHubConnectingSubtitle,
                             showsSpinner: true,
                             isCritical: false)
        case .reconnecting(let attempt):
            connectionBanner(title: UntranslatedL10n.screenApprovalsListReconnectingTitle,
                             subtitle: UntranslatedL10n.screenApprovalsListReconnectingSubtitleAttempt(attempt),
                             showsSpinner: true,
                             isCritical: false)
        case .failed:
            connectionBanner(title: UntranslatedL10n.screenApprovalsListOfflineTitle,
                             subtitle: UntranslatedL10n.screenApprovalsListOfflineSubtitle,
                             showsSpinner: false,
                             isCritical: true)
        }
    }

    private func connectionBanner(title: String, subtitle: String, showsSpinner: Bool, isCritical: Bool) -> some View {
        Section {
            ListRow(kind: .custom {
                HStack(alignment: .top, spacing: 12) {
                    if showsSpinner {
                        ProgressView().controlSize(.small)
                    } else {
                        CompoundIcon(\.errorSolid,
                                     size: .small,
                                     relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconCriticalPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                        Text(subtitle)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The home screen's recovery banner anatomy: an inset card on
                // the list, not a tinted row.
                .background(isCritical
                    ? Color.compound.bgCriticalSubtle
                    : Color.compound.bgSubtleSecondary)
                .cornerRadius(14)
            })
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
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

    private func needsActionRow(_ item: NeedsActionListItem, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentStatusBadge(title: Self.kindLabel(item.kind), variant: .accent)
                if let agentName = item.agentName {
                    Text(agentName)
                        .font(.compound.bodyXSSemibold)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(relativeDate(item.createdAt, now: now))
                    .font(.compound.bodyXS)
                    .foregroundStyle(.compound.textSecondary)
            }

            Text(item.preview)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(.compound.bodyXS)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        case .loading:
            // Canon §3: fast/rare data → delayed spinner, never a skeleton.
            Section {
                ListRow(kind: .custom {
                    DelayedProgressView()
                        .frame(minHeight: 80)
                })
            }
            .listRowBackground(Color.clear)
        case .loaded(let items, _) where !items.isEmpty:
            activitySection(items, now: now)
            if let sentinel = context.viewState.sentinel {
                sentinelSection(sentinel)
            }
        case .loaded:
            EmptyView()
        case .failed:
            AgentSpacesRetryErrorSection {
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
            VStack(spacing: 24) {
                BigIcon(icon: \.notifications)
                VStack(spacing: 8) {
                    Text(UntranslatedL10n.screenNotificationsHubEmptyTitle)
                        .font(.compound.headingSMSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(UntranslatedL10n.screenNotificationsHubEmptySubtitle)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
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

struct NotificationsHubScreen_Previews: PreviewProvider, TestablePreview {
    static let emptyViewModel = makeViewModel(needsAction: [], activity: [])
    static let contentViewModel = makeViewModel(needsAction: sampleNeedsAction, activity: sampleActivity)
    static let activityOnlyViewModel = makeViewModel(needsAction: [], activity: sampleActivity)
    static let errorViewModel = makeViewModel(needsAction: [], activity: [], failsActivity: true)
    static let visitorsViewModel = makeViewModel(needsAction: [], activity: [], visitorMessages: sampleVisitorMessages)

    static var previews: some View {
        // The activity feed loads on appear; snapshots wait for it so they
        // never catch the (delayed, invisible) spinner as an empty section.
        ElementNavigationStack {
            NotificationsHubScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: emptyViewModel.context.observe(\.viewState.activityState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Empty")

        ElementNavigationStack {
            NotificationsHubScreen(context: contentViewModel.context)
        }
        .snapshotPreferences(expect: contentViewModel.context.observe(\.viewState.activityState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Content")

        ElementNavigationStack {
            NotificationsHubScreen(context: activityOnlyViewModel.context)
        }
        .snapshotPreferences(expect: activityOnlyViewModel.context.observe(\.viewState.activityState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Activity only")

        ElementNavigationStack {
            NotificationsHubScreen(context: errorViewModel.context)
        }
        .snapshotPreferences(expect: errorViewModel.context.observe(\.viewState.activityState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Error")

        ElementNavigationStack {
            NotificationsHubScreen(context: visitorsViewModel.context)
        }
        .snapshotPreferences(expect: visitorsViewModel.context.observe(\.viewState.activityState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("People")
    }

    static let sampleVisitorMessages: [VisitorMessage] = [
        VisitorMessage(id: "visitor-1", kind: .message, agentID: "agent-1", visitorMXID: "@bob:spiral.md", roomID: "!bob:spiral.md",
                       body: "Hi Anna, are we still on for Friday? I can bring the slides.", createdAt: Date(timeIntervalSinceNow: -600)),
        VisitorMessage(id: "visitor-2", kind: .missedCall, agentID: "agent-1", visitorMXID: "@carol:example.org", roomID: "!carol:spiral.md",
                       body: "", createdAt: Date(timeIntervalSinceNow: -7200))
    ]

    static let sampleNeedsAction: [NeedsActionItem] = [
        .approval(ApprovalSummary(id: "approval-1",
                                  agentID: "agent-1",
                                  draftBody: "Hi Bob — thanks for reaching out! Alice is away today; can I take a message?",
                                  targetRoomID: "!visitor:spiral.md",
                                  createdAt: Date(timeIntervalSinceNow: -300))),
        .verification(VerificationSummary(id: "verification-1",
                                          requesterUserID: "@alice:spiral.md",
                                          requesterDeviceID: "IPHONE15",
                                          state: .pendingOwner,
                                          createdAt: Date(timeIntervalSinceNow: -900),
                                          deadlineAt: Date(timeIntervalSinceNow: 600)))
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
                           createdAt: Date(timeIntervalSinceNow: -3600),
                           resolvedAt: Date(timeIntervalSinceNow: -3590)),
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
                           createdAt: Date(timeIntervalSinceNow: -86400),
                           resolvedAt: Date(timeIntervalSinceNow: -86400))
    ]

    static func makeViewModel(needsAction: [NeedsActionItem],
                              activity: [AgentActivityEntry],
                              failsActivity: Bool = false,
                              visitorMessages: [VisitorMessage] = []) -> NotificationsHubScreenViewModel {
        let streamService = ApprovalsStreamServiceMock()
        streamService.needsAction = needsAction
        streamService.underlyingPendingCount = needsAction.count
        streamService.underlyingUnseenCount = 0
        streamService.underlyingConnectionState = .connected

        let platformService = AgentPlatformServiceMock()
        if failsActivity {
            platformService.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 500))
        } else {
            platformService.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: needsAction,
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
                                                                                        lifecycleState: "active", presence: .online,
                                                                                        roomCount: 1, activeToolCount: 0)]))

        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { $0 == "!example1:spiral.md" ? .mock(id: $0, name: "Book club") : nil }
        clientProxy.profileForClosure = { userID in
            userID == "@bob:spiral.md" ? .success(.init(userID: userID, displayName: "Bob")) : .failure(.sdkError(ClientProxyMockError.generic))
        }
        return NotificationsHubScreenViewModel(approvalsStreamService: streamService,
                                               agentPlatformService: platformService,
                                               clientProxy: clientProxy,
                                               userIndicatorController: UserIndicatorControllerMock())
    }
}
