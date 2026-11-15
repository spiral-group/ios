//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083, question 359)
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct RoomMemberDetailsScreen: View {
    @ObservedObject var context: RoomMemberDetailsScreenViewModel.Context
    
    private var profile: UserProfile {
        // AGENT-PLATFORM (Brief 0083, question 359): the person's own agent's name is known before the member is.
        context.viewState.memberDetails.map(UserProfile.init(member:))
            ?? UserProfile(userID: context.viewState.userID, displayName: context.viewState.agentProfile?.ownCard?.displayName)
    }
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 344): Spiral's profile page, was a `Form` under Element's centred header.
        SpiralProfilePage(picture: .user(profile),
                          title: profile.displayName ?? profile.id,
                          mediaProvider: context.mediaProvider) {
            headerSection
            
            // AGENT-PLATFORM (Brief 0083, question 359): this page has no «More», so the handle stays, under the rows.
            if let card = context.viewState.agentProfile?.ownCard {
                SpiralOwnAgentSection(card: card) { row in
                    context.send(viewAction: .openAgentRow(row))
                }
            } else if context.viewState.agentProfile?.isReadingOwnership == true {
                SpiralOwnAgentPlaceholderSection()
            }
            
            infoSection
            
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
            
            if context.viewState.showBlockUserSection { // AGENT-PLATFORM (Brief 0083, question 359)
                blockUserSection
            }
        }
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
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the page's hero.
    @ViewBuilder
    private var headerSection: some View {
        if context.viewState.memberDetails != nil {
            SpiralProfileHero(picture: .user(profile),
                              title: profile.displayName ?? profile.id,
                              isVerified: context.viewState.showVerifiedBadge,
                              agent: context.viewState.agentProfile, // AGENT-PLATFORM (Brief 0083, question 359)
                              presence: context.viewState.presence, // AGENT-PLATFORM (Brief 0072)
                              userStatus: profile.status,
                              mediaProvider: context.mediaProvider) { url in
                context.send(viewAction: .displayAvatar(url))
            } actions: {
                otherUserFooter
            } footer: {
                if context.viewState.showWithdrawVerificationSection {
                    withdrawVerificationSection
                }
            }
        } else {
            SpiralProfileHero(picture: .user(profile),
                              title: profile.displayName ?? profile.id,
                              isVerified: context.viewState.showVerifiedBadge,
                              agent: context.viewState.agentProfile, // AGENT-PLATFORM (Brief 0083, question 359)
                              mediaProvider: context.mediaProvider) { _ in } actions: {
                if !context.viewState.isOwnMemberDetails { // AGENT-PLATFORM (Brief 0083, question 359)
                    SpiralProfileActionPlaceholder()
                }
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the handle, under a person's name before.
    @ViewBuilder
    private var infoSection: some View {
        // AGENT-PLATFORM (Brief 0083, question 359): the ID is known before the member is, so its card doesn't arrive late.
        if profile.displayName != nil || context.viewState.memberDetails == nil {
            Section {
                SpiralProfileInfoRow(caption: L10n.commonUsername) {
                    Text(profile.id)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private var withdrawVerificationSection: some View {
        VStack(spacing: 16) {
            // AGENT-PLATFORM (Brief 0083): on the canvas, as red on the page's field read 3:1 in light.
            Text(L10n.cryptoIdentityChangeProfilePinViolation(context.viewState.memberDetails?.name ?? context.viewState.memberDetails?.id ?? context.viewState.userID))
                .foregroundStyle(.compound.textCriticalPrimary)
                .font(.compound.bodyMDSemibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CompoundDesignTokens.space3X)
                .padding(.vertical, CompoundDesignTokens.space2X)
                .background(.compound.bgCanvasDefault, in: .rect(cornerRadius: SpiralRadius.block))
            
            Button {
                context.send(viewAction: .withdrawVerification)
            } label: {
                Text(L10n.cryptoIdentityChangeWithdrawVerificationAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.secondary, size: .medium, isRaised: true)) // AGENT-PLATFORM (Brief 0083, decision 329): on the list's grey.
        }
        .padding(.horizontal, 16)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the action row.
    @ViewBuilder
    private var otherUserFooter: some View {
        if context.viewState.memberDetails != nil, !context.viewState.isOwnMemberDetails {
            Button {
                context.send(viewAction: .openDirectChat)
            } label: {
                SpiralProfileActionLabel(title: L10n.commonMessage, icon: \.chat)
            }
            .buttonStyle(.spiralProfileAction)
            .accessibilityIdentifier(A11yIdentifiers.roomMemberDetailsScreen.directChat)
        }
        
        if let roomID = context.viewState.dmRoomID, context.viewState.isCallingEnabled {
            Button {
                context.send(viewAction: .startCall(roomID: roomID, isVoiceCall: true))
            } label: {
                SpiralProfileActionLabel(title: UntranslatedL10n.screenProfileActionCall, icon: \.voiceCall)
            }
            .accessibilityLabel(L10n.a11yStartVoiceCall)
            .buttonStyle(.spiralProfileAction)
            
            Button {
                context.send(viewAction: .startCall(roomID: roomID, isVoiceCall: false))
            } label: {
                SpiralProfileActionLabel(title: L10n.commonVideo, icon: \.videoCall)
            }
            .accessibilityLabel(L10n.a11yStartVideoCall)
            .buttonStyle(.spiralProfileAction)
        }
        
        if let permalink = context.viewState.memberDetails?.permalink {
            ShareLink(item: permalink) {
                SpiralProfileActionLabel(title: L10n.actionShare, icon: \.shareIos)
            }
            .buttonStyle(.spiralProfileAction)
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
        } else {
            // AGENT-PLATFORM (Brief 0083, question 359): the row keeps its place until the member says what it does.
            Section {
                ListRow(label: .default(title: L10n.screenRoomMemberDetailsBlockUser, icon: \.block, role: .destructive), kind: .label)
                    .spiralLoadingSlot(true, label: L10n.commonLoading)
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

struct RoomMemberDetailsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let verifiedUserViewModel = makeViewModel(member: .mockDan)
    static let verificationViolationUserViewModel = makeViewModel(member: .mockBob)
    static let otherUserViewModel = makeViewModel(member: .mockAlice)
    static let accountOwnerViewModel = makeViewModel(member: .mockMe)
    static let ignoredUserViewModel = makeViewModel(member: .mockIgnored)
    static let spiralContactViewModel = makeViewModel(member: .mockAlice, hasAssistant: true) // AGENT-PLATFORM (Brief 0078)
    static let blockedByAgentViewModel = makeViewModel(member: .mockAlice, hasAssistant: true, agentBlocks: [previewAgentBlock])
    // AGENT-PLATFORM (Brief 0083, question 359): an agent's page: the person's assistant, their role agent, someone else's.
    static let ownAssistantViewModel = makeViewModel(member: AgentProfileMock.member(AgentProfileMock.assistant), ownsAgents: true)
    static let ownRoleAgentViewModel = makeViewModel(member: AgentProfileMock.member(AgentProfileMock.salesAgent), ownsAgents: true)
    static let othersAgentViewModel = makeViewModel(member: AgentProfileMock.othersAgent, ownsAgents: true)
    static let readingAgentViewModel = makeViewModel(member: AgentProfileMock.member(AgentProfileMock.assistant), ownsAgents: true, spacesRead: .hangs)
    static let failedAgentViewModel = makeViewModel(member: AgentProfileMock.member(AgentProfileMock.assistant), ownsAgents: true, spacesRead: .fails)
    // AGENT-PLATFORM (decision 87): one of the person's agents blocks them.
    static let previewAgentBlock = AgentContactBlock(agentID: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
                                                     agentMXID: "@aria:spiral.md",
                                                     agentName: "Aria",
                                                     blockedAt: Date(timeIntervalSince1970: 1_791_709_200))
    
    static var previews: some View {
        ElementNavigationStack { RoomMemberDetailsScreen(context: verifiedUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: verifiedUserViewModel.context.$viewState.map { state in
                state.verificationState == .verified
            })
            .previewDisplayName("Verified User")
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: verificationViolationUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: verificationViolationUserViewModel.context.$viewState.map { state in
                state.verificationState == .verificationViolation
            })
            .previewDisplayName("Verification Violation User")
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: otherUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: otherUserViewModel.context.$viewState.map { state in
                state.memberDetails?.role == .user && state.dmRoomID != nil
            })
            .previewDisplayName("Other User")
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: accountOwnerViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: accountOwnerViewModel.context.$viewState.map { state in
                state.isOwnMemberDetails == true
            })
            .previewDisplayName("Account Owner")
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: ignoredUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: ignoredUserViewModel.context.$viewState.map { state in
                state.memberDetails?.isIgnored ?? false && state.dmRoomID != nil
            })
            .previewDisplayName("Ignored User")
        
        // AGENT-PLATFORM (Brief 0078): a Spiral account can erase what its assistant remembers.
        ElementNavigationStack { RoomMemberDetailsScreen(context: spiralContactViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: spiralContactViewModel.context.$viewState.map { state in
                state.showEraseAssistantMemorySection && state.dmRoomID != nil
            })
            .previewDisplayName("Other User With Assistant")
        
        // AGENT-PLATFORM (decision 87): the owner can undo an agent's block.
        ElementNavigationStack { RoomMemberDetailsScreen(context: blockedByAgentViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: blockedByAgentViewModel.context.$viewState.map { state in
                state.showAgentBlocksSection && state.dmRoomID != nil
            })
            .previewDisplayName("Blocked By Agent")
        
        // AGENT-PLATFORM (Brief 0083, question 359)
        ElementNavigationStack { RoomMemberDetailsScreen(context: ownAssistantViewModel.context) }
            .snapshotPreferences(expect: ownAssistantViewModel.context.$viewState.map { $0.agentProfile?.ownCard != nil && $0.dmRoomID != nil && $0.verificationState != nil })
            .previewDisplayName("Own Assistant")
            .previewLayout(.sizeThatFits)
            .frame(height: 1100)
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: ownRoleAgentViewModel.context) }
            .snapshotPreferences(expect: ownRoleAgentViewModel.context.$viewState.map { $0.agentProfile?.ownCard != nil && $0.dmRoomID != nil })
            .previewDisplayName("Own Role Agent")
        
        ElementNavigationStack { RoomMemberDetailsScreen(context: othersAgentViewModel.context) }
            .snapshotPreferences(expect: othersAgentViewModel.context.$viewState.map { $0.showEraseAssistantMemorySection && $0.dmRoomID != nil })
            .previewDisplayName("Others Agent")
        
        // The page's first render when the spaces aren't in memory yet.
        ElementNavigationStack { RoomMemberDetailsScreen(context: readingAgentViewModel.context) }
            .environment(\.spiralPreloaderDelay, .zero)
            .snapshotPreferences(expect: readingAgentViewModel.context.$viewState.map { $0.dmRoomID != nil && $0.verificationState != nil })
            .previewDisplayName("Agent Reading Ownership")
            .previewLayout(.sizeThatFits)
            .frame(height: 1100)
        
        // A failed read: the safe page, with Verify and Block.
        ElementNavigationStack { RoomMemberDetailsScreen(context: failedAgentViewModel.context) }
            .snapshotPreferences(expect: failedAgentViewModel.context.$viewState.map { $0.verificationState != nil && $0.agentOwnership == .unknown(isReading: false) })
            .previewDisplayName("Agent Failed Ownership")
            .previewLayout(.sizeThatFits)
            .frame(height: 1100)
    }
    
    static func makeViewModel(member: RoomMemberProxyMock, hasAssistant: Bool = false, ownsAgents: Bool = false, spacesRead: AgentProfileMock.SpacesRead = .answers,
                              agentBlocks: [AgentContactBlock] = []) -> RoomMemberDetailsScreenViewModel {
        let roomProxyMock = JoinedRoomProxyMock(.init(name: ""))
        roomProxyMock.getMemberUserIDClosure = { _ in .success(member) } // AGENT-PLATFORM (Brief 0083, question 359): the mock room knows only its own members.
        
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
        if ownsAgents {
            AgentProfileMock.configure(userSession, spacesRead: spacesRead)
        }
        
        return RoomMemberDetailsScreenViewModel(userID: member.userID,
                                                roomProxy: roomProxyMock,
                                                userSession: userSession,
                                                analytics: AnalyticsServiceMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock())
    }
}
