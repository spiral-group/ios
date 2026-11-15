//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
// A chat's tools (question 359, item 12, board A): every agent with its tools.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct AgentSheetScreen: View {
    @Bindable var context: AgentSheetScreenViewModel.Context
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                loadingSection
            case .loaded(let mine, let others):
                groupSections(mine, header: UntranslatedL10n.screenAgentSheetYoursHeader, footer: nil)
                groupSections(others, header: UntranslatedL10n.screenAgentSheetOthersHeader, footer: UntranslatedL10n.screenAgentSheetOthersFooter)
            case .failed:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentSheetLoadFailed) { context.send(viewAction: .retry) }
            }
            addAgentSection
        }
        .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        .navigationTitle(UntranslatedL10n.screenChatToolsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .alert(item: $context.alertInfo)
        .toolbar { toolbar }
    }

    // MARK: - Sections

    // AGENT-PLATFORM (Brief 0083, question 359): an agent and its tools as placeholders, after a short delay (decision
    // 330). How many there are is the read's to say; "Add agent" is there from the start.
    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    VStack(spacing: 0) {
                        SpiralPlaceholderRows(count: 1, leading: .avatar(SpiralAvatarSize.small))
                        SpiralPlaceholderRows(count: 2, leading: .icon)
                    }
                }
            })
        } header: {
            Text(UntranslatedL10n.screenAgentSheetYoursHeader)
                .compoundListSectionHeader()
        }
    }

    /// One section for each agent; the first carries the header and the last the footer.
    private func groupSections(_ groups: [AgentSheetGroup], header: String, footer: String?) -> some View {
        ForEach(groups) { group in
            Section {
                agentRow(group)
                ForEach(group.tools) { tool in
                    toolRow(tool, agentID: group.id)
                }
                if group.agent.isMine {
                    addRows(group)
                }
            } header: {
                if group.id == groups.first?.id {
                    Text(header)
                        .compoundListSectionHeader()
                }
            } footer: {
                if let footer, group.id == groups.last?.id {
                    Text(footer)
                        .compoundListSectionFooter()
                }
            }
        }
    }

    private func agentRow(_ group: AgentSheetGroup) -> some View {
        ListRow(kind: .custom {
            HStack(spacing: CompoundDesignTokens.space3X) {
                LoadableAvatarImage(url: group.agent.avatarURL,
                                    name: group.agent.displayName,
                                    contentID: group.agent.matrixUserID,
                                    avatarSize: .custom(SpiralAvatarSize.small),
                                    mediaProvider: mediaProvider)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.agent.displayName)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                    if let ownerLine = group.ownerLine {
                        Text(ownerLine)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if group.agent.isMine {
                    agentMenu(group)
                }
            }
            .padding(.horizontal, ListRowPadding.horizontal)
            .padding(.vertical, CompoundDesignTokens.space2X)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.agent(group.agent.matrixUserID))
        })
    }

    @ViewBuilder
    private func agentMenu(_ group: AgentSheetGroup) -> some View {
        if context.viewState.removingAgentID == group.id {
            ProgressView()
        } else {
            Menu {
                Button {
                    context.send(viewAction: .viewProfile(agentID: group.id))
                } label: {
                    Label(L10n.screenBottomSheetManageRoomMemberMemberUserInfo, icon: \.userProfile)
                }
                if group.canRemoveFromChat {
                    Button(role: .destructive) {
                        context.send(viewAction: .removeAgent(agentID: group.id))
                    } label: {
                        Label(UntranslatedL10n.screenAgentInRoomRemove, icon: \.leave)
                    }
                }
            } label: {
                CompoundIcon(\.overflowHorizontal)
                    .foregroundStyle(.compound.iconSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(UntranslatedL10n.screenProfileActionMore)
            .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.agentMenu(group.agent.matrixUserID))
        }
    }

    private func toolRow(_ tool: AgentSheetTool, agentID: String) -> some View {
        ListRow(label: .default(title: tool.title, description: tool.subtitle, icon: tool.icon),
                details: tool.isUnavailable ? .title(UntranslatedL10n.screenAgentCapabilitiesUnavailable) : nil,
                kind: .navigationLink {
                    context.send(viewAction: .selectTool(agentID: agentID, toolID: tool.id))
                })
                .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.tool(tool.id))
    }

    /// Under an own agent: "Add a tool", or with no tools yet what board 4 draws.
    @ViewBuilder
    private func addRows(_ group: AgentSheetGroup) -> some View {
        switch group.quickAdd {
        case .none:
            addToolRow(title: UntranslatedL10n.screenAgentInRoomAddTool, agentID: group.id)
        case .loading:
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 2, leading: .icon)
                }
            })
        case .kinds(let kinds, let hasMore):
            ForEach(kinds) { kind in
                ListRow(label: .default(title: kind.title, description: kind.explanation, icon: kind.icon),
                        details: .icon(CompoundIcon(\.plus).foregroundStyle(.compound.iconAccentPrimary)),
                        kind: .button {
                            context.send(viewAction: .addToolOfKind(kind, agentID: group.id))
                        })
                        .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.quickAdd(kind.rawValue))
            }
            if hasMore {
                addToolRow(title: UntranslatedL10n.screenChatToolsAllTools, agentID: group.id)
            }
        case .failed:
            ListRow(label: .plain(title: UntranslatedL10n.screenAddToolLoadFailed), kind: .label)
            ListRow(label: .action(title: L10n.actionRetry, icon: \.restart, role: .accent),
                    kind: .button {
                        context.send(viewAction: .retryCatalog(agentID: group.id))
                    })
        }
    }

    private func addToolRow(title: String, agentID: String) -> some View {
        ListRow(label: .action(title: title, icon: \.plus, role: .accent),
                kind: .button {
                    context.send(viewAction: .addTool(agentID: agentID))
                })
                .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.addTool)
    }

    private var addAgentSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenAgentSheetAddAgent,
                                   icon: \.userAdd,
                                   role: .accent),
                    kind: .button {
                        context.send(viewAction: .addAgent)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.addAgent)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ToolScreenTitle(title: UntranslatedL10n.screenChatToolsTitle, subtitle: context.viewState.roomName)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .done) }
        }
    }
}

