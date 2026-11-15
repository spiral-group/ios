//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the first card of the person's own agent's page.
//

import Compound
import SpiralComponents
import SwiftUI

/// Activity, Usage and Chats, as the agent's screen has them on the Agents tab.
struct SpiralOwnAgentSection: View {
    let card: AgentSpaceAgentCard
    let onSelect: (AgentPageRow) -> Void
    
    var body: some View {
        Section {
            AgentActivityRows(onActivity: { onSelect(.activity) }, onUsage: { onSelect(.usage) })
            
            ListRow(label: .default(title: UntranslatedL10n.screenAgentDetailChatsSection, icon: \.chat),
                    details: .title(String(card.roomCount)),
                    kind: .navigationLink {
                        onSelect(.chats)
                    })
        }
    }
}

/// The owner's rows' place while whose the agent is isn't known: the rows themselves, redacted, so that they stand
/// exactly as tall and nothing below moves if the answer is that they're the person's.
struct SpiralOwnAgentPlaceholderSection: View {
    var body: some View {
        Section {
            row(title: UntranslatedL10n.actionAgentActivity, icon: \.history)
            row(title: UntranslatedL10n.actionAgentUsage, icon: \.chart)
            row(title: UntranslatedL10n.screenAgentDetailChatsSection, icon: \.chat)
        }
    }
    
    private func row(title: String, icon: KeyPath<CompoundIcons, Image>) -> some View {
        ListRow(label: .default(title: title, icon: icon), kind: .navigationLink { })
            .spiralLoadingSlot(true, label: L10n.commonLoading)
    }
}
