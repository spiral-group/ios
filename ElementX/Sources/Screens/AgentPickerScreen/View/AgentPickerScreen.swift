//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//

import Compound
import SwiftUI

struct AgentPickerScreen: View {
    @Bindable var context: AgentPickerScreenViewModel.Context

    var body: some View {
        Form {
            Section {
                ForEach(context.viewState.agents) { agent in
                    ListRow(label: .default(title: agent.displayName,
                                            description: subtitle(for: agent),
                                            icon: \.userProfile),
                            kind: .navigationLink {
                                context.send(viewAction: .selectAgent(id: agent.id))
                            })
                }
            } header: {
                Text(UntranslatedL10n.screenAgentPickerSectionTitle)
                    .compoundListSectionHeader()
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenAgentPickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
    }

    private func subtitle(for agent: AgentPickerItem) -> String {
        agent.activeToolCount > 0
            ? UntranslatedL10n.screenAgentsToolCount(agent.activeToolCount)
            : agent.matrixUserID
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .done) }
        }
    }
}

// MARK: - Previews

struct AgentPickerScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = AgentPickerScreenViewModel(agents: [
        AgentPickerItem(agentID: "a1", matrixUserID: "@assistant:example.com", displayName: "Aria", activeToolCount: 2),
        AgentPickerItem(agentID: "a2", matrixUserID: "@scribe:example.com", displayName: "Scribe", activeToolCount: 0)
    ])

    static var previews: some View {
        ElementNavigationStack {
            AgentPickerScreen(context: viewModel.context)
        }
    }
}
