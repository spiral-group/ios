//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
// The "Add agent" picker: the caller's own agents as
// avatar rows; those already in the room are non-addable (badge). Tapping an
// addable agent invites it.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct AddAgentPickerScreen: View {
    @Bindable var context: AddAgentPickerScreenViewModel.Context
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                loadingSection
            case .loaded:
                agentsSection
            case .failed:
                errorSection
            }
        }
        .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        .navigationTitle(UntranslatedL10n.screenAddAgentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .toolbar { toolbar }
    }

    // MARK: - Sections

    /// The person's agents as placeholders, after a short delay (decision 330).
    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 3, leading: .avatar(SpiralAvatarSize.small))
                }
            })
        }
    }

    @ViewBuilder
    private var agentsSection: some View {
        if context.viewState.agents.isEmpty {
            Section {
                SpiralEmptyState(symbol: .sparkles, title: UntranslatedL10n.screenAddAgentEmpty)
                    .listRowBackground(Color.clear)
            }
        } else {
            // One section per space the person acts for, Personal first.
            ForEach(context.viewState.sections) { section in
                Section {
                    ForEach(section.agents) { agent in
                        agentRow(agent)
                    }
                } header: {
                    Text(section.title)
                        .compoundListSectionHeader()
                } footer: {
                    if section.id == context.viewState.sections.last?.id {
                        Text(UntranslatedL10n.screenAddAgentFooter)
                            .compoundListSectionFooter()
                    }
                }
            }
        }
    }

    private func agentRow(_ agent: AddAgentItem) -> some View {
        AgentRow(title: agent.displayName,
                 status: agent.isInRoom ? UntranslatedL10n.screenAddAgentInRoomBadge : nil,
                 avatarContentID: agent.matrixUserID,
                 avatarURL: agent.avatarURL,
                 mediaProvider: mediaProvider,
                 kind: rowKind(for: agent)) {
            context.send(viewAction: .invite(id: agent.id))
        }
        // An invite in flight elsewhere disables the rest of the list.
        .disabled(agent.isInRoom == false
            && context.viewState.invitingAgentID != nil
            && context.viewState.invitingAgentID != agent.agentID)
        // Not `.disabled`, which dims the row: nothing here has failed, the room is only being read.
        .allowsHitTesting(context.viewState.isRoomRead)
    }

    private func rowKind(for agent: AddAgentItem) -> AgentRowKind {
        if agent.isInRoom {
            return .disabled
        }
        if context.viewState.invitingAgentID == agent.agentID {
            return .waiting
        }
        return .button
    }

    private var errorSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAddAgentPickerLoadFailed) { context.send(viewAction: .retry) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .done) }
        }
    }
}

// MARK: - Previews

struct AddAgentPickerScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let noAgentsViewModel = makeViewModel(hasAgents: false)

    static var previews: some View {
        // Decision 330: without the wait, the snapshot caught the first load's blank 250 ms.
        ElementNavigationStack {
            AddAgentPickerScreen(context: viewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState).map { $0.isRoomRead && !$0.sections.isEmpty })

        ElementNavigationStack {
            AddAgentPickerScreen(context: noAgentsViewModel.context, mediaProvider: nil)
        }
        .snapshotPreferences(expect: noAgentsViewModel.context.observe(\.viewState).map { state in
            if case .loaded = state.listState { state.isRoomRead } else { false }
        })
        .previewDisplayName("No agents")
    }

    private static func makeViewModel(hasAgents: Bool = true) -> AddAgentPickerScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(AgentSpacesDirectory(spaces: hasAgents ? [
            AgentSpaceSummary(orgID: "personal", name: "Alice", kind: .solo, avatarMXC: nil, agentCount: 1),
            AgentSpaceSummary(orgID: "acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)
        ] : [], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            orgID == "personal"
                ? .success(space(orgID, kind: .solo, agent: card("a1", mxid: "@assistant-alice:example.com", name: "Assistant Alice")))
                : .success(space(orgID, kind: .company, agent: card("a2", mxid: "@agent-acme-sales:example.com", name: "Acme Sales")))
        }
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: "!room:example.com",
                                                                         agents: [RoomToolAgentEntry(agentID: "a1", matrixUserID: "@assistant-alice:example.com",
                                                                                                     displayName: "Assistant", ownerUserID: "@o:host",
                                                                                                     isMine: true, tools: [])]))
        return AddAgentPickerScreenViewModel(roomID: "!room:example.com",
                                             roomProxy: JoinedRoomProxyMock(.init()),
                                             store: AgentsStore(service: service))
    }

    private nonisolated static func space(_ orgID: String, kind: AgentSpaceSummary.Kind, agent: AgentSpaceAgentCard) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: orgID, name: orgID, kind: kind, avatarMXC: nil, industry: nil, website: nil, agents: [agent])
    }

    private nonisolated static func card(_ id: String, mxid: String, name: String) -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: id, matrixUserID: mxid, displayName: name, avatarMXC: nil,
                            kind: "sales", visibility: "private", lifecycleState: "active",
                            roomCount: 0, activeToolCount: 0)
    }
}
