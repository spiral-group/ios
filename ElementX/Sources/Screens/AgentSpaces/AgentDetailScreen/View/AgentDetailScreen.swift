//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents
import SwiftUI

/// One agent (step B, decision 191): the profile pages' hero on top (avatar, name,
/// handle, what it is, its status, «Написать» and «В чат»), «Активность» and
/// «Использование», the agent's chats; a role agent's brief and its Archive at
/// the bottom. «Изменить» is in the toolbar.
struct AgentDetailScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @Bindable var context: AgentDetailScreenViewModel.Context
    
    var body: some View {
        // The profile pages' page (question 359): the avatar's field behind the top, the pull and the bar as there.
        SpiralProfilePage(picture: .user(profile),
                          title: context.viewState.displayName,
                          mediaProvider: context.mediaProvider) {
            headerSection
            
            verificationBannerSection
            
            activitySection
            
            // AGENT-PLATFORM (Brief 0083, question 359): the page's shape comes from the card. The read fills the
            // chats' slot and the counts; it moves nothing under them.
            chatsSection
            
            settingsSection
            
            controlSection
            
            queueSection
            
            archiveSection
        }
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .toolbar { toolbar }
        .alert(item: $context.alertInfo)
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(UntranslatedL10n.screenAgentsActionEdit) {
                context.send(viewAction: .edit)
            }
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.edit)
        }
    }
    
    // MARK: Header
    
    /// The page's picture: the agent's avatar, and a field in its own colour when it has none (question 400).
    private var profile: UserProfile {
        UserProfile(userID: context.viewState.card.matrixUserID,
                    displayName: context.viewState.displayName,
                    avatarURL: context.viewState.avatarMXC.flatMap(URL.init(string:)))
    }
    
    /// The profile pages' hero (question 359): the avatar with its badge, the name, the handle, what it is and its
    /// status, then Message and Add to chat as Spiral's buttons. Activity and Usage open screens, so they are rows below.
    private var headerSection: some View {
        SpiralProfileHero(picture: .user(profile),
                          title: context.viewState.displayName,
                          agent: SpiralAgentProfile(userID: context.viewState.card.matrixUserID,
                                                    roleLine: context.viewState.kindLine,
                                                    ownCard: context.viewState.card),
                          subtitle: context.viewState.card.matrixUserID,
                          agentStatus: context.viewState.presence,
                          mediaProvider: context.mediaProvider) {
            actionButtons
                .padding(.horizontal, ListRowPadding.horizontal)
                .padding(.top, CompoundDesignTokens.space2X)
        }
    }
    
    /// Side by side, each half the width; stacked at accessibility sizes, Message first.
    private var actionButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: CompoundDesignTokens.space2X))
            : AnyLayout(HStackLayout(spacing: CompoundDesignTokens.space3X))
        return layout {
            Button {
                context.send(viewAction: .message)
            } label: {
                actionTitle(L10n.actionMessage)
            }
            .buttonStyle(.compound(.primary, size: .medium))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.message)
            
            Button {
                context.send(viewAction: .addToChat)
            } label: {
                actionTitle(UntranslatedL10n.actionAddAgentToChat)
            }
            .buttonStyle(.compound(.secondary, size: .medium, isRaised: true))
            .disabled(context.viewState.isAddingToChat)
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.addToChat)
        }
    }
    
    /// A title without a glyph: two titles fit side by side on the smallest phone in long languages.
    private func actionTitle(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }
    
    /// Activity and Usage, which were tiles in the header.
    private var activitySection: some View {
        Section {
            AgentActivityRows(onActivity: { context.send(viewAction: .openActivity) },
                              onUsage: { context.send(viewAction: .openUsage) })
        }
    }
    
    // MARK: Verification banner
    
    @ViewBuilder
    private var verificationBannerSection: some View {
        if !context.viewState.pendingVerifications.isEmpty {
            // As RoomDetailsScreen shows knock requests: a plain row with a counter.
            Section {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentDetailVerificationBanner(context.viewState.pendingVerifications.count),
                                        icon: \.verified),
                        details: .counter(context.viewState.pendingVerifications.count),
                        kind: .navigationLink {
                            context.send(viewAction: .openVerification)
                        })
            }
        }
    }
    
    /// The chats' slot: placeholders as the card counts them, the rows, or why there are none to show.
    @ViewBuilder
    private var chatsSection: some View {
        switch context.viewState.detailState {
        case .loading:
            AgentChatsLoadingSection(count: context.viewState.card.roomCount)
        case .failure:
            failureSection
        case .loaded(_, let rooms):
            AgentChatsSection(rooms: rooms) { room in
                context.viewState.title(for: room)
            } onSelect: { room in
                context.send(viewAction: .selectRoom(room))
            }
        }
    }
    
    /// «Настройки» (decision 194): each row a small screen, but a screen of
    /// one switch is the switch here.
    private var settingsSection: some View {
        Section {
            if context.viewState.showsPeopleSettings {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentSettingsPeopleTitle, icon: \.user),
                        kind: .navigationLink {
                            context.send(viewAction: .openSettings(.people))
                        })
            } else if let showInSearch = context.viewState.showInSearch {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentSettingsShowInSearch, icon: \.search),
                        kind: .toggle(Binding(get: { showInSearch },
                                              set: { context.send(viewAction: .setShowInSearch($0)) })))
                    .disabled(context.viewState.isWritingVisibility)
                    .allowsHitTesting(context.viewState.canWriteSwitches) // Not `.disabled`, which dims the row.
            }
            ListRow(label: .default(title: context.viewState.characterTitle, icon: \.reaction),
                    kind: .navigationLink {
                        context.send(viewAction: .openSettings(.character))
                    })
            if context.viewState.showsCallsSettings {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentSettingsCallsTitle, icon: \.voiceCall),
                        kind: .navigationLink {
                            context.send(viewAction: .openSettings(.calls))
                        })
            }
        } header: {
            Text(L10n.commonSettings)
                .compoundListSectionHeader()
        } footer: {
            if context.viewState.showInSearch != nil {
                Text(UntranslatedL10n.screenAgentSettingsShowInSearchFooter)
                    .compoundListSectionFooter()
            }
        }
    }
    
    /// «Контроль»: the pause, what waits for the owner, who is blocked.
    private var controlSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenAgentDetailPause,
                                    description: UntranslatedL10n.screenAgentDetailPauseDescription,
                                    icon: \.pause),
                    kind: .toggle(Binding(get: { context.viewState.paused },
                                          set: { context.send(viewAction: .setPaused($0)) })))
                .disabled(context.viewState.isPausing)
                .allowsHitTesting(context.viewState.canWriteSwitches) // Not `.disabled`, which dims the row.
            countRow(title: UntranslatedL10n.screenAgentActivityFilterPendingConsent,
                     icon: \.time,
                     count: context.viewState.pendingApprovalsCount.map(String.init),
                     isReading: context.viewState.isReadingPendingApprovals) {
                context.send(viewAction: .openPendingApprovals)
            }
            countRow(title: UntranslatedL10n.screenAgentDetailBlocked,
                     icon: \.block,
                     count: context.viewState.blockedCount?.text,
                     isReading: context.viewState.isReadingBlocked) {
                context.send(viewAction: .openBlocked)
            }
        } header: {
            Text(UntranslatedL10n.screenAgentDetailControlSection)
                .compoundListSectionHeader()
        }
    }
    
    /// A row with a count: a placeholder while it is read; a failed read leaves the slot empty, never a made-up `0`.
    @ViewBuilder
    private func countRow(title: String,
                          icon: KeyPath<CompoundIcons, Image>,
                          count: String?,
                          isReading: Bool,
                          action: @escaping () -> Void) -> some View {
        if isReading {
            ListRow(label: .default(title: title, icon: icon),
                    details: .icon(SpiralPreloader(label: L10n.commonLoading) { Text(verbatim: "00") }),
                    kind: .navigationLink(action: action))
        } else {
            ListRow(label: .default(title: title, icon: icon),
                    details: count.map { .title($0) },
                    kind: .navigationLink(action: action))
        }
    }
    
    @ViewBuilder
    private var queueSection: some View {
        if context.viewState.showsQueue {
            Section {
                ListRow(label: .default(title: UntranslatedL10n.actionAgentQueue, icon: \.send),
                        kind: .navigationLink {
                            context.send(viewAction: .openQueue)
                        })
            }
        }
    }
    
    @ViewBuilder
    private var archiveSection: some View {
        if context.viewState.canArchive {
            Section {
                ListRow(label: .action(title: UntranslatedL10n.actionArchiveAgent,
                                       icon: \.exportArchive,
                                       role: .destructive),
                        details: .isWaiting(context.viewState.isArchiving),
                        kind: .button {
                            context.send(viewAction: .archiveTapped)
                        })
                        .disabled(context.viewState.isArchiving)
                        .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.archive)
            }
        }
    }
    
    // MARK: States
    
    private var failureSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentDetailErrorTitle) {
            context.send(viewAction: .retry)
        }
    }
}

