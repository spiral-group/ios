//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 87): the owner undoes an agent's block of a person
// from that person's profile, over REST. Never a chat tool, so the model can
// never unblock anyone.
//

import SwiftUI

/// One of the person's agents that blocks a contact (`GET /me/blocks`).
nonisolated struct AgentContactBlock: Equatable, Identifiable {
    let agentID: String
    let agentMXID: String
    let agentName: String
    let blockedAt: Date

    var id: String {
        agentID
    }
}

/// One person an agent blocks (`GET /agents/{id}/blocks`, decision 194).
nonisolated struct AgentBlockedContact: Equatable, Identifiable {
    let contactMXID: String
    /// Their display name when the platform could read their profile.
    let displayName: String?
    let blockedAt: Date

    var id: String {
        contactMXID
    }

    var name: String {
        displayName ?? contactMXID
    }
}

/// One page of the people an agent blocks, newest block first.
nonisolated struct AgentBlockedContactsPage: Equatable {
    let blocks: [AgentBlockedContact]
    /// Set only when the page filled its limit: more may follow.
    let nextCursor: String?
}

/// Where a profile's read of the blocks stands. A failed read is never taken
/// for "not blocked": the next trigger reads again.
nonisolated enum AgentBlocksRead: Equatable {
    case notRead
    case reading
    case read
    case failed
}

/// Which of the person's agents block a contact, and undoing one agent's block.
/// Shown where the erase is (`AssistantMemoryEraser.offersErase`): never on the
/// person's own profile or their own agents'. Separate from Element's Block
/// user, which is the Matrix ignore list.
struct AgentBlocks {
    let agentPlatformService: AgentPlatformServiceProtocol
    let userIndicatorController: UserIndicatorControllerProtocol

    /// `nil` when they could not be read: the profile keeps what it shows and
    /// reads again on its next trigger.
    func blocks(ofContact contactMXID: String) async -> [AgentContactBlock]? {
        switch await agentPlatformService.listAgentBlocks(ofContact: contactMXID) {
        case .success(let blocks):
            return blocks
        case .failure(let error):
            MXLog.error("Reading the agents' blocks of a contact failed: \(error)")
            return nil
        }
    }

    /// The confirmation names the person and the agent, and what follows.
    func confirmation<T: Hashable>(id: T, block: AgentContactBlock, contactName: String, onUnblock: @escaping () -> Void) -> AlertInfo<T> {
        AlertInfo(id: id,
                  title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertTitle(contactName, block.agentName),
                  message: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAlertMessage(block.agentName),
                  primaryButton: .init(title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAction, action: onUnblock),
                  secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }

    /// Whether the agent no longer blocks them. A toast says so either way.
    @discardableResult
    func unblock(_ block: AgentContactBlock, contactMXID: String) async -> Bool {
        switch await agentPlatformService.unblockContact(contactMXID, forAgent: block.agentID) {
        case .success:
            MXLog.info("Unblocked a contact for agent \(block.agentID)")
            userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockDone(block.agentName),
                                                          icon: \.checkCircle))
            return true
        case .failure(let error):
            MXLog.error("Unblocking a contact for agent \(block.agentID) failed: \(error)")
            userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenRoomMemberDetailsAgentUnblockFailed))
            return false
        }
    }
}
