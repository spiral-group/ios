//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
// The room's own agents as avatar rows (name + tool
// summary) + "Add agent". A tap opens the agent's capabilities; "Add agent"
// opens the invite picker. This is the room → agent → tool entry surface.
//

import Compound
import SwiftUI

struct AgentSheetScreen: View {
    @Bindable var context: AgentSheetScreenViewModel.Context
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                loadingSection
            case .loaded:
                ownAgentsSection
                otherAgentsSection
                addAgentSection
            case .failed:
                errorSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenAgentSheetTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .retry) }
        .onAppear { context.send(viewAction: .appeared) }
        .toolbar { toolbar }
    }

    // MARK: - Sections

    /// Fast data → a delayed spinner, no flicker (CODEBASE/14 §3).
    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                DelayedProgressView()
                    .frame(minHeight: 80)
            })
        }
        .listRowBackground(Color.clear)
        .accessibilityRepresentation { Text(L10n.commonLoading) }
    }

    /// The caller's own agents — tappable, editable. When the caller
    /// has none, a "you have no agent here" line invites them to add
    /// one (the add row below is the affordance).
    @ViewBuilder
    private var ownAgentsSection: some View {
        if context.viewState.hasNoOwnAgent {
            Section {
                Text(UntranslatedL10n.screenAgentSheetNoOwnAgent)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(context.viewState.agents) { agent in
                    agentRow(agent, editable: true)
                }
            } header: {
                Text(UntranslatedL10n.screenAgentSheetYoursHeader)
                    .compoundListSectionHeader()
            }
        }
    }

    /// Brief 0043 P4: other participants' armed agents — READ-ONLY, so
    /// everyone sees the room's full tool picture but edits only their
    /// own. Hidden when nobody else has tools.
    @ViewBuilder
    private var otherAgentsSection: some View {
        if !context.viewState.otherAgents.isEmpty {
            Section {
                ForEach(context.viewState.otherAgents) { agent in
                    agentRow(agent, editable: false)
                }
            } header: {
                Text(UntranslatedL10n.screenAgentSheetOthersHeader)
                    .compoundListSectionHeader()
            } footer: {
                Text(UntranslatedL10n.screenAgentSheetOthersFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ agent: AgentSummary, editable: Bool) -> some View {
        if editable {
            AgentRow(title: agent.displayName,
                     description: agent.statusLine,
                     avatarContentID: agent.matrixUserID,
                     mediaProvider: mediaProvider,
                     kind: context.viewState.openingAgentID == agent.id ? .waiting : .navigate) {
                context.send(viewAction: .selectAgent(id: agent.id))
            }
            .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.agent(agent.matrixUserID))
        } else {
            // Read-only: no navigation chevron, no tap action — display
            // only, attributed to its owner via the display name.
            AgentRow(title: agent.displayName,
                     description: agent.statusLine,
                     avatarContentID: agent.matrixUserID,
                     mediaProvider: mediaProvider,
                     kind: .readOnly) { }
        }
    }

    private var addAgentSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenAgentSheetAddAgent,
                                   icon: \.userAdd),
                    kind: .button {
                        context.send(viewAction: .addAgent)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.agentSheetScreen.addAgent)
        } footer: {
            Text(UntranslatedL10n.screenAgentSheetFooter)
                .compoundListSectionFooter()
        }
    }

    private var errorSection: some View {
        AgentSpacesRetryErrorSection { context.send(viewAction: .retry) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .done) }
        }
    }
}

// MARK: - Previews

struct AgentSheetScreen_Previews: PreviewProvider, TestablePreview {
    static let mineTool = RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                                       targetLanguage: "English",
                                       params: .translate(targetLanguage: "English"),
                                       trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1")
    // Other participants' tools arrive safe-sliced (no id/params/trigger).
    static let othersTool = RoomToolView(toolID: nil, toolKind: "summarize", triggerKind: "on_message",
                                         targetLanguage: nil,
                                         params: nil, trigger: nil, safeSliceSalt: "t2")

    static let mixedViewModel = makeViewModel(agents: [
        agentEntry(id: "a1", mxid: "@assistant:example.com", name: "Your Assistant", mine: true, tools: [mineTool]),
        agentEntry(id: "a2", mxid: "@bohdan-agent:example.com", name: "Bohdan's Agent", mine: false, tools: [othersTool])
    ])
    static let noOwnViewModel = makeViewModel(agents: [
        agentEntry(id: "a2", mxid: "@bohdan-agent:example.com", name: "Bohdan's Agent", mine: false, tools: [othersTool])
    ])

    static var previews: some View {
        ElementNavigationStack {
            AgentSheetScreen(context: mixedViewModel.context, mediaProvider: nil)
        }
        .previewDisplayName("Yours + others")

        ElementNavigationStack {
            AgentSheetScreen(context: noOwnViewModel.context, mediaProvider: nil)
        }
        .previewDisplayName("No own agent")
    }

    private static func agentEntry(id: String, mxid: String, name: String, mine: Bool, tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: id,
                           matrixUserID: mxid,
                           displayName: name,
                           ownerUserID: mine ? "@owner:example.com" : "@bohdan:example.com",
                           isMine: mine,
                           tools: tools)
    }

    private static func makeViewModel(agents: [RoomToolAgentEntry]) -> AgentSheetScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(
            RoomToolsView(roomID: "!room:example.com", agents: agents))
        let viewModel = AgentSheetScreenViewModel(roomID: "!room:example.com", agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        return viewModel
    }
}
