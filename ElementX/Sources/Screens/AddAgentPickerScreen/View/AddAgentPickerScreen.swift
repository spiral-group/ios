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
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenAddAgentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
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

    @ViewBuilder
    private var agentsSection: some View {
        if context.viewState.agents.isEmpty {
            Section {
                Text(UntranslatedL10n.screenAddAgentEmpty)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
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
                 description: agent.matrixUserID,
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

struct AddAgentPickerScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()

    static var previews: some View {
        ElementNavigationStack {
            AddAgentPickerScreen(context: viewModel.context, mediaProvider: nil)
        }
    }

    private static func makeViewModel() -> AddAgentPickerScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(AgentSpacesDirectory(spaces: [
            AgentSpaceSummary(orgID: "personal", name: "Alice", kind: .solo, avatarMXC: nil, agentCount: 1),
            AgentSpaceSummary(orgID: "acme", name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)
        ], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            orgID == "personal"
                ? .success(space(orgID, kind: .solo, agent: card("a1", mxid: "@assistant-alice:example.com", name: "Assistant Alice")))
                : .success(space(orgID, kind: .company, agent: card("a2", mxid: "@agent-acme-sales:example.com", name: "Acme Sales")))
        }
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: "!room:example.com",
                                                                         agents: [RoomToolAgentEntry(agentID: "a1", matrixUserID: "@assistant-alice:example.com",
                                                                                                     displayName: "Assistant", ownerUserID: "@o:host",
                                                                                                     isMine: true, tools: [])]))
        let viewModel = AddAgentPickerScreenViewModel(roomID: "!room:example.com",
                                                      roomProxy: JoinedRoomProxyMock(.init()),
                                                      agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        return viewModel
    }

    private nonisolated static func space(_ orgID: String, kind: AgentSpaceSummary.Kind, agent: AgentSpaceAgentCard) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: orgID, name: orgID, kind: kind, avatarMXC: nil, industry: nil, website: nil, agents: [agent])
    }

    private nonisolated static func card(_ id: String, mxid: String, name: String) -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: id, matrixUserID: mxid, displayName: name, avatarMXC: nil,
                            kind: "sales", visibility: "private", lifecycleState: "active",
                            presence: .online, roomCount: 0, activeToolCount: 0)
    }
}
