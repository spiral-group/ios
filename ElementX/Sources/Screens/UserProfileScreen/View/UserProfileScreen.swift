//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct UserProfileScreen: View {
    @Bindable var context: UserProfileScreenViewModel.Context
    
    var body: some View {
        Form {
            headerSection
            
            // AGENT-PLATFORM (Brief 0078, ADR-0019 P5)
            if context.viewState.showEraseAssistantMemorySection {
                eraseAssistantMemorySection
            }
            
            // AGENT-PLATFORM (decision 87)
            if context.viewState.showAgentBlocksSection {
                agentBlocksSection
            }
        }
        .compoundList()
        .navigationTitle(L10n.screenRoomMemberDetailsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .alert(item: $context.alertInfo)
        .sheet(item: $context.inviteConfirmationUser) { userToInvite in
            SendInviteConfirmationView(userToInvite: userToInvite,
                                       mediaProvider: context.mediaProvider) {
                context.send(viewAction: .createDirectChat)
            }
        }
        .track(screen: .User)
        .interactiveQuickLook(item: $context.mediaPreviewItem, allowEditing: false)
        .onAppear { context.send(viewAction: .appeared) } // AGENT-PLATFORM (decision 87): blocks may have changed meanwhile.
    }
    
    // MARK: - Private
    
    @ViewBuilder
    private var headerSection: some View {
        if let userProfile = context.viewState.userProfile {
            AvatarHeaderView(user: userProfile,
                             isVerified: context.viewState.showVerifiedBadge,
                             avatarSize: .user(on: .memberDetails),
                             mediaProvider: context.mediaProvider) { url in
                context.send(viewAction: .displayAvatar(url))
            } footer: {
                otherUserFooter
                    .padding(.top, 8)
            }
            .presence(context.viewState.presence) // AGENT-PLATFORM (Brief 0072)
        } else {
            AvatarHeaderView(user: UserProfile(userID: context.viewState.userID),
                             isVerified: context.viewState.showVerifiedBadge,
                             avatarSize: .user(on: .memberDetails),
                             mediaProvider: context.mediaProvider) { }
        }
    }
    
    private var otherUserFooter: some View {
        HStack(spacing: 8) {
            if context.viewState.userProfile != nil, !context.viewState.isOwnUser {
                Button {
                    context.send(viewAction: .openDirectChat)
                } label: {
                    CompoundIcon(\.chat)
                }
                .buttonStyle(FormActionButtonStyle(title: L10n.commonMessage))
                .accessibilityIdentifier(A11yIdentifiers.roomMemberDetailsScreen.directChat)
            }
            
            if let roomID = context.viewState.dmRoomID {
                Button {
                    context.send(viewAction: .startCall(roomID: roomID, isVoiceCall: true))
                } label: {
                    CompoundIcon(\.voiceCall)
                }
                .accessibilityLabel(L10n.a11yStartVoiceCall)
                .buttonStyle(FormActionButtonStyle(title: L10n.actionCall))
                
                Button {
                    context.send(viewAction: .startCall(roomID: roomID, isVoiceCall: false))
                } label: {
                    CompoundIcon(\.videoCall)
                }
                .accessibilityLabel(L10n.a11yStartVideoCall)
                .buttonStyle(FormActionButtonStyle(title: L10n.commonVideo))
            }
            
            if let permalink = context.viewState.permalink {
                ShareLink(item: permalink) {
                    CompoundIcon(\.shareIos)
                }
                .buttonStyle(FormActionButtonStyle(title: L10n.actionShare))
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0078, ADR-0019 P5): what the person's assistant remembers about them.
    private var eraseAssistantMemorySection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenRoomMemberDetailsEraseAssistantMemory,
                                    icon: \.delete,
                                    role: .destructive),
                    details: .isWaiting(context.viewState.isErasingAssistantMemory),
                    kind: .button {
                        context.send(viewAction: .eraseAssistantMemory)
                    })
                    .disabled(context.viewState.isErasingAssistantMemory)
        }
    }
    
    // AGENT-PLATFORM (decision 87): the person's agents that block them, each undone here.
    private var agentBlocksSection: some View {
        Section {
            ForEach(context.viewState.agentBlocks) { block in
                ListRow(label: .default(title: UntranslatedL10n.screenRoomMemberDetailsAgentBlockTitle(block.agentName), icon: \.block),
                        details: .title(UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAction,
                                        isWaiting: context.viewState.unblockingAgentID == block.agentID),
                        kind: .button {
                            context.send(viewAction: .unblockAgent(agentID: block.agentID))
                        })
                        .disabled(context.viewState.unblockingAgentID != nil)
            }
        } footer: {
            Text(UntranslatedL10n.screenRoomMemberDetailsAgentBlockFooter)
                .compoundListSectionFooter()
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.isPresentedModally {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionDone) {
                    context.send(viewAction: .dismiss)
                }
            }
        }
    }
}

