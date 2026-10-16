//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The agent in one chat (step B.4): the chat's name with the agent under it,
/// each tool with its own icon, name and when it runs; a tool opens its form;
/// «Убрать агента из чата» at the bottom, like Element's "Leave space".
struct AgentInRoomScreen: View {
    @Bindable var context: AgentInRoomScreenViewModel.Context
    
    var body: some View {
        Form {
            toolsSection
            removeSection
        }
        .compoundList()
        .navigationTitle(context.viewState.roomTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(context.viewState.roomTitle)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    Text(context.viewState.agent.displayName)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .alert(item: $context.alertInfo)
    }
    
    private var toolsSection: some View {
        Section {
            if context.viewState.room.activeTools.isEmpty {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentInRoomNoTools), kind: .label)
            } else {
                ForEach(context.viewState.room.activeTools) { tool in
                    ListRow(label: .default(title: tool.localizedTitle,
                                            description: tool.localizedTrigger(memberNames: context.viewState.memberNames),
                                            icon: ToolDisplayName.icon(forKind: tool.toolKind)),
                            details: context.viewState.openingToolID == tool.toolID ? .isWaiting(true) : nil,
                            kind: .navigationLink {
                                context.send(viewAction: .selectTool(id: tool.toolID))
                            })
                            .disabled(context.viewState.openingToolID != nil)
                }
            }
            
            ListRow(label: .action(title: UntranslatedL10n.screenAgentInRoomAddTool,
                                   icon: \.plus),
                    kind: .button {
                        context.send(viewAction: .addTool)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.agentInRoomScreen.addTool)
        } header: {
            Text(UntranslatedL10n.screenAgentInRoomSectionTitle)
                .compoundListSectionHeader()
        }
    }
    
    private var removeSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenAgentInRoomRemove,
                                   icon: \.leave,
                                   role: .destructive),
                    details: .isWaiting(context.viewState.isRemoving),
                    kind: .button {
                        context.send(viewAction: .removeTapped)
                    })
                    .disabled(context.viewState.isRemoving)
                    .accessibilityIdentifier(A11yIdentifiers.agentInRoomScreen.remove)
        }
    }
}

// MARK: - Previews

struct AgentInRoomScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let emptyViewModel = makeViewModel(hasTools: false)
    
    static var previews: some View {
        ElementNavigationStack {
            AgentInRoomScreen(context: viewModel.context)
        }
        
        ElementNavigationStack {
            AgentInRoomScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("No tools")
    }
    
    static func makeViewModel(hasTools: Bool = true) -> AgentInRoomScreenViewModel {
        let agent = AgentInRoomScreenAgent(agentID: "agent-1",
                                           matrixUserID: "@assistant-owner:spiral.md",
                                           displayName: "Personal Assistant")
        
        let room = AgentRoomEntry(roomID: "!group:spiral.md",
                                  displayName: "Team chat",
                                  kind: "group",
                                  activeTools: hasTools
                                      ? [.init(toolID: "t1", toolKind: "translate", targetLanguages: ["en"], firing: .onMessage, audience: .nonSelfNonOwner),
                                         .init(toolID: "t2", toolKind: "call_summary", targetLanguages: [], firing: .onVoiceCall, audience: .anyone)]
                                      : [])
        
        return AgentInRoomScreenViewModel(agent: agent,
                                          room: room,
                                          agentPlatformService: AgentPlatformServiceMock(),
                                          clientProxy: ClientProxyMock(.init()),
                                          mediaProvider: MediaProviderMock(.init()))
    }
}
