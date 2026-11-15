//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the agent's rows the Agents tab shares with the chat's page and the
// profile pages.
//

import Compound
import SpiralComponents
import SwiftUI

/// Activity and Usage, which open screens.
struct AgentActivityRows: View {
    let onActivity: () -> Void
    let onUsage: () -> Void
    
    var body: some View {
        ListRow(label: .default(title: UntranslatedL10n.actionAgentActivity, icon: \.history),
                kind: .navigationLink(action: onActivity))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.activity)
        ListRow(label: .default(title: UntranslatedL10n.actionAgentUsage, icon: \.chart),
                kind: .navigationLink(action: onUsage))
            .accessibilityIdentifier(A11yIdentifiers.agentDetailScreen.usage)
    }
}

/// The chats an agent is in; a row opens the agent in that chat.
struct AgentChatsSection: View {
    let rooms: [AgentRoomEntry]
    /// The agent's screen names the section; on the chats screen the title does.
    var showsHeader = true
    var emptyTitle = UntranslatedL10n.screenAgentDetailNoRooms
    let title: (AgentRoomEntry) -> String
    let onSelect: (AgentRoomEntry) -> Void
    
    var body: some View {
        Section {
            if rooms.isEmpty {
                ListRow(label: .plain(title: emptyTitle),
                        kind: .label)
            } else {
                ForEach(rooms) { room in
                    ListRow(label: .default(title: title(room),
                                            description: room.toolsLine,
                                            icon: room.kind == "dm" ? \.userProfile : \.chat),
                            kind: .navigationLink {
                                onSelect(room)
                            })
                }
            }
        } header: {
            if showsHeader {
                Text(UntranslatedL10n.screenAgentDetailChatsSection)
                    .compoundListSectionHeader()
            }
        }
    }
}

/// `AgentChatsSection` while the chats are read: its rows in their own shape, as many as the card counts, after a
/// short delay (decision 330). An agent in no chat has one row there too, the one that says so.
struct AgentChatsLoadingSection: View {
    /// The card's `roomCount`.
    let count: Int
    var showsHeader = true
    
    // Lengths in characters, cycled so that the rows don't read as one stamp.
    private static let titleLengths = [14, 9, 17, 11]
    private static let descriptionLengths = [19, 15, 22, 17]
    
    var body: some View {
        Section {
            ForEach(0..<max(count, 1), id: \.self) { index in
                SpiralPreloader(label: L10n.commonLoading) {
                    row(index)
                }
                .accessibilityHidden(index > 0) // One "Loading…" for the section.
            }
        } header: {
            if showsHeader {
                Text(UntranslatedL10n.screenAgentDetailChatsSection)
                    .compoundListSectionHeader()
            }
        }
    }
    
    @ViewBuilder
    private func row(_ index: Int) -> some View {
        let title = String(repeating: "0", count: Self.titleLengths[index % Self.titleLengths.count])
        if count == 0 {
            ListRow(label: .plain(title: title), kind: .label)
        } else {
            ListRow(label: .default(title: title,
                                    description: String(repeating: "0", count: Self.descriptionLengths[index % Self.descriptionLengths.count]),
                                    icon: \.chat),
                    kind: .navigationLink { })
        }
    }
}
