//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import MatrixRustSDK
import SpiralComponents
import SwiftUI

struct RoomDetailsScreen: View {
    @Bindable var context: RoomDetailsScreenViewModel.Context
    
    @State private var isTopicExpanded = false
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, decision 344): Spiral's profile page, was a `Form` under Element's centred header.
        SpiralProfilePage(picture: .room(context.viewState.details.avatar),
                          title: roomTitle,
                          mediaProvider: context.mediaProvider) {
            roomHeaderSection
            
            // AGENT-PLATFORM (Brief 0083, question 359): the person's own agent: its rows, and the handle in «More».
            if let card = context.viewState.ownAgentCard {
                SpiralOwnAgentSection(card: card) { row in
                    context.send(viewAction: .processTapAgentRow(row))
                }
            } else if context.viewState.agentProfile?.isReadingOwnership == true {
                SpiralOwnAgentPlaceholderSection()
            } else {
                infoSection
            }
            
            aboutSection
            
            if context.viewState.dmUserID == nil {
                peopleSection
            }
            
            configurationSection
            
            securitySection
            
            leaveRoomSection
        }
        .onChange(of: context.isFavourite) { _, newValue in
            context.send(viewAction: .toggleFavourite(isFavourite: newValue))
        }
        .alert(item: $context.alertInfo)
        .alert(item: $context.leaveRoomAlertItem,
               actions: leaveRoomAlertActions,
               message: leaveRoomAlertMessage)
        .alert(item: $context.ignoreUserRoomAlertItem,
               actions: blockUserAlertActions,
               message: blockUserAlertMessage)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if context.viewState.canEditBaseInfo {
                    Button(L10n.actionEdit) {
                        context.send(viewAction: .processTapEdit)
                    }
                }
            }
        }
        .navigationTitle(L10n.screenRoomDetailsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .track(screen: .RoomDetails)
        .interactiveQuickLook(item: $context.mediaPreviewItem, allowEditing: false)
        .onAppear { context.send(viewAction: .appeared) } // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    // MARK: - Private
    
    private var roomTitle: String {
        context.viewState.details.name ?? context.viewState.details.id
    }
    
    /// The DM's other person: the one hero of a direct room.
    private var dmHero: UserProfile? {
        guard context.viewState.details.isDirect, case let .heroes(heroes) = context.viewState.details.avatar, heroes.count == 1 else { return nil }
        return heroes[0]
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the page's hero. The address moves to the info card, the pills to
    // the security section, the share shortcut into «More».
    private var roomHeaderSection: some View {
        SpiralProfileHero(picture: .room(context.viewState.details.avatar),
                          title: roomTitle,
                          agent: context.viewState.agentProfile, // AGENT-PLATFORM (Brief 0083, question 359)
                          presence: context.viewState.dmRecipientPresence, // AGENT-PLATFORM (Brief 0072)
                          subtitle: context.viewState.isDirect ? nil : L10n.commonMemberCount(context.viewState.joinedMembersCount),
                          userStatus: dmHero?.status,
                          mediaProvider: context.mediaProvider,
                          avatarAccessibilityIdentifier: A11yIdentifiers.roomDetailsScreen.avatar) { url in
            context.send(viewAction: .displayAvatar(url))
        } actions: {
            headerSectionShortcuts
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the action row: call, video, sound, invite and «More» for the rest.
    @ViewBuilder
    private var headerSectionShortcuts: some View {
        let shortcuts = context.viewState.shortcuts
        
        if let isVoiceCall = shortcuts.compactMap(\.joinCallIsVoice).first {
            Button {
                context.send(viewAction: .processTapCall(isVoiceCall: isVoiceCall))
            } label: {
                SpiralProfileActionLabel(title: L10n.actionJoin, icon: isVoiceCall ? \.voiceCall : \.videoCall)
            }
            .accessibilityLabel(L10n.a11yJoinCall)
            .buttonStyle(.spiralProfileAction)
            .disabled(!context.viewState.canJoinCall)
        }
        
        if shortcuts.contains(.voiceCall) {
            Button {
                context.send(viewAction: .processTapCall(isVoiceCall: true))
            } label: {
                SpiralProfileActionLabel(title: UntranslatedL10n.screenProfileActionCall, icon: \.voiceCall)
            }
            .accessibilityLabel(L10n.a11yStartVoiceCall)
            .buttonStyle(.spiralProfileAction)
        }
        
        if shortcuts.contains(.videoCall) {
            Button {
                context.send(viewAction: .processTapCall(isVoiceCall: false))
            } label: {
                SpiralProfileActionLabel(title: L10n.commonVideo, icon: \.videoCall)
            }
            .accessibilityLabel(L10n.a11yStartVideoCall)
            .buttonStyle(.spiralProfileAction)
        }
        
        // AGENT-PLATFORM (Brief 0083, questions 359 and 391): the person's own agent has Settings here, its screen on
        // the Agents tab, and Mute in «More».
        if context.viewState.agentProfile?.isReadingOwnership == true {
            toggleMuteButton
                .spiralLoadingSlot(true, label: L10n.commonLoading)
        } else if context.viewState.showsAgentSettings {
            Button {
                context.send(viewAction: .processTapAgentRow(.settings))
            } label: {
                SpiralProfileActionLabel(title: L10n.commonSettings, icon: \.settings)
            }
            .buttonStyle(.spiralProfileAction)
        } else {
            toggleMuteButton
        }
        
        if shortcuts.contains(.invite) {
            Button {
                context.send(viewAction: .processTapInvite)
            } label: {
                SpiralProfileActionLabel(title: L10n.actionInvite, icon: \.userAdd)
            }
            .buttonStyle(.spiralProfileAction)
        }
        
        moreMenu
    }
    
    private var moreMenu: some View {
        SpiralProfileActionMenu(title: UntranslatedL10n.screenProfileActionMore, icon: \.overflowHorizontal) {
            // AGENT-PLATFORM (Brief 0083, question 359)
            if let card = context.viewState.ownAgentCard {
                Button {
                    context.send(viewAction: .copyAgentHandle)
                } label: {
                    Label(card.matrixUserID, icon: \.copy)
                }
                
                Button {
                    context.send(viewAction: .processToggleMuteNotifications)
                } label: {
                    Label(context.viewState.notificationShortcutButtonTitle, icon: context.viewState.notificationShortcutButtonIcon)
                }
                .disabled(context.viewState.isProcessingMuteToggleAction)
            }
            
            if let permalink = context.viewState.shortcuts.compactMap(\.shareLink).first {
                ShareLink(item: permalink) {
                    Label(L10n.actionShare, icon: \.shareIos)
                }
            }
            
            // The invitation flow is different for DMs
            if context.viewState.dmUserID != nil { // AGENT-PLATFORM (Brief 0083, question 359)
                Button {
                    context.send(viewAction: .processTapInvite)
                } label: {
                    Label(L10n.actionInvite, icon: \.userAdd)
                }
            }
            
            Toggle(isOn: $context.isFavourite) {
                Label(L10n.commonFavourite, icon: \.favourite)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.favourite)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the handle and the topic as one card, as a caption over its value.
    private var infoSection: some View {
        Section {
            if let address = context.viewState.details.canonicalAlias {
                SpiralProfileInfoRow(caption: L10n.screenCreateRoomRoomAddressSectionTitle) {
                    Text(address)
                        .textSelection(.enabled)
                }
            } else if let dmHero {
                SpiralProfileInfoRow(caption: L10n.commonUsername) {
                    Text(dmHero.id)
                        .textSelection(.enabled)
                }
            }
            
            if context.viewState.hasTopicSection {
                if let topic = context.viewState.topic, !topic.characters.isEmpty, let topicSummary = context.viewState.topicSummary {
                    SpiralProfileInfoRow(caption: L10n.commonTopic) {
                        Text(isTopicExpanded ? topic : topicSummary)
                            .lineLimit(isTopicExpanded ? nil : 3)
                            .accentColor(.compound.textLinkExternal)
                            .textSelection(.enabled)
                    }
                    .onTapGesture {
                        isTopicExpanded.toggle()
                    }
                } else {
                    ListRow(label: .plain(title: L10n.screenRoomDetailsAddTopicTitle),
                            kind: .button { context.send(viewAction: .processTapAddTopic) })
                        .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.addTopic)
                }
            }
        }
    }
    
    private var aboutSection: some View {
        Section {
            ListRow(label: .default(title: L10n.screenMediaBrowserTitle, icon: \.image),
                    kind: .navigationLink {
                        context.send(viewAction: .processTapMediaEvents)
                    })
            
            ListRow(label: .default(title: L10n.screenRoomDetailsPinnedEventsRowTitle, icon: \.pin),
                    details: context.viewState.pinnedEventsActionState.isLoading ? .isWaiting(true) : .title(context.viewState.pinnedEventsActionState.count),
                    kind: context.viewState.pinnedEventsActionState.isLoading ? .label : .navigationLink {
                        context.send(viewAction: .processTapPinnedEvents)
                    }) // AGENT-PLATFORM (Brief 0083): no `.disabled` while loading. A `.label` row does nothing on a tap, and its title read 3.41:1.
            
            ListRow(label: .default(title: L10n.screenPollsHistoryTitle, icon: \.polls),
                    kind: .navigationLink {
                        context.send(viewAction: .processTapPolls)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.pollsHistory)
            
            // AGENT-PLATFORM (Brief 0083, decision 344): Interactive Posts make threads; the list lives here, out of the chat.
            if context.viewState.areThreadsEnabled {
                ListRow(label: .default(title: L10n.commonThreads, icon: \.threads),
                        kind: .navigationLink {
                            context.send(viewAction: .processTapThreads)
                        })
            }
        }
    }
    
    @ViewBuilder
    private var profileRow: some View {
        if context.viewState.dmUserID != nil { // AGENT-PLATFORM (Brief 0083, question 359)
            let details: ListRowDetails? = switch context.viewState.dmRecipientInfo?.verificationState {
            case .verified:
                .icon(CompoundIcon(\.verified).foregroundStyle(.compound.iconSuccessPrimary))
            case .verificationViolation:
                .icon(CompoundIcon(\.infoSolid).foregroundStyle(.compound.iconCriticalPrimary))
            case .notVerified, .none:
                nil
            }
            
            ListRow(label: .default(title: L10n.screenRoomDetailsProfileRowTitle, icon: \.userProfile),
                    details: details,
                    kind: .navigationLink {
                        context.send(viewAction: .processTapRecipientProfile)
                    })
        }
    }
    
    private var configurationSection: some View {
        Section {
            profileRow
            
            ListRow(label: .default(title: L10n.screenRoomDetailsNotificationTitle, icon: \.notifications),
                    details: context.viewState.notificationSettingsState.isLoading ? .isWaiting(true)
                        : context.viewState.notificationSettingsState.isError ? .systemIcon(.exclamationmarkCircle)
                        : .title(context.viewState.notificationSettingsState.label),
                    kind: .navigationLink {
                        context.send(viewAction: .processTapNotifications)
                    })
                    .disabled(context.viewState.notificationSettingsState.isLoading)
                    .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.notifications)
        }
    }
    
    private var peopleSection: some View {
        Section {
            if context.viewState.hasMemberIdentityVerificationStateViolations {
                ListRow(label: .default(title: L10n.commonPeople, icon: \.user),
                        details: .icon(CompoundIcon(\.infoSolid).foregroundStyle(.compound.iconCriticalPrimary)),
                        kind: .navigationLink {
                            context.send(viewAction: .processTapPeople)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.people)
                
            } else {
                ListRow(label: .default(title: L10n.commonPeople, icon: \.user),
                        details: .title(String(context.viewState.joinedMembersCount)),
                        kind: .navigationLink {
                            context.send(viewAction: .processTapPeople)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.people)
            }
            
            // AGENT-PLATFORM (decision 192): the same screen as the composer's «+».
            if context.viewState.showsAgentsRow {
                ListRow(label: .default(title: UntranslatedL10n.screenRoomDetailsAgents, icon: \.extensions),
                        details: context.viewState.agentsCount.map { .title(String($0)) },
                        kind: .navigationLink {
                            context.send(viewAction: .processTapAgents)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.agents)
            }
            
            if context.viewState.canSeeKnockingRequests {
                ListRow(label: .default(title: L10n.screenRoomDetailsRequestsToJoinTitle, icon: \.askToJoin),
                        details: context.viewState.knockRequestsCount > 0 ? .counter(context.viewState.knockRequestsCount) : nil,
                        kind: .navigationLink {
                            context.send(viewAction: .processTapRequestsToJoin)
                        })
            }
            
            if context.viewState.canEditRolesOrPermissions, context.viewState.dmUserID == nil {
                ListRow(label: .default(title: L10n.screenRoomDetailsRolesAndPermissions, icon: \.admin),
                        kind: .navigationLink {
                            context.send(viewAction: .processTapRolesAndPermissions)
                        })
            }
        }
    }
    
    private var toggleMuteButton: some View {
        Button {
            context.send(viewAction: .processToggleMuteNotifications)
        } label: {
            SpiralProfileActionLabel(title: context.viewState.notificationShortcutButtonTitle,
                                     icon: context.viewState.notificationShortcutButtonIcon,
                                     isBusy: context.viewState.isProcessingMuteToggleAction)
        }
        .buttonStyle(.spiralProfileAction)
        .disabled(context.viewState.isProcessingMuteToggleAction)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the header's pills, as quiet rows.
    private var securitySection: some View {
        Section {
            ForEach(SpiralProfileSecurityFact.facts(of: context.viewState.details)) { fact in
                ListRow(label: .default(title: fact.title, description: fact.description, icon: fact.icon),
                        kind: .label)
            }
            
            if context.viewState.canSeeSecurityAndPrivacy {
                ListRow(label: .default(title: L10n.screenRoomDetailsSecurityAndPrivacyTitle, icon: \.settings),
                        kind: .navigationLink {
                            context.send(viewAction: .processTapSecurityAndPrivacy)
                        })
            }
        } header: {
            Text(L10n.commonSecurity)
                .compoundListSectionHeader()
        }
    }
    
    private func ignoreUserRow(user: RoomMemberDetails) -> some View {
        ListRow(label: .default(title: user.isIgnored ? L10n.screenDmDetailsUnblockUser : L10n.screenDmDetailsBlockUser,
                                icon: \.block,
                                role: user.isIgnored ? nil : .destructive),
                details: .isWaiting(context.viewState.isProcessingIgnoreRequest),
                kind: .button {
                    context.send(viewAction: user.isIgnored ? .processTapUnignore : .processTapIgnore)
                })
                .disabled(context.viewState.isProcessingIgnoreRequest)
                .accessibilityIdentifier(user.isIgnored ? A11yIdentifiers.roomDetailsScreen.unblockUser : A11yIdentifiers.roomDetailsScreen.blockUser) // AGENT-PLATFORM (decision 146)
    }
    
    private var reportRoomRow: some View {
        ListRow(label: .action(title: L10n.actionReportRoom,
                               icon: \.chatProblem,
                               role: .destructive),
                kind: .button { context.send(viewAction: .processTapReport) })
            .accessibilityIdentifier(A11yIdentifiers.roomDetailsScreen.reportRoom) // AGENT-PLATFORM (decision 146)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 344): the page's red rows, one card.
    private var leaveRoomSection: some View {
        Section {
            // AGENT-PLATFORM (Brief 0083, question 359): a DM's row keeps its place until the member says what it does.
            if context.viewState.dmUserID != nil {
                if context.viewState.showsBlockRow {
                    if let recipient = context.viewState.dmRecipientInfo?.member {
                        ignoreUserRow(user: recipient)
                    } else {
                        ListRow(label: .default(title: L10n.screenDmDetailsBlockUser, icon: \.block, role: .destructive), kind: .label)
                            .spiralLoadingSlot(true, label: L10n.commonLoading)
                    }
                }
            } else if context.viewState.reportRoomEnabled {
                reportRoomRow
            }
            
            if context.viewState.showsLeaveRow { // AGENT-PLATFORM (Brief 0083, question 359)
                ListRow(label: .action(title: L10n.screenRoomDetailsLeaveRoomTitle,
                                       icon: \.leave,
                                       role: .destructive),
                        kind: .button { context.send(viewAction: .processTapLeave) })
            }
        }
    }
    
    @ViewBuilder
    private func leaveRoomAlertActions(_ item: LeaveRoomAlertItem) -> some View {
        Button(item.cancelTitle, role: .cancel) { }
        Button(item.confirmationTitle, role: .destructive) {
            context.send(viewAction: .confirmLeave)
        }
    }
    
    private func leaveRoomAlertMessage(_ item: LeaveRoomAlertItem) -> some View {
        Text(item.subtitle)
    }
    
    @ViewBuilder
    private func blockUserAlertActions(_ item: RoomDetailsScreenViewStateBindings.IgnoreUserAlertItem) -> some View {
        Button(item.cancelTitle, role: .cancel) { }
        Button(item.confirmationTitle,
               role: item.action == .ignore ? .destructive : nil) {
            context.send(viewAction: item.viewAction)
        }
    }
    
    private func blockUserAlertMessage(_ item: RoomDetailsScreenViewStateBindings.IgnoreUserAlertItem) -> some View {
        Text(item.description)
    }
}

// MARK: - Previews

struct RoomDetailsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let genericWorldReadableRoomViewModel = makeGenericRoomViewModel(historyVisibility: .worldReadable)
    static let genericJoinedRoomViewModel = makeGenericRoomViewModel(historyVisibility: .joined)
    static let simpleRoomViewModel = makeSimpleRoomViewModel()
    // AGENT-PLATFORM: the tombstoned avatar's circle on the grouped background.
    static let tombstonedRoomViewModel = makeSimpleRoomViewModel(id: "!tombstoned_room:spiral.md",
                                                                 successor: .init(roomId: "!successor_room:spiral.md", reason: nil))
    static let dmRoomViewModel = makeDMViewModel(verificationState: .notVerified)
    static let dmRoomVerifiedViewModel = makeDMViewModel(verificationState: .verified)
    static let dmRoomVerificationViolationViewModel = makeDMViewModel(verificationState: .verificationViolation)
    // AGENT-PLATFORM (Brief 0083, decision 344): a monogram's field, the assistant's DM (the header's sample) and a call to join.
    static let dmRoomMonogramViewModel = makeDMViewModel(verificationState: .notVerified, recipient: .init(with: .init(userID: "@andrii:spiral.md", displayName: "Andrii", membership: .join)), topic: nil)
    static let assistantDMViewModel = makeDMViewModel(verificationState: .notVerified,
                                                      recipient: .init(with: .init(userID: "@assistant-appreview:spiral.md", displayName: "App Review · assistant", membership: .join)),
                                                      topic: nil)
    static let ongoingCallRoomViewModel = makeGenericRoomViewModel(historyVisibility: .joined, hasOngoingCall: true)
    // AGENT-PLATFORM (Brief 0083, question 359): an agent's page: the person's assistant, their role agent, someone else's.
    static let ownAssistantDMViewModel = makeDMViewModel(verificationState: .notVerified, recipient: AgentProfileMock.member(AgentProfileMock.assistant), topic: nil, ownsAgents: true)
    static let ownRoleAgentDMViewModel = makeDMViewModel(verificationState: .notVerified, recipient: AgentProfileMock.member(AgentProfileMock.salesAgent), topic: nil, ownsAgents: true)
    static let othersAgentDMViewModel = makeDMViewModel(verificationState: .notVerified, recipient: AgentProfileMock.othersAgent, topic: nil, ownsAgents: true)
    static let readingAgentDMViewModel = makeDMViewModel(verificationState: .notVerified, recipient: AgentProfileMock.member(AgentProfileMock.assistant), topic: nil, ownsAgents: true, spacesRead: .hangs)
    static let failedAgentDMViewModel = makeDMViewModel(verificationState: .notVerified, recipient: AgentProfileMock.member(AgentProfileMock.assistant), topic: nil, ownsAgents: true, spacesRead: .fails)
    // AGENT-PLATFORM (question 400): the field from an agent's own photo, beside the agents' own colours above.
    static let agentPhotoDMViewModel = makeDMViewModel(verificationState: .notVerified,
                                                       recipient: .init(with: .init(userID: "@assistant-sample:spiral.md", displayName: "Sample · assistant",
                                                                                    avatarURL: .mockMXCUserAvatar, membership: .join)),
                                                       topic: nil)
    
    static var previews: some View {
        ElementNavigationStack { RoomDetailsScreen(context: genericJoinedRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: genericJoinedRoomViewModel.context.observe(\.viewState.permalink).map { $0 != nil })
            .previewDisplayName("Generic Room - Joined History Visibility")
            .previewLayout(.sizeThatFits)
            .frame(height: 1400)
        
        ElementNavigationStack { RoomDetailsScreen(context: genericWorldReadableRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: genericWorldReadableRoomViewModel.context.observe(\.viewState.permalink).map { $0 != nil })
            .previewDisplayName("Generic Room - World Readable History Visibility")
            .previewLayout(.sizeThatFits)
            .frame(height: 1400)
        
        ElementNavigationStack { RoomDetailsScreen(context: simpleRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: simpleRoomViewModel.context.observe(\.viewState.permalink).map { $0 != nil })
            .previewDisplayName("Simple Room")
            .previewLayout(.sizeThatFits)
            .frame(height: 1200)
        
        ElementNavigationStack { RoomDetailsScreen(context: tombstonedRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: tombstonedRoomViewModel.context.observe(\.viewState.permalink).map { $0 != nil })
            .previewDisplayName("Tombstoned Room")
            .previewLayout(.sizeThatFits)
            .frame(height: 1200)
        
        ElementNavigationStack { RoomDetailsScreen(context: dmRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            // AGENT-PLATFORM: also wait for the hero-based dmRecipientInfo —
            // it resolves asynchronously, so waiting on accountOwner alone
            // races the recipient section and flakes the snapshot.
            .snapshotPreferences(expect: dmRoomViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("DM Room")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: dmRoomVerifiedViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: dmRoomVerifiedViewModel.context.observe(\.viewState.dmRecipientInfo?.verificationState).map { $0 == .verified })
            .previewDisplayName("DM Room Verified")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: dmRoomVerificationViolationViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            // AGENT-PLATFORM: wait for the violation badge state, not just the
            // account owner, for a deterministic snapshot.
            .snapshotPreferences(expect: dmRoomVerificationViolationViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo?.verificationState == .verificationViolation })
            .previewDisplayName("DM Room Verification Violation")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        // AGENT-PLATFORM (Brief 0083, decision 344)
        ElementNavigationStack { RoomDetailsScreen(context: dmRoomMonogramViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: dmRoomMonogramViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("DM Room Monogram")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: assistantDMViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: assistantDMViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("Assistant DM")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: ongoingCallRoomViewModel.context) } // AGENT-PLATFORM (Brief 0083): the page's field is laid out under a bar.
            .snapshotPreferences(expect: ongoingCallRoomViewModel.context.observe(\.viewState.permalink).map { $0 != nil })
            .previewDisplayName("Room With Ongoing Call")
            .previewLayout(.sizeThatFits)
            .frame(height: 1400)
        
        // AGENT-PLATFORM (Brief 0083, question 359)
        ElementNavigationStack { RoomDetailsScreen(context: ownAssistantDMViewModel.context) }
            .snapshotPreferences(expect: ownAssistantDMViewModel.context.observe(\.viewState).map { await $0.ownAgentCard != nil && $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("Own Assistant DM")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: ownRoleAgentDMViewModel.context) }
            .snapshotPreferences(expect: ownRoleAgentDMViewModel.context.observe(\.viewState).map { await $0.ownAgentCard != nil && $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("Own Role Agent DM")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: othersAgentDMViewModel.context) }
            .snapshotPreferences(expect: othersAgentDMViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil && $0.agentOwnership == .someoneElses })
            .previewDisplayName("Others Agent DM")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        // The page's first render when the spaces aren't in memory yet.
        ElementNavigationStack { RoomDetailsScreen(context: readingAgentDMViewModel.context) }
            .environment(\.spiralPreloaderDelay, .zero)
            .snapshotPreferences(expect: readingAgentDMViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("Agent DM Reading Ownership")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        // A failed read: the safe page, with Block.
        ElementNavigationStack { RoomDetailsScreen(context: failedAgentDMViewModel.context) }
            .snapshotPreferences(expect: failedAgentDMViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil && $0.agentOwnership == .unknown(isReading: false) })
            .previewDisplayName("Agent DM Failed Ownership")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
        
        ElementNavigationStack { RoomDetailsScreen(context: agentPhotoDMViewModel.context) }
            .snapshotPreferences(expect: agentPhotoDMViewModel.context.observe(\.viewState).map { $0.accountOwner != nil && $0.dmRecipientInfo != nil })
            .previewDisplayName("Agent DM With A Photo")
            .previewLayout(.sizeThatFits)
            .frame(height: 1350)
    }
    
    private static func makeGenericRoomViewModel(historyVisibility: RoomHistoryVisibility, hasOngoingCall: Bool = false) -> RoomDetailsScreenViewModel { // AGENT-PLATFORM (Brief 0083)
        let knockRequests: [KnockRequestProxyMock] = [.init()]
        
        let members: [RoomMemberProxyMock] = [
            .mockMeAdmin,
            .mockAlice,
            .mockBob,
            .mockCharlie
        ]
        
        let roomProxy = JoinedRoomProxyMock(.init(id: "!room_a:spiral.md", // AGENT-PLATFORM: sigil-less mock IDs yield no SpiralLink, deadlocking the permalink snapshot wait
                                                  name: "Room A",
                                                  topic: """
                                                  Discussions about Element X iOS | https://github.com/vector-im/element-x-ios
                                                  
                                                  Feature Status: https://github.com/vector-im/element-x-ios/issues/1225
                                                  
                                                  App Store: https://apple.co/3r6LJHZ
                                                  TestFlight: https://testflight.apple.com/join/uZbeZCOi
                                                  """,
                                                  isDirect: false,
                                                  isEncrypted: true,
                                                  hasOngoingCall: hasOngoingCall, // AGENT-PLATFORM (Brief 0083)
                                                  canonicalAlias: "#alias:domain.com",
                                                  historyVisibility: historyVisibility,
                                                  members: members,
                                                  knockRequestsState: .loaded(knockRequests),
                                                  joinRule: .knock))
        
        let notificationSettingsProxyMockConfiguration = NotificationSettingsProxyMockConfiguration()
        notificationSettingsProxyMockConfiguration.roomMode.isDefault = false
        
        let notificationSettingsProxy = NotificationSettingsProxyMock(with: notificationSettingsProxyMockConfiguration)
        
        return .init(roomProxy: roomProxy,
                     userSession: UserSessionMock(.init()),
                     analyticsService: AnalyticsServiceMock(.init()),
                     userIndicatorController: UserIndicatorControllerMock(),
                     notificationSettingsProxy: notificationSettingsProxy,
                     attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()))
    }
    
    private static func makeSimpleRoomViewModel(id: String = "!simple_room:spiral.md", successor: SuccessorRoom? = nil) -> RoomDetailsScreenViewModel { // AGENT-PLATFORM
        let knockRequests: [KnockRequestProxyMock] = [.init()]
        
        let members: [RoomMemberProxyMock] = [
            .mockMeAdmin,
            .mockAlice,
            .mockBob,
            .mockCharlie
        ]
        let roomProxy = JoinedRoomProxyMock(.init(id: id,
                                                  name: "Room A",
                                                  isDirect: false,
                                                  isEncrypted: false,
                                                  hasOngoingCall: false, // AGENT-PLATFORM (Brief 0083): the row's Call and Video.
                                                  members: members,
                                                  knockRequestsState: .loaded(knockRequests),
                                                  joinRule: .knock,
                                                  successor: successor))
        
        let notificationSettingsProxy = NotificationSettingsProxyMock(with: .init())
        
        return .init(roomProxy: roomProxy,
                     userSession: UserSessionMock(.init()),
                     analyticsService: AnalyticsServiceMock(.init()),
                     userIndicatorController: UserIndicatorControllerMock(),
                     notificationSettingsProxy: notificationSettingsProxy,
                     attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()))
    }
    
    private static func makeDMViewModel(verificationState: UserIdentityVerificationState, // AGENT-PLATFORM (Brief 0083)
                                        recipient: RoomMemberProxyMock = .mockDan,
                                        topic: String? = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
                                        ownsAgents: Bool = false,
                                        spacesRead: AgentProfileMock.SpacesRead = .answers) -> RoomDetailsScreenViewModel {
        let members: [RoomMemberProxyMock] = [
            .mockMe,
            recipient
        ]
        
        let roomProxy = JoinedRoomProxyMock(.init(id: "!dm_room:spiral.md",
                                                  name: recipient.displayName, // AGENT-PLATFORM (Brief 0083)
                                                  topic: topic, // AGENT-PLATFORM (Brief 0083)
                                                  isDirect: true,
                                                  isEncrypted: true,
                                                  hasOngoingCall: false, // AGENT-PLATFORM (Brief 0083): the row's Call and Video.
                                                  members: members,
                                                  heroes: [recipient])) // AGENT-PLATFORM (Brief 0083)
        
        let clientProxyMock = ClientProxyMock(.init())
        
        clientProxyMock.userIdentityForFallBackToServerClosure = { userID, _ in
            let identity = switch userID {
            case RoomMemberProxyMock.mockDan.userID:
                UserIdentityProxyMock(.init(verificationState: verificationState))
            default:
                UserIdentityProxyMock(.init())
            }
            
            return .success(identity)
        }
        
        let notificationSettingsProxy = NotificationSettingsProxyMock(with: .init())
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxyMock))
        if ownsAgents {
            AgentProfileMock.configure(userSession, spacesRead: spacesRead)
        }
        
        return .init(roomProxy: roomProxy,
                     userSession: userSession,
                     analyticsService: AnalyticsServiceMock(.init()),
                     userIndicatorController: UserIndicatorControllerMock(),
                     notificationSettingsProxy: notificationSettingsProxy,
                     attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()))
    }
}
