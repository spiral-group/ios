//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum UserProfileScreenViewModelAction {
    case openDirectChat(roomID: String)
    case startCall(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case dismiss
}

struct UserProfileScreenViewState: BindableState {
    let userID: String
    let isOwnUser: Bool
    let isPresentedModally: Bool
    
    var userProfile: UserProfile?
    var isIdentityKnown = false
    var isVerified: Bool?
    var permalink: URL?
    var dmRoomID: String?
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    var presence: UserPresence?
    // AGENT-PLATFORM (Brief 0078, ADR-0019 P5): a Spiral account's assistant may remember them.
    var canEraseAssistantMemory = false
    var isErasingAssistantMemory = false
    /// The person's own agents, loaded only when this is an agent's profile.
    var ownAgentMXIDs: Set<String>?
    var isReadingOwnAgents = false
    // AGENT-PLATFORM (decision 87): the person's agents that block them, and the one being unblocked.
    var agentBlocks: [AgentContactBlock] = []
    var unblockingAgentID: String?
    var agentBlocksRead = AgentBlocksRead.notRead

    var bindings: UserProfileScreenViewStateBindings
    
    var showVerifiedBadge: Bool {
        isVerified == true // We purposely show the badge on your own account for consistency with Web.
    }
    
    // AGENT-PLATFORM (Brief 0078): not on one's own profile, nor on one's own agents'.
    var showEraseAssistantMemorySection: Bool {
        canEraseAssistantMemory && userProfile != nil && !isOwnUser
            && AssistantMemoryEraser.offersErase(onProfileOf: userID, ownAgentMXIDs: ownAgentMXIDs)
    }

    // AGENT-PLATFORM (decision 87): where the erase is offered, by the erase's rule.
    var showAgentBlocksSection: Bool {
        showEraseAssistantMemorySection && !agentBlocks.isEmpty
    }
}

struct UserProfileScreenViewStateBindings {
    var alertInfo: AlertInfo<UserProfileScreenAlertType>?
    var inviteConfirmationUser: UserToInvite?
    
    /// A media item that will be previewed with QuickLook.
    var mediaPreviewItem: MediaPreviewItem?
}

enum UserProfileScreenViewAction {
    case displayAvatar(URL)
    case openDirectChat
    case createDirectChat
    case startCall(roomID: String, isVoiceCall: Bool)
    case dismiss
    case eraseAssistantMemory // AGENT-PLATFORM (Brief 0078): asks first.
    case unblockAgent(agentID: String) // AGENT-PLATFORM (decision 87): asks first.
    case appeared // AGENT-PLATFORM (decision 87): reads the blocks again.
}

enum UserProfileScreenAlertType: Hashable {
    case failedOpeningDirectChat
    case unknown
    case eraseAssistantMemory // AGENT-PLATFORM (Brief 0078)
    case unblockAgent // AGENT-PLATFORM (decision 87)
}
