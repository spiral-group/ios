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
    
    private var profile: UserProfile {
        // AGENT-PLATFORM (Brief 0083, question 359): the person's own agent's name is known before the profile is.
        context.viewState.userProfile
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
            
            // AGENT-PLATFORM (Brief 0078, ADR-0019 P5)
            if context.viewState.showEraseAssistantMemorySection {
                eraseAssistantMemorySection
            }
            
            // AGENT-PLATFORM (decision 87)
            if context.viewState.showAgentBlocksSection {
                agentBlocksSection
            }
        }
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
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the page's hero.
    @ViewBuilder
    private var headerSection: some View {
        if context.viewState.userProfile != nil {
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
            }
        } else {
            SpiralProfileHero(picture: .user(profile),
                              title: profile.displayName ?? profile.id,
                              isVerified: context.viewState.showVerifiedBadge,
                              agent: context.viewState.agentProfile, // AGENT-PLATFORM (Brief 0083, question 359)
                              mediaProvider: context.mediaProvider) { _ in } actions: {
                if !context.viewState.isOwnUser { // AGENT-PLATFORM (Brief 0083, question 359)
                    SpiralProfileActionPlaceholder()
                }
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the handle, under a person's name before.
    @ViewBuilder
    private var infoSection: some View {
        // AGENT-PLATFORM (Brief 0083, question 359): the ID is known before the profile is, so its card doesn't arrive late.
        if profile.displayName != nil || context.viewState.userProfile == nil {
            Section {
                SpiralProfileInfoRow(caption: L10n.commonUsername) {
                    Text(profile.id)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the action row.
    @ViewBuilder
    private var otherUserFooter: some View {
        if context.viewState.userProfile != nil, !context.viewState.isOwnUser {
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
        
        if let permalink = context.viewState.permalink {
            ShareLink(item: permalink) {
                SpiralProfileActionLabel(title: L10n.actionShare, icon: \.shareIos)
            }
            .buttonStyle(.spiralProfileAction)
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

struct UserProfileScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let verifiedUserViewModel = makeViewModel(userID: RoomMemberProxyMock.mockDan.userID)
    static let otherUserViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID)
    static let accountOwnerViewModel = makeViewModel(userID: RoomMemberProxyMock.mockMe.userID)
    static let spiralContactViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: true) // AGENT-PLATFORM (Brief 0078)
    static let blockedByAgentViewModel = makeViewModel(userID: RoomMemberProxyMock.mockAlice.userID, hasAssistant: true,
                                                       agentBlocks: [previewAgentBlock])
    // AGENT-PLATFORM (Brief 0083, question 359): the person's own agent and someone else's.
    static let ownAgentViewModel = makeViewModel(userID: AgentProfileMock.assistant.matrixUserID, ownsAgents: true)
    static let othersAgentViewModel = makeViewModel(userID: AgentProfileMock.othersAgentID, ownsAgents: true)
    static let readingAgentViewModel = makeViewModel(userID: AgentProfileMock.assistant.matrixUserID, ownsAgents: true, spacesRead: .hangs)
    // AGENT-PLATFORM (decision 87): one of the person's agents blocks them.
    static let previewAgentBlock = AgentContactBlock(agentID: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02",
                                                     agentMXID: "@aria:spiral.md",
                                                     agentName: "Aria",
                                                     blockedAt: Date(timeIntervalSince1970: 1_791_709_200))
    
    static var previews: some View {
        ElementNavigationStack { UserProfileScreen(context: verifiedUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: verifiedUserViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Verified User")
        
        ElementNavigationStack { UserProfileScreen(context: otherUserViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: otherUserViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Other User")
        
        ElementNavigationStack { UserProfileScreen(context: accountOwnerViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: accountOwnerViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Account Owner")
        
        // AGENT-PLATFORM (Brief 0078): a Spiral account can erase what its assistant remembers.
        ElementNavigationStack { UserProfileScreen(context: spiralContactViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: spiralContactViewModel.context.observe(\.viewState.isVerified).map { $0 != nil })
            .previewDisplayName("Other User With Assistant")
        
        // AGENT-PLATFORM (decision 87): the owner can undo an agent's block.
        ElementNavigationStack { UserProfileScreen(context: blockedByAgentViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: blockedByAgentViewModel.context.observe(\.viewState.showAgentBlocksSection))
            .previewDisplayName("Blocked By Agent")
        
        // AGENT-PLATFORM (Brief 0083, question 359)
        ElementNavigationStack { UserProfileScreen(context: ownAgentViewModel.context) }
            .snapshotPreferences(expect: ownAgentViewModel.context.observe(\.viewState).map { await $0.agentProfile?.ownCard != nil && $0.userProfile != nil })
            .previewDisplayName("Own Agent")
        
        ElementNavigationStack { UserProfileScreen(context: othersAgentViewModel.context) }
            .snapshotPreferences(expect: othersAgentViewModel.context.observe(\.viewState).map { $0.agentOwnership == .someoneElses && $0.userProfile != nil })
            .previewDisplayName("Others Agent")
        
        // The page's first render when the spaces aren't in memory yet.
        ElementNavigationStack { UserProfileScreen(context: readingAgentViewModel.context) }
            .environment(\.spiralPreloaderDelay, .zero)
            .snapshotPreferences(expect: readingAgentViewModel.context.observe(\.viewState.userProfile).map { $0 != nil })
            .previewDisplayName("Agent Reading Ownership")
    }
    
    static func makeViewModel(userID: String, hasAssistant: Bool = false, ownsAgents: Bool = false, spacesRead: AgentProfileMock.SpacesRead = .answers,
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
        if ownsAgents {
            AgentProfileMock.configure(userSession, spacesRead: spacesRead)
        }
        
        return UserProfileScreenViewModel(userID: userID,
                                          isPresentedModally: false,
                                          userSession: userSession,
                                          analytics: AnalyticsServiceMock(.init()),
                                          userIndicatorController: UserIndicatorControllerMock())
    }
}
