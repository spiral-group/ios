//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): an agent's page tells it from a person's: the badge and a role line for
// every agent, and the owner's rows for the person's own.
//

import Foundation

/// An agent as the chat's page and the profile pages show it.
struct SpiralAgentProfile: Equatable {
    let userID: String
    /// What stands between the name and the status.
    let roleLine: String?
    let ownership: AgentOwnership
    
    /// The agent's card, when it is the person's own.
    var ownCard: AgentSpaceAgentCard? {
        if case .own(let card) = ownership { card } else { nil }
    }
    
    /// Whose it is isn't known yet: the owner's rows hold a placeholder, and nothing is offered that may go.
    var isReadingOwnership: Bool {
        ownership == .unknown(isReading: true)
    }
    
    /// `nil` for a person.
    init?(userID: String, ownership: AgentOwnership) {
        guard let idKind = SpiralAppPostSession.agentIDKind(userID) else { return nil }
        self.userID = userID
        self.ownership = ownership
        roleLine = if case .own(let card) = ownership { card.roleLine ?? idKind.roleLine } else { idKind.roleLine }
    }
    
    /// The agent's own screen on the Agents tab: its role line is the card's, and the card is the person's own.
    init(userID: String, roleLine: String?, ownCard: AgentSpaceAgentCard) {
        self.userID = userID
        self.roleLine = roleLine
        ownership = .own(ownCard)
    }
    
    /// Not the person's own agent, nor one that may yet turn out to be. After a failed read it is offered:
    /// a failed read must not hide what protects the person from someone else's agent.
    var offersVerify: Bool {
        ownCard == nil && !isReadingOwnership
    }
    
    /// As `offersVerify`; one blocked before keeps its way back.
    func offersBlock(isBlocked: Bool) -> Bool {
        offersVerify || isBlocked
    }
    
    /// The person's own assistant stays with their account, so its chat has no Leave.
    var offersLeave: Bool {
        if isReadingOwnership {
            return SpiralAppPostSession.agentIDKind(userID) != .assistant
        }
        return ownCard?.kind != "personal_assistant"
    }
}

/// The owner's entries on an agent's page, which open the Agents tab's screens.
enum AgentPageRow: Hashable {
    case activity
    case usage
    case chats
    /// The chat's Settings: the agent's own screen, as the Agents tab opens it (question 391).
    case settings
}

private extension SpiralAppPostSession.AgentIDKind {
    /// All that's known of someone else's agent: its ID says which of the two it is.
    var roleLine: String {
        switch self {
        case .assistant: UntranslatedL10n.screenProfileAgentKindAssistant
        case .agent: UntranslatedL10n.screenProfileAgentKindAgent
        }
    }
}