// MARK: - Previews

struct AgentDetailScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let roleViewModel = makeViewModel(isRoleAgent: true)
    static let pausedViewModel = makeViewModel(isPaused: true)
    static let photoViewModel = makeViewModel(avatarMXC: URL.mockMXCUserAvatar.absoluteString)
    static let loadingViewModel = makeViewModel(isLoading: true)
    static let roleLoadingViewModel = makeViewModel(isRoleAgent: true, isLoading: true)
    static let failedViewModel = makeViewModel(hasFailed: true)
    
    static var previews: some View {
        ElementNavigationStack {
            AgentDetailScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(viewModel))
        
        ElementNavigationStack {
            AgentDetailScreen(context: roleViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(roleViewModel))
        .previewDisplayName("Role agent")
        
        ElementNavigationStack {
            AgentDetailScreen(context: pausedViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(pausedViewModel))
        .previewDisplayName("Paused")
        
        // The field from the agent's picture; the other states have the agent's own colour (question 400).
        ElementNavigationStack {
            AgentDetailScreen(context: photoViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(photoViewModel))
        .previewDisplayName("With a photo")
        
        // What a slow read shows: the rows from the card, placeholders for what the read fills.
        ElementNavigationStack {
            AgentDetailScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
        
        ElementNavigationStack {
            AgentDetailScreen(context: roleLoadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Role agent loading")
        
        ElementNavigationStack {
            AgentDetailScreen(context: failedViewModel.context)
        }
        .snapshotPreferences(expect: failedViewModel.context.observe(\.viewState.detailState).map { if case .failure = $0 { true } else { false } })
        .previewDisplayName("Failed")
    }
    
    /// The agent, its blocks and what waits are read on their own: the snapshot waits for all three.
    private static func hasLoaded(_ viewModel: AgentDetailScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.isReadForPreview)
    }
    
    static func makeViewModel(isRoleAgent: Bool = false,
                              isPaused: Bool = false,
                              avatarMXC: String? = nil,
                              isLoading: Bool = false,
                              hasFailed: Bool = false) -> AgentDetailScreenViewModel {
        let card = isRoleAgent
            ? AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md", displayName: "Sales · Acme Corp",
                                  avatarMXC: avatarMXC, kind: "sales", visibility: "public", lifecycleState: "active",
                                  roomCount: 1, activeToolCount: 0)
            : AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                  avatarMXC: avatarMXC, kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                  roomCount: 3, activeToolCount: 3, isPaused: isPaused)
        
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: card.agentID,
                                                                       matrixUserID: card.matrixUserID,
                                                                       displayName: card.displayName,
                                                                       avatarMXC: avatarMXC,
                                                                       kind: card.kind,
                                                                       visibility: card.visibility,
                                                                       lifecycleState: card.lifecycleState,
                                                                       organizationID: "org-1",
                                                                       roomCount: card.roomCount,
                                                                       activeToolCount: card.activeToolCount,
                                                                       configVersionNumber: 3,
                                                                       persona: nil,
                                                                       roleBrief: isRoleAgent ? "Qualify inbound leads and answer pricing questions." : nil,
                                                                       voiceLanguage: isRoleAgent ? nil : .ru,
                                                                       visitorPolicy: isRoleAgent ? nil : .askFirst,
                                                                       paused: isPaused))
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: isRoleAgent ? [] : [.init(contactMXID: "@spam:example.org",
                                                                                                                   displayName: nil,
                                                                                                                   blockedAt: .now)],
                                                                                 nextCursor: nil))
        service.fetchAgentRoomsAgentIDReturnValue = .success(isRoleAgent
            ? [.init(roomID: "!lead:spiral.md", displayName: "Bob", kind: "dm", activeTools: [])]
            : [.init(roomID: "!owner-dm:spiral.md", displayName: card.displayName, kind: "dm", activeTools: []),
               .init(roomID: "!dm:spiral.md", displayName: "Alice", kind: "dm",
                     activeTools: [.init(toolID: "t1", toolKind: "translate", targetLanguages: ["en"])]),
               .init(roomID: "!group:spiral.md", displayName: "Team chat", kind: "group",
                     activeTools: [.init(toolID: "t2", toolKind: "summarize", targetLanguages: []),
                                   .init(toolID: "t3", toolKind: "call_recording", targetLanguages: [])])])
        
        if isLoading {
            service.fetchAgentRoomsAgentIDClosure = { _ in await neverAnswers() }
            service.listBlockedContactsAgentIDCursorLimitClosure = { _, _, _ in await neverAnswers() }
            service.fetchNotificationsActivityCursorLimitClosure = { _, _ in await neverAnswers() }
        }
        if hasFailed {
            service.fetchAgentRoomsAgentIDReturnValue = .failure(.serverError(status: 500))
        }
        
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success("!owner-dm:spiral.md")
        
        let needsAction: [NeedsActionItem] = isRoleAgent ? [] : [.approval(.init(id: "a1", agentID: card.agentID, draftBody: "Sure, Friday at 11 works.",
                                                                                     targetRoomID: "!dm:spiral.md", createdAt: .now))]
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: needsAction, activity: [], nextActivityCursor: nil,
                                                                                  lastSeenAt: nil, unseenCount: 0))
        
        return AgentDetailScreenViewModel(selection: .init(card: card, companyName: isRoleAgent ? "Acme Corp" : nil),
                                          agentPlatformService: service,
                                          clientProxy: clientProxy,
                                          mediaProvider: MediaProviderMock(.init()),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          store: AgentsStore(service: service))
    }
    
    /// A read that stays on its way: the snapshot suites share a view model in one run, which can outlast a minute.
    private static func neverAnswers<Value>() async -> Result<Value, AgentPlatformError> {
        try? await Task.sleep(for: .seconds(24 * 3600))
        return .failure(.serverError(status: 0))
    }
}

private extension AgentDetailScreenViewState {
    var isReadForPreview: Bool {
        if case .loading = detailState { return false }
        return blockedCount != nil && pendingApprovalsCount != nil
    }
}
