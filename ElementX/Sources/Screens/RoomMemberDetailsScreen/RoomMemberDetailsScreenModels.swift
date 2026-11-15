//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum RoomMemberDetailsScreenViewModelAction {
    case openUserProfile
    case openDirectChat(roomID: String)
    case startCall(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case verifyUser(userID: String)
    case openAgentRow(AgentPageRow, card: AgentSpaceAgentCard) // AGENT-PLATFORM (Brief 0083, question 359)
}

struct RoomMemberDetailsScreenViewState: BindableState {
    let userID: String
    var memberDetails: RoomMemberDetails?
    var verificationState: UserIdentityVerificationState?
    var isOwnMemberDetails = false
    var isProcessingIgnoreRequest = false
    var dmRoomID: String?
    var isCallingEnabled = true
    
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    var presence: UserPresence?
    // AGENT-PLATFORM (Brief 0078, ADR-0019 P5): a Spiral account's assistant may remember them.
    var canEraseAssistantMemory = false
    var isErasingAssistantMemory = false
    var agentOwnership = AgentOwnership.unknown(isReading: false) // AGENT-PLATFORM (Brief 0083, question 359)
    // AGENT-PLATFORM (decision 87): the person's agents that block them, and the one being unblocked.
    var agentBlocks: [AgentContactBlock] = []
    var unblockingAgentID: String?
    var agentBlocksRead = AgentBlocksRead.notRead

    var bindings: RoomMemberDetailsScreenViewStateBindings
    
    var showVerifiedBadge: Bool {
        verificationState == .verified // We purposely show the badge on your own account for consistency with Web.
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359)
    var agentProfile: SpiralAgentProfile? {
        SpiralAgentProfile(userID: userID, ownership: agentOwnership)
    }
    
    var showVerifyIdentitySection: Bool {
        verificationState == .notVerified && !isOwnMemberDetails && agentProfile?.offersVerify != false // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    var showWithdrawVerificationSection: Bool {
        verificationState == .verificationViolation && !isOwnMemberDetails
    }
    
    // AGENT-PLATFORM (Brief 0078): not on one's own profile, nor on one's own agents'.
    var showEraseAssistantMemorySection: Bool {
        canEraseAssistantMemory && !isOwnMemberDetails
            && AssistantMemoryEraser.offersErase(onProfileOf: userID, ownership: agentOwnership)
    }

    // AGENT-PLATFORM (decision 87): where the erase is offered, by the erase's rule.
    var showAgentBlocksSection: Bool {
        showEraseAssistantMemorySection && !agentBlocks.isEmpty
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359)
    var showBlockUserSection: Bool {
        guard !isOwnMemberDetails else { return false }
        return agentProfile?.offersBlock(isBlocked: memberDetails?.isIgnored == true) ?? true
    }
}

struct RoomMemberDetailsScreenViewStateBindings {
    struct IgnoreUserAlertItem: AlertProtocol, Equatable {
        enum Action {
            case ignore
            case unignore
        }
        
        let action: Action
        /// AGENT-PLATFORM (decision 98): the owner's block reaches their agents.
        var mentionsAgents = false
        let cancelTitle = L10n.actionCancel
        
        var title: String {
            switch action {
            case .ignore: return L10n.screenRoomMemberDetailsBlockUser
            case .unignore: return L10n.screenRoomMemberDetailsUnblockUser
            }
        }
        
        var confirmationTitle: String {
            switch action {
            case .ignore: return L10n.screenRoomMemberDetailsBlockAlertAction
            case .unignore: return L10n.screenRoomMemberDetailsUnblockAlertAction
            }
        }
        
        var description: String {
            let description = switch action {
            case .ignore: L10n.screenRoomMemberDetailsBlockAlertDescription
            case .unignore: L10n.screenRoomMemberDetailsUnblockAlertDescription
            }
            return mentionsAgents ? "\(description)\n\n\(OwnerBlocksSync.alertLine(for: action == .ignore))" : description
        }
        
        var viewAction: RoomMemberDetailsScreenViewAction {
            switch action {
            case .ignore: return .ignoreConfirmed
            case .unignore: return .unignoreConfirmed
            }
        }
    }
    
    var ignoreUserAlert: IgnoreUserAlertItem?
    var alertInfo: AlertInfo<RoomMemberDetailsScreenAlertType>?
    var inviteConfirmationUser: UserToInvite?
    
    /// A media item that will be previewed with QuickLook.
    var mediaPreviewItem: MediaPreviewItem?
}

enum RoomMemberDetailsScreenViewAction {
    case showUnignoreAlert
    case showIgnoreAlert
    case ignoreConfirmed
    case unignoreConfirmed
    case displayAvatar(URL)
    case openDirectChat
    case createDirectChat
    case startCall(roomID: String, isVoiceCall: Bool)
    case verifyUser
    case withdrawVerification
    case eraseAssistantMemory // AGENT-PLATFORM (Brief 0078): asks first.
    case unblockAgent(agentID: String) // AGENT-PLATFORM (decision 87): asks first.
    case appeared // AGENT-PLATFORM (decision 87): reads the blocks again.
    case openAgentRow(AgentPageRow) // AGENT-PLATFORM (Brief 0083, question 359)
}

enum RoomMemberDetailsScreenAlertType: Hashable {
    case failedOpeningDirectChat
    case unknown
    case eraseAssistantMemory // AGENT-PLATFORM (Brief 0078)
    case unblockAgent // AGENT-PLATFORM (decision 87)
}
