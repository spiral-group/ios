//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomMemberDetailsScreen: View {
    @ObservedObject var context: RoomMemberDetailsScreenViewModel.Context
    
    var body: some View {
        Form {
            headerSection
            
            if context.viewState.showVerifyIdentitySection {
                verificationSection
            }
            
            // AGENT-PLATFORM (Brief 0078, ADR-0019 P5)
            if context.viewState.showEraseAssistantMemorySection {
                eraseAssistantMemorySection
            }
            
            // AGENT-PLATFORM (decision 87): above Element's Block user, which is a different thing.
            if context.viewState.showAgentBlocksSection {
                agentBlocksSection
            }
            
            if context.viewState.memberDetails != nil, !context.viewState.isOwnMemberDetails {
                blockUserSection
            }
        }
        .compoundList()
        .navigationTitle(L10n.screenRoomMemberDetailsTitle)
        .alert(item: $context.ignoreUserAlert, actions: blockUserAlertActions, message: blockUserAlertMessage)
        .alert(item: $context.alertInfo)
        .sheet(item: $context.inviteConfirmationUser) { user in
            SendInviteConfirmationView(userToInvite: user,
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
        if let memberDetails = context.viewState.memberDetails {
            AvatarHeaderView(member: memberDetails,
                             isVerified: context.viewState.showVerifiedBadge,
                             avatarSize: .user(on: .memberDetails),
                             mediaProvider: context.mediaProvider) { url in
                context.send(viewAction: .displayAvatar(url))
            } footer: {
                VStack(spacing: 24) {
                    if context.viewState.showWithdrawVerificationSection {
                        withdrawVerificationSection
                    }
                    
                    otherUserFooter
                        .padding(.top, 8)
                }
            }
            .presence(context.viewState.presence) // AGENT-PLATFORM (Brief 0072)
        } else {
            AvatarHeaderView(user: UserProfile(userID: context.viewState.userID),
                             isVerified: context.viewState.showVerifiedBadge,
                             avatarSize: .user(on: .memberDetails),
                             mediaProvider: context.mediaProvider) { }
        }
    }
    
    private var withdrawVerificationSection: some View {
        VStack(spacing: 16) {
            if let memberDetails = context.viewState.memberDetails {
                Text(L10n.cryptoIdentityChangeProfilePinViolation(memberDetails.name ?? memberDetails.id))
                    .foregroundStyle(.compound.textCriticalPrimary)
                    .font(.compound.bodyMDSemibold)
            } else {
                Text(L10n.cryptoIdentityChangeProfilePinViolation(context.viewState.userID))
                    .foregroundStyle(.compound.textCriticalPrimary)
                    .font(.compound.bodyMDSemibold)
            }
            
            Button {
                context.send(viewAction: .withdrawVerification)
            } label: {
                Text(L10n.cryptoIdentityChangeWithdrawVerificationAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.secondary, size: .medium))
        }
        .padding(.horizontal, 16)
    }
    
    private var otherUserFooter: some View {
        HStack(spacing: 8) {
            if context.viewState.memberDetails != nil, !context.viewState.isOwnMemberDetails {
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
            
            if let permalink = context.viewState.memberDetails?.permalink {
                ShareLink(item: permalink) {
                    CompoundIcon(\.shareIos)
                }
                .buttonStyle(FormActionButtonStyle(title: L10n.actionShare))
            }
        }
    }
    
    var verificationSection: some View {
        Section {
            ListRow(label: .default(title: L10n.commonVerifyUser, icon: \.lock), kind: .button {
                context.send(viewAction: .verifyUser)
            })
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
                    .accessibilityIdentifier(A11yIdentifiers.roomMemberDetailsScreen.eraseAssistantMemory)
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
    
    @ViewBuilder
    private var blockUserSection: some View {
        if let memberDetails = context.viewState.memberDetails {
            let title = memberDetails.isIgnored ? L10n.screenRoomMemberDetailsUnblockUser : L10n.screenRoomMemberDetailsBlockUser
            let action: RoomMemberDetailsScreenViewAction = memberDetails.isIgnored ? .showUnignoreAlert : .showIgnoreAlert
            let accessibilityIdentifier = memberDetails.isIgnored ? A11yIdentifiers.roomMemberDetailsScreen.unignore : A11yIdentifiers.roomMemberDetailsScreen.ignore
            
            Section {
                ListRow(label: .default(title: title,
                                        icon: \.block,
                                        role: memberDetails.isIgnored ? nil : .destructive),
                        details: .isWaiting(context.viewState.isProcessingIgnoreRequest),
                        kind: .button {
                            context.send(viewAction: action)
                        })
                        .accessibilityIdentifier(accessibilityIdentifier)
                        .disabled(context.viewState.isProcessingIgnoreRequest)
            }
        }
    }
    
    @ViewBuilder
    private func blockUserAlertActions(_ item: RoomMemberDetailsScreenViewStateBindings.IgnoreUserAlertItem) -> some View {
        Button(item.cancelTitle, role: .cancel) { }
        Button(item.confirmationTitle,
               role: item.action == .ignore ? .destructive : nil) {
            context.send(viewAction: item.viewAction)
        }
    }
    
    private func blockUserAlertMessage(_ item: RoomMemberDetailsScreenViewStateBindings.IgnoreUserAlertItem) -> some View {
        Text(item.description)
    }
}

// MARK: - Previews

struct RoomMemberDetailsScreen_Previews: PreviewProvider, TestablePreview {
    static let verifiedUserViewModel = makeViewModel(member: .mockDan)
    static let verificationViolationUserViewModel = makeViewModel(member: .mockBob)
    static let otherUserViewModel = makeViewModel(member: .mockAlice)
    static let accountOwnerViewModel = makeViewModel(member: .mockMe)
    static let ignoredUserViewModel = makeViewModel(member: .mockIgnored)
    static let spiralContactViewModel = makeViewModel(member: .mockAlice, hasAssistant: true) // AGENT-PLATFORM (Brief 0078)
    static let blockedByAgentViewModel = makeViewModel(member: .mockAlice, hasAssistant: true, agentBlocks: [previewAgentBlock])
    // AGENT-PLATFORM (decision 87): one of the person's agents blocks them.
    static let previewAgentBlock = AgentContactBlock(agentID: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
                                                     agentMXID: "@aria:spiral.md",
                                                     agentName: "Aria",
                                                     blockedAt: Date(timeIntervalSince1970: 1_791_709_200))
    
    static var previews: some View {
        RoomMemberDetailsScreen(context: verifiedUserViewModel.context)
            .snapshotPreferences(expect: verifiedUserViewModel.context.$viewState.map { state in
                state.verificationState == .verified
            })
            .previewDisplayName("Verified User")
        
        RoomMemberDetailsScreen(context: verificationViolationUserViewModel.context)
            .snapshotPreferences(expect: verificationViolationUserViewModel.context.$viewState.map { state in
                state.verificationState == .verificationViolation
            })
            .previewDisplayName("Verification Violation User")
        
        RoomMemberDetailsScreen(context: otherUserViewModel.context)
            .snapshotPreferences(expect: otherUserViewModel.context.$viewState.map { state in
                state.memberDetails?.role == .user && state.dmRoomID != nil
            })
            .previewDisplayName("Other User")
        
        RoomMemberDetailsScreen(context: accountOwnerViewModel.context)
            .snapshotPreferences(expect: accountOwnerViewModel.context.$viewState.map { state in
                state.isOwnMemberDetails == true
            })
            .previewDisplayName("Account Owner")
        
        RoomMemberDetailsScreen(context: ignoredUserViewModel.context)
            .snapshotPreferences(expect: ignoredUserViewModel.context.$viewState.map { state in
                state.memberDetails?.isIgnored ?? false && state.dmRoomID != nil
            })
            .previewDisplayName("Ignored User")
        
        // AGENT-PLATFORM (Brief 0078): a Spiral account can erase what its assistant remembers.
        RoomMemberDetailsScreen(context: spiralContactViewModel.context)
            .snapshotPreferences(expect: spiralContactViewModel.context.$viewState.map { state in
                state.showEraseAssistantMemorySection && state.dmRoomID != nil
            })
            .previewDisplayName("Other User With Assistant")
        
        // AGENT-PLATFORM (decision 87): the owner can undo an agent's block.
        RoomMemberDetailsScreen(context: blockedByAgentViewModel.context)
            .snapshotPreferences(expect: blockedByAgentViewModel.context.$viewState.map { state in
                state.showAgentBlocksSection && state.dmRoomID != nil
            })
            .previewDisplayName("Blocked By Agent")
    }
    
    static func makeViewModel(member: RoomMemberProxyMock, hasAssistant: Bool = false,
                              agentBlocks: [AgentContactBlock] = []) -> RoomMemberDetailsScreenViewModel {
        let roomProxyMock = JoinedRoomProxyMock(.init(name: ""))
        roomProxyMock.getMemberUserIDReturnValue = .success(member)
        
        let clientProxyMock = ClientProxyMock(.init())
        
        clientProxyMock.userIdentityForFallBackToServerClosure = { userID, _ in
            let identity = switch userID {
            case RoomMemberProxyMock.mockDan.userID:
                UserIdentityProxyMock(.init(verificationState: .verified))
            case RoomMemberProxyMock.mockBob.userID:
                UserIdentityProxyMock(.init(verificationState: .verificationViolation))
            default:
                UserIdentityProxyMock(.init())
            }
            
            return .success(identity)
        }
        
        // to avoid mock the call state for the account owner test case
        if member.userID != RoomMemberProxyMock.mockMe.userID {
            clientProxyMock.directRoomForUserIDReturnValue = .success("roomID")
        }
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxyMock))
        if hasAssistant {
            let agentPlatformService = AgentPlatformServiceMock()
            agentPlatformService.listAgentBlocksOfContactReturnValue = .success(agentBlocks) // AGENT-PLATFORM (decision 87)
            userSession.agentPlatformService = agentPlatformService
        }
        
        return RoomMemberDetailsScreenViewModel(userID: member.userID,
                                                roomProxy: roomProxyMock,
                                                userSession: userSession,
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                analytics: AnalyticsServiceMock(.init()))
    }
}