// MARK: - Previews

@available(iOS 26.0, *)
struct UserProfileScreen_Previews: PreviewProvider, TestablePreview {
    static let verifiedUserViewModel = makeViewModel(userID: RoomMemberProxyMock.mockDan.userID)
    static let otherUserViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID)
    static let accountOwnerViewModel = makeViewModel(userID: RoomMemberProxyMock.mockMe.userID)
    static let spiralContactViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: true) // AGENT-PLATFORM (Brief 0078)
    static let blockedByAgentViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: true,
                                                       agentBlocks: [previewAgentBlock])
    // AGENT-PLATFORM (decision 87): one of the person's agents blocks them.
    static let previewAgentBlock = AgentContactBlock(agentID: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
                                                     agentMXID: "@aria:spiral.md",
                                                     agentName: "Aria",
                                                     blockedAt: Date(timeIntervalSince1970: 1_791_709_200))
    
    static var previews: some View {
        UserProfileScreen(context: verifiedUserViewModel.context)
            .snapshotPreferences(expect: verifiedUserViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Verified User")
        
        UserProfileScreen(context: otherUserViewModel.context)
            .snapshotPreferences(expect: otherUserViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Other User")
        
        UserProfileScreen(context: accountOwnerViewModel.context)
            .snapshotPreferences(expect: accountOwnerViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Account Owner")
        
        // AGENT-PLATFORM (Brief 0078): a Spiral account can erase what its assistant remembers.
        UserProfileScreen(context: spiralContactViewModel.context)
            .snapshotPreferences(expect: spiralContactViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Other User With Assistant")
        
        // AGENT-PLATFORM (decision 87): the owner can undo an agent's block.
        UserProfileScreen(context: blockedByAgentViewModel.context)
            .snapshotPreferences(expect: blockedByAgentViewModel.context.observe(\.viewState.showAgentBlocksSection))
            .previewDisplayName("Blocked By Agent")
    }
    
    static func makeViewModel(userID: String, hasAssistant: Bool = false,
                              agentBlocks: [AgentContactBlock] = []) -> UserProfileScreenViewModel {
        let clientProxyMock = ClientProxyMock(.init())
        
        clientProxyMock.userIdentityForFallBackToServerClosure = { userID, _ in
            let identity = switch userID {
            case RoomMemberProxyMock.mockDan.userID:
                UserIdentityProxyMock(.init(verificationState: .verified))
            default:
                UserIdentityProxyMock(.init())
            }
            
            return .success(identity)
        }
        
        if userID != RoomMemberProxyMock.mockMe.userID {
            clientProxyMock.directRoomForUserIDReturnValue = .success("roomID")
        }
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxyMock))
        if hasAssistant {
            let agentPlatformService = AgentPlatformServiceMock()
            agentPlatformService.listAgentBlocksOfContactReturnValue = .success(agentBlocks) // AGENT-PLATFORM (decision 87)
            userSession.agentPlatformService = agentPlatformService
        }
        
        return UserProfileScreenViewModel(userID: userID,
                                          isPresentedModally: false,
                                          userSession: userSession,
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          analytics: AnalyticsServiceMock(.init()))
    }
}
