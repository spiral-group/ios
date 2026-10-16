//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0035/0036 / ADR-0048), not
// present upstream. One canonical agent avatar row, shared by the agent-sheet
// (own agents in the room) and the add-agent picker (own agents to invite).
// Both screens previously hand-rolled the same `ListRow(.avatar)` +
// `LoadableAvatarImage(avatarSize: .custom(32))`; this is that row, once.
//
// A dumb view (plain data in, one closure out — never a ViewModel), per the
// reusable-component canon in docs CODEBASE/12 §1-2. The `kind` enum carries
// every presentation the two callers need today plus a `.destructive` case so
// a future owner-side "remove agent" row lands here rather than re-forking the
// avatar row.
//

import Compound
import SwiftUI

/// How an ``AgentRow`` presents and what tapping it does.
enum AgentRowKind {
    /// Navigable row with a chevron (agent-sheet → capabilities).
    case navigate
    /// Tappable button row (add-agent picker → invite).
    case button
    /// Non-interactive row showing a trailing spinner (invite in flight).
    case waiting
    /// Non-interactive, dimmed row (e.g. an agent already in the room).
    case disabled
    /// Non-interactive, FULL-opacity display row — Brief 0043 P4:
    /// another participant's agent, shown so everyone sees the room's
    /// tools but nobody edits someone else's (no chevron, no dimming).
    case readOnly
    /// Destructive button row (owner-side remove — reserved for future use).
    case destructive
}

/// A single agent as a Compound avatar row: avatar + name, an optional
/// description line, and an optional trailing status string (e.g. "In this
/// chat").
struct AgentRow: View {
    let title: String
    var description: String?
    var status: String?
    /// Stable id the avatar colour/initials are derived from (the agent MXID).
    let avatarContentID: String
    /// The agent's real avatar when it has one. Was hard-coded to `nil`, so
    /// every agent everywhere rendered as initials even when it had a
    /// picture set.
    var avatarURL: URL?
    let mediaProvider: MediaProviderProtocol?
    var kind: AgentRowKind = .navigate
    let onTap: () -> Void

    var body: some View {
        switch kind {
        case .navigate:
            ListRow(label: label(role: nil), kind: .navigationLink(action: onTap))
        case .button:
            ListRow(label: label(role: nil), kind: .button(action: onTap))
        case .waiting:
            ListRow(label: label(role: nil), details: .isWaiting(true), kind: .label)
                .disabled(true)
        case .disabled:
            ListRow(label: label(role: nil), kind: .label)
                .disabled(true)
        case .readOnly:
            ListRow(label: label(role: nil), kind: .label)
        case .destructive:
            ListRow(label: label(role: .destructive), kind: .button(action: onTap))
        }
    }

    // MARK: - Private

    private func label(role: ListRowLabel<LoadableAvatarImage>.Role?) -> ListRowLabel<LoadableAvatarImage> {
        .avatar(title: title,
                status: status,
                description: description,
                icon: LoadableAvatarImage(url: avatarURL,
                                          name: title,
                                          contentID: avatarContentID,
                                          avatarSize: .custom(32),
                                          mediaProvider: mediaProvider),
                role: role)
    }
}

// MARK: - Previews

struct AgentRow_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        Form {
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
                AgentRow(title: "Assistant",
                         description: "Remove from this chat",
                         avatarContentID: "@assistant:example.com",
                         mediaProvider: nil,
                         kind: .destructive) { }
            }
        }
        .compoundList()
    }
}
