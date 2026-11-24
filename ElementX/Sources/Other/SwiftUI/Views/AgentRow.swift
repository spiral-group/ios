//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048), not
// present upstream. One agent row for every list of agents: the Agents tab,
// the agent sheet (own agents in the room), the add-agent picker (own agents
// to invite) and the «В чат» picker. Brief 0083 (batch P4-D): it draws
// Spiral's agent card (`SpiralAgentCard`) with the app's avatar.
//
// A dumb view (plain data in, one closure out — never a ViewModel), per the
// reusable-component canon in docs CODEBASE/12 §1-2.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

/// How an ``AgentRow`` presents and what tapping it does.
enum AgentRowKind {
    /// Navigable row with a chevron (agent-sheet → capabilities).
    case navigate
    /// Tappable button row (add-agent picker → invite).
    case button
    /// Non-interactive, dimmed row showing a trailing spinner (invite in flight).
    case waiting
    /// Non-interactive, dimmed row (e.g. an agent already in the room).
    case disabled
    /// Non-interactive, FULL-opacity display row — Brief 0043 P4:
    /// another participant's agent, shown so everyone sees the room's
    /// tools but nobody edits someone else's (no chevron, no dimming).
    case readOnly
}

/// A single agent as Spiral's agent card in a list row: the avatar, the name,
/// what it is, its status and one line of facts, and a trailing chevron,
/// status ("In this chat") or spinner.
struct AgentRow: View {
    let title: String
    /// What the agent is: "Your personal assistant", or a role agent's role.
    var role: String?
    var presence: SpiralAgentStatus?
    /// One line of facts under the name (its tools, its address).
    var description: String?
    /// A trailing status in place of the chevron (e.g. "In this chat").
    var status: String?
    /// Stable id the avatar's initial is drawn from when there's no name (the agent MXID).
    let avatarContentID: String
    /// The agent's real avatar when it has one.
    var avatarURL: URL?
    var avatarSize = SpiralAvatarSize.small
    let mediaProvider: MediaProviderProtocol?
    var kind: AgentRowKind = .navigate
    let onTap: () -> Void

    var body: some View {
        ListRow(kind: .custom { content })
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .navigate, .button:
            Button(action: onTap) { card }
        case .readOnly:
            card
        case .waiting, .disabled:
            card
                .disabled(true)
        }
    }

    private var card: some View {
        SpiralAgentCard(name: title,
                        role: role,
                        status: presence,
                        details: description) {
            LoadableAvatarImage(url: avatarURL,
                                name: title,
                                contentID: avatarContentID,
                                avatarSize: .custom(avatarSize),
                                mediaProvider: mediaProvider)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        } accessory: {
            accessory
        }
    }

    @ViewBuilder
    private var accessory: some View {
        if let status {
            Text(status)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
        } else {
            switch kind {
            case .navigate:
                SpiralAgentCardChevron()
            case .waiting:
                ProgressView()
            case .button, .disabled, .readOnly:
                EmptyView()
            }
        }
    }
}

// MARK: - Previews

struct AgentRow_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        Form {
            Section {
                AgentRow(title: "Anna Sampleton · assistant",
                         role: "Your personal assistant",
                         presence: .online("Online"),
                         description: "4 chats · 2 tools",
                         avatarContentID: "@assistant:example.com",
                         avatarSize: SpiralAvatarSize.medium,
                         mediaProvider: nil,
                         kind: .navigate) { }
                AgentRow(title: "Sales · Acme Corp",
                         role: "Sales",
                         presence: .paused("Paused"),
                         avatarContentID: "@sales:example.com",
                         avatarSize: SpiralAvatarSize.medium,
                         mediaProvider: nil,
                         kind: .navigate) { }
            }
            Section {
                AgentRow(title: "Assistant",
                         description: "Translating to English",
                         avatarContentID: "@assistant:example.com",
                         mediaProvider: nil,
                         kind: .navigate) { }
                AgentRow(title: "Scribe",
                         description: "@scribe:example.com",
                         avatarContentID: "@scribe:example.com",
                         mediaProvider: nil,
                         kind: .button) { }
                AgentRow(title: "Assistant",
                         description: "@assistant:example.com",
                         status: "In this chat",
                         avatarContentID: "@assistant:example.com",
                         mediaProvider: nil,
                         kind: .disabled) { }
                AgentRow(title: "Scribe",
                         description: "@scribe:example.com",
                         avatarContentID: "@scribe:example.com",
                         mediaProvider: nil,
                         kind: .waiting) { }
            }
        }
        .spiralGroupedList()
        .previewDisplayName("Rows")

        Form {
            Section {
                SpiralAgentCard(layout: .profile,
                                name: "Anna Sampleton · assistant",
                                subtitle: "@assistant-owner:spiral.md",
                                role: "Your personal assistant",
                                status: .online("Online")) {
                    LoadableAvatarImage(url: nil, name: "Anna Sampleton", contentID: "@assistant-owner:spiral.md",
                                        avatarSize: .user(on: .memberDetails), mediaProvider: nil)
                } actions: {
                    HStack(spacing: CompoundDesignTokens.space3X) {
                        Button { } label: { Text("Message").frame(maxWidth: .infinity) }
                            .buttonStyle(.compound(.primary, size: .medium))
                        Button { } label: { Text("Add to chat").frame(maxWidth: .infinity) }
                            .buttonStyle(.compound(.secondary, size: .medium, isRaised: true))
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .spiralGroupedList()
        .previewDisplayName("Profile")
    }
}