// MARK: - Previews

struct AgentSheetScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let translateTool = RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                                            targetLanguage: "ru",
                                            params: .translate(targetLanguage: "ru"),
                                            trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1", appliesToViewer: .yes)
    static let summaryTool = RoomToolView(toolID: "t2", toolKind: "call_summary", triggerKind: "on_voice_call",
                                          targetLanguage: nil,
                                          params: .callSummary,
                                          trigger: .onVoiceCall(speakerScope: .anyone), safeSliceSalt: "t2", appliesToViewer: .notApplicable)
    // Other participants' tools arrive safe-sliced (no id/params/trigger).
    static let othersTool = RoomToolView(toolID: nil, toolKind: "translate", triggerKind: "on_message",
                                         targetLanguage: "en",
                                         params: nil, trigger: nil, safeSliceSalt: "t3", appliesToViewer: .yes)

    static let mixedViewModel = makeViewModel(agents: [
        agentEntry(id: "a1", mxid: "@assistant:example.com", name: "Your Assistant", mine: true, tools: [translateTool, summaryTool]),
        agentEntry(id: "a2", mxid: "@bohdan-agent:example.com", name: "Bohdan's Agent", mine: false, tools: [othersTool])
    ])
    static let emptyViewModel = makeViewModel(agents: [
        agentEntry(id: "a1", mxid: "@assistant:example.com", name: "Your Assistant", mine: true, tools: [])
    ])
    static let noOwnViewModel = makeViewModel(agents: [
        agentEntry(id: "a2", mxid: "@bohdan-agent:example.com", name: "Bohdan's Agent", mine: false, tools: [othersTool])
    ])
    static let nothingViewModel = makeViewModel(agents: [])
    static let failedViewModel = makeViewModel(agents: [], isFailed: true)
    static let catalogFailedViewModel = makeViewModel(agents: [
        agentEntry(id: "a1", mxid: "@assistant:example.com", name: "Your Assistant", mine: true, tools: [])
    ], isCatalogFailed: true)
    static let loadingViewModel = makeViewModel(agents: [], isLoading: true)

    static var previews: some View {
        ElementNavigationStack {
            AgentSheetScreen(context: mixedViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: hasLoaded(mixedViewModel))
        .previewDisplayName("Yours + others")

        ElementNavigationStack {
            AgentSheetScreen(context: emptyViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: hasCatalog(emptyViewModel))
        .previewDisplayName("Empty")

        ElementNavigationStack {
            AgentSheetScreen(context: noOwnViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: hasLoaded(noOwnViewModel))
        .previewDisplayName("No own agent")

        ElementNavigationStack {
            AgentSheetScreen(context: nothingViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: hasLoaded(nothingViewModel))
        .previewDisplayName("No agents")

        ElementNavigationStack {
            AgentSheetScreen(context: failedViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: failedViewModel.context.observe(\.viewState.listState).map { if case .failed = $0 { true } else { false } })
        .previewDisplayName("Failed")

        ElementNavigationStack {
            AgentSheetScreen(context: catalogFailedViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: hasCatalog(catalogFailedViewModel))
        .previewDisplayName("Catalogue failed")

        ElementNavigationStack {
            AgentSheetScreen(context: loadingViewModel.context, mediaProvider: nil)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
    }

    private static func hasLoaded(_ viewModel: AgentSheetScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loaded = $0 { true } else { false } }
    }

    private static func hasCatalog(_ viewModel: AgentSheetScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map {
            guard case .loaded(let mine, _) = $0 else { return false }
            return mine.allSatisfy { if case .loading = $0.quickAdd { false } else { true } }
        }
    }

    private static func agentEntry(id: String, mxid: String, name: String, mine: Bool, tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: id,
                           matrixUserID: mxid,
                           displayName: name,
                           ownerUserID: mine ? "@owner:example.com" : "@bohdan:example.com",
                           isMine: mine,
                           tools: tools)
    }

    private static func makeViewModel(agents: [RoomToolAgentEntry],
                                      isLoading: Bool = false,
                                      isFailed: Bool = false,
                                      isCatalogFailed: Bool = false) -> AgentSheetScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = isFailed ? .failure(.serverError(status: 500)) : .success(RoomToolsView(roomID: "!room:example.com", agents: agents))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = isCatalogFailed ? .failure(.serverError(status: 500)) : .success(ToolsCatalogView(agentID: "a1",
                                                                                                                                              roomID: "!room:example.com",
                                                                                                                                              paramsSchema: [:],
                                                                                                                                              triggerSchema: [:],
                                                                                                                                              textTranslationLanguages: [],
                                                                                                                                              voiceTranslationLanguages: [],
                                                                                                                                              availableToolKinds: AgentToolKind.allCases.map(\.rawValue)))
        if isLoading {
            // The snapshot suites share this view model in one run, which can outlast a minute.
            service.fetchRoomToolsRoomIDClosure = { _ in
                try? await Task.sleep(for: .seconds(24 * 3600))
                return .failure(.serverError(status: 0))
            }
        }
        return AgentSheetScreenViewModel(roomID: "!room:example.com",
                                         roomProxy: JoinedRoomProxyMock(.init(id: "!room:example.com", name: "Stage A")),
                                         store: AgentsStore(service: service),
                                         agentPlatformService: service,
                                         clientProxy: ClientProxyMock(.init()))
    }
}
