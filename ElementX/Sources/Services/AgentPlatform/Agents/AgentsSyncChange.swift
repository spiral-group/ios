//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync, the Agents tab's kinds (contract v0.3 § 5
// "Agents", ADR-0092's amendment B7b). Ids only: each change says what to
// read again. A kind this build does not know, or one without the id it must
// name, is skipped (decision 96). Uuids are lower-cased, like every id the
// app holds; room ids are Matrix's and stay as they are.
//

import Foundation

nonisolated enum AgentsSyncChange: Equatable {
    /// An agent created, deleted, or a column the app shows changed (not its
    /// `last_active_at`: the app ages the dot itself).
    case agentUpdated(agentID: String, spaceID: String?)
    case agentConfig(agentID: String)
    case spaceUpdated(spaceID: String)
    case agentRooms(agentID: String, roomID: String)
    case agentTools(agentID: String, roomID: String)
    /// `nil` when the row's agent is gone (B7b departure 5).
    case agentActivity(agentID: String?)
    case agentUsage(agentID: String?)
    case agentBlocks(agentID: String)
    case agentOutreach(agentID: String)
    case approvalChanged(approvalID: String)
    case verificationChanged(verificationID: String, agentID: String?)
    case notificationVisitor(messageID: String?)
    case notificationSeen
    /// A public agent's profile moved; the id is the agent's, no owner (M4).
    case profilePublic(agentID: String)

    /// The ids a change of the log may carry.
    struct IDs {
        var agent: String?
        var space: String?
        var room: String?
        var approval: String?
        var verification: String?
        var message: String?
    }

    /// `nil` for a kind that is not the Agents tab's, or one missing what it must name.
    init?(kind: String, ids: IDs) {
        let agent = ids.agent?.lowercased()
        switch kind {
        case "agent.updated":
            guard let agent else { return nil }
            self = .agentUpdated(agentID: agent, spaceID: ids.space?.lowercased())
        case "agent.config":
            guard let agent else { return nil }
            self = .agentConfig(agentID: agent)
        case "space.updated":
            guard let space = ids.space?.lowercased() else { return nil }
            self = .spaceUpdated(spaceID: space)
        case "agent.rooms":
            guard let agent, let room = ids.room else { return nil }
            self = .agentRooms(agentID: agent, roomID: room)
        case "agent.tools":
            guard let agent, let room = ids.room else { return nil }
            self = .agentTools(agentID: agent, roomID: room)
        case "agent.activity":
            self = .agentActivity(agentID: agent)
        case "agent.usage":
            self = .agentUsage(agentID: agent)
        case "agent.blocks":
            guard let agent else { return nil }
            self = .agentBlocks(agentID: agent)
        case "agent.outreach":
            guard let agent else { return nil }
            self = .agentOutreach(agentID: agent)
        case "approval.changed":
            guard let approval = ids.approval?.lowercased() else { return nil }
            self = .approvalChanged(approvalID: approval)
        case "verification.changed":
            guard let verification = ids.verification?.lowercased() else { return nil }
            self = .verificationChanged(verificationID: verification, agentID: agent)
        case "notification.visitor":
            self = .notificationVisitor(messageID: ids.message?.lowercased())
        case "notification.seen":
            self = .notificationSeen
        case "profile.public":
            guard let agent else { return nil }
            self = .profilePublic(agentID: agent)
        default:
            return nil
        }
    }

    var kind: String {
        switch self {
        case .agentUpdated: "agent.updated"
        case .agentConfig: "agent.config"
        case .spaceUpdated: "space.updated"
        case .agentRooms: "agent.rooms"
        case .agentTools: "agent.tools"
        case .agentActivity: "agent.activity"
        case .agentUsage: "agent.usage"
        case .agentBlocks: "agent.blocks"
        case .agentOutreach: "agent.outreach"
        case .approvalChanged: "approval.changed"
        case .verificationChanged: "verification.changed"
        case .notificationVisitor: "notification.visitor"
        case .notificationSeen: "notification.seen"
        case .profilePublic: "profile.public"
        }
    }
}
