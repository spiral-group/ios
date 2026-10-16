//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// One agent (step B, decision 191) — the room details layout: avatar, name
/// with the presence dot, handle and a kind line; «Написать» · «В чат» ·
/// «Активность» · «Использование»; the agent's chats; a role agent's brief
/// and its Archive at the bottom. «Изменить» is in the toolbar.
struct AgentDetailScreen: View {
    @Bindable var context: AgentDetailScreenViewModel.Context
    
    var body: some View {
        Form {
            headerSection
            
            verificationBannerSection
            
            switch context.viewState.detailState {
            case .loading:
                loadingSection
            case .failure:
                failureSection
            case .loaded(_, let rooms):
                roomsSection(rooms)
                settingsSection
                controlSection
                queueSection
            }
            
            archiveSection
        }
        .compoundList()
        .refreshable { context.send(viewAction: .refresh) }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
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
    
    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                LoadableAvatarImage(url: context.viewState.avatarMXC.flatMap(URL.init(string:)),
                                    name: context.viewState.displayName,
                                    contentID: context.viewState.card.matrixUserID,
                                    avatarSize: .user(on: .memberDetails),
                                    mediaProvider: context.mediaProvider)
                    .accessibilityHidden(true)
                
                AgentNameWithPresence(name: context.viewState.displayName,
                                      isOnline: context.viewState.card.presence == .online)
                    .font(.compound.headingLGBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(context.viewState.card.matrixUserID)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                
                if context.viewState.isPaused {
                    AgentStatusBadge(title: UntranslatedL10n.screenAgentsPaused, variant: .neutral)
                }
                
                if let kindLine = context.viewState.kindLine {
                    Text(kindLine)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                actionButtons
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    /// The room-details action row anatomy (`FormActionButtonStyle`).
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                context.send(viewAction: .message)
            } label: {
                CompoundIcon(\.chat)
            }
            .buttonStyle(FormActionButtonStyle(title: L10n.actionMessage))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.message)
            
            Button {
                context.send(viewAction: .addToChat)
            } label: {
                CompoundIcon(\.chatNew)
            }
            .buttonStyle(FormActionButtonStyle(title: UntranslatedL10n.actionAddAgentToChat))
            .disabled(context.viewState.isAddingToChat)
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.addToChat)
            
            Button {
                context.send(viewAction: .openActivity)
            } label: {
                CompoundIcon(\.history)
            }
            .buttonStyle(FormActionButtonStyle(title: UntranslatedL10n.actionAgentActivity))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.activity)
            
            Button {
                context.send(viewAction: .openUsage)
            } label: {
                CompoundIcon(\.chart)
            }
            .buttonStyle(FormActionButtonStyle(title: UntranslatedL10n.actionAgentUsage))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.usage)
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
    
    // MARK: Chats
    
    private func roomsSection(_ rooms: [AgentRoomEntry]) -> some View {
        Section {
            if rooms.isEmpty {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentDetailNoRooms),
                        kind: .label)
            } else {
                ForEach(rooms) { room in
                    ListRow(label: .default(title: context.viewState.title(for: room),
                                            description: room.toolsLine,
                                            icon: room.kind == "dm" ? \.userProfile : \.chat),
                            kind: .navigationLink {
                                context.send(viewAction: .selectRoom(room))
                            })
                }
            }
        } header: {
            Text(UntranslatedL10n.screenAgentDetailChatsSection)
                .compoundListSectionHeader()
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
            if let paused = context.viewState.paused {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentDetailPause,
                                        description: UntranslatedL10n.screenAgentDetailPauseDescription,
                                        icon: \.pause),
                        kind: .toggle(Binding(get: { paused },
                                              set: { context.send(viewAction: .setPaused($0)) })))
                    .disabled(context.viewState.isPausing)
            }
            ListRow(label: .default(title: UntranslatedL10n.screenAgentActivityFilterPendingConsent, icon: \.time),
                    details: context.viewState.pendingApprovalsCount.map { .title(String($0)) },
                    kind: .navigationLink {
                        context.send(viewAction: .openPendingApprovals)
                    })
            ListRow(label: .default(title: UntranslatedL10n.screenAgentDetailBlocked, icon: \.block),
                    details: context.viewState.blockedCount.map { .title($0.text) },
                    kind: .navigationLink {
                        context.send(viewAction: .openBlocked)
                    })
        } header: {
            Text(UntranslatedL10n.screenAgentDetailControlSection)
                .compoundListSectionHeader()
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
    
    /// Fast data → a delayed spinner, no skeleton flicker (CODEBASE/14 §3).
    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                DelayedProgressView()
                    .frame(minHeight: 80)
            })
        }
        .listRowBackground(Color.clear)
    }
    
    private var failureSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentDetailErrorTitle) {
            context.send(viewAction: .retry)
        }
    }
}

// MARK: - Previews

struct AgentDetailScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let roleViewModel = makeViewModel(isRoleAgent: true)
    static let pausedViewModel = makeViewModel(isPaused: true)
    
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
    }
    
    private static func hasLoaded(_ viewModel: AgentDetailScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.detailState).map { if case .loading = $0 { false } else { true } }
    }
    
    static func makeViewModel(isRoleAgent: Bool = false, isPaused: Bool = false) -> AgentDetailScreenViewModel {
        let card = isRoleAgent
            ? AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md", displayName: "Sales · Acme Corp",
                                  avatarMXC: nil, kind: "sales", visibility: "public", lifecycleState: "active",
                                  presence: .offline, roomCount: 1, activeToolCount: 0)
            : AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                  avatarMXC: nil, kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                  presence: .online, roomCount: 3, activeToolCount: 3, isPaused: isPaused)
        
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: card.agentID,
                                                                       matrixUserID: card.matrixUserID,
                                                                       displayName: card.displayName,
                                                                       avatarMXC: nil,
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
        
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success("!owner-dm:spiral.md")
        
        let stream = ApprovalsStreamServiceMock()
        stream.needsAction = isRoleAgent ? [] : [.approval(.init(id: "a1", agentID: card.agentID, draftBody: "Sure, Friday at 11 works.",
                                                                 targetRoomID: "!dm:spiral.md", createdAt: .now))]
        stream.underlyingConnectionState = .connected
        stream.underlyingIsSeeded = true
        
        return AgentDetailScreenViewModel(selection: .init(card: card, companyName: isRoleAgent ? "Acme Corp" : nil),
                                          agentPlatformService: service,
                                          clientProxy: clientProxy,
                                          mediaProvider: MediaProviderMock(.init()),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          approvalsStreamService: stream)
    }
}
