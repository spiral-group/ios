//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct TimelineItemMenu: View {
    @EnvironmentObject private var context: TimelineViewModel.Context
    @Environment(\.dismiss) private var dismiss
    
    let item: EventBasedTimelineItemProtocol
    let actions: TimelineItemMenuActions
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
    
    // AGENT-PLATFORM (Brief 0083): Spiral's menu is iOS's grouped sheet, where Element's was a flat list under a
    // divider: the message, the quick reactions, the actions in cards by kind and the destructive ones each on a card.
    var body: some View {
        ScrollView {
            VStack(spacing: CompoundDesignTokens.space4X) {
                SpiralCard(on: .groupedSheet) {
                    messagePreview
                }
                
                if !actions.reactions.isEmpty {
                    SpiralCard(on: .groupedSheet) {
                        reactionsSection
                    }
                }
                
                ForEach(MenuCardGroup.cards(for: actions.actions), id: \.self) { card in
                    SpiralCard(on: .groupedSheet) {
                        viewsForActions(card)
                    }
                }
                
                if !actions.secondaryActions.isEmpty {
                    SpiralCard(on: .groupedSheet) {
                        viewsForActions(actions.secondaryActions)
                    }
                }
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.top, CompoundDesignTokens.space8X)
            .padding(.bottom, CompoundDesignTokens.space4X)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.compound.bgSubtleSecondaryLevel0.ignoresSafeArea())
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.timelineItemActionMenu)
        .presentationSizing(.page)
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.compound.bgSubtleSecondaryLevel0)
        .presentationDragIndicator(.visible)
    }
    
    // AGENT-PLATFORM (Brief 0083): the sender, the time beside the name and two lines of the message, then the
    // send failure or the authenticity line under a separator, on the message's card.
    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CompoundDesignTokens.space3X) {
                LoadableAvatarImage(url: item.sender.avatarURL,
                                    name: item.sender.displayName,
                                    contentID: item.sender.id,
                                    avatarSize: .user(on: .timeline),
                                    mediaProvider: context.mediaProvider)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                    HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                        Text(item.sender.displayName ?? item.sender.id)
                            .font(.compound.bodyMDSemibold)
                            .foregroundColor(.compound.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(item.timestamp.formattedTime())
                            .font(.compound.bodySM)
                            .foregroundColor(.compound.textSecondary)
                    }
                    
                    Text(item.timelineMenuDescription)
                        .font(.compound.bodyMD)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
            
            if case let .sendingFailed(.verifiedUser(failure)) = item.properties.deliveryStatus {
                SpiralCardSeparator()
                
                VerifiedUserSendFailureView(failure: failure,
                                            members: context.viewState.members,
                                            ownUserID: context.viewState.ownUserID) {
                    send(.itemSendInfoTapped(itemID: item.id))
                }
            } else if let authenticity = item.properties.encryptionAuthenticity {
                SpiralCardSeparator()
                
                Label(authenticity.message, icon: authenticity.icon, iconSize: .small, relativeTo: .compound.bodySMSemibold)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(authenticity.foregroundStyle)
                    .padding(.horizontal, CompoundDesignTokens.space4X)
                    .padding(.vertical, CompoundDesignTokens.space3X)
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): the quick reactions on their own card, the picker's button on a grey disc apart
    // from them. They spread across the card when they fit and scroll under a fade when they don't, so the first
    // frame (and a snapshot) lays them out as the app does: no width is read after layout.
    private var reactionsSection: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            ViewThatFits(in: .horizontal) {
                reactionButtons
                
                ScrollView(.horizontal) {
                    reactionButtons
                }
                .scrollIndicators(.hidden)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0.0),
                                           .init(color: .black, location: 0.85),
                                           .init(color: .clear, location: 1.0)],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                }
            }
            
            Button {
                dismiss()
                // Otherwise we get errors that a sheet is already presented
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    context.send(viewAction: .displayEmojiPicker(itemID: item.id))
                }
            } label: {
                CompoundIcon(\.reactionAdd, size: .medium, relativeTo: .compound.headingLG)
                    .foregroundColor(.compound.iconSecondary)
                    .padding(10)
                    .background(Circle().fill(Color.compound.bgSubtleSecondary))
            }
            .accessibilityLabel(L10n.actionReact)
            .padding(.trailing, CompoundDesignTokens.space2X)
        }
        .padding(.vertical, CompoundDesignTokens.space2X)
    }
    
    private var reactionButtons: some View {
        HStack(alignment: .center, spacing: CompoundDesignTokens.space1X) {
            ForEach(actions.reactions, id: \.key) {
                reactionButton(for: $0.key)
            }
        }
        .padding(.leading, CompoundDesignTokens.space2X)
    }
    
    private func reactionButton(for emoji: String) -> some View {
        Button {
            feedbackGenerator.impactOccurred()
            dismiss()
            context.send(viewAction: .toggleReaction(key: emoji, itemID: item.id))
        } label: {
            Text(emoji)
                .font(.compound.headingLG)
                .padding(8)
                .background { reactionBackground(for: emoji) } // AGENT-PLATFORM (Brief 0083)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(hasReacted(to: emoji) ? L10n.a11yRemoveReaction(emoji) : L10n.a11yAddReaction(emoji))
    }
    
    private func hasReacted(to emoji: String) -> Bool {
        if let reaction = item.properties.reactions.first(where: { $0.key == emoji }),
           reaction.isHighlighted {
            return true
        }
        return false
    }
    
    // AGENT-PLATFORM (Brief 0083): a reaction you sent takes the timeline's tint, and a ring in its ink so the
    // state reads at 3:1 against the card.
    @ViewBuilder
    private func reactionBackground(for emoji: String) -> some View {
        if hasReacted(to: emoji) {
            Circle()
                .fill(Color.compound.bgBadgeAccent)
                .strokeBorder(Color.compound.textBadgeAccent, lineWidth: CompoundDesignTokens.borderWidth1)
        }
    }
    
    private func viewsForActions(_ actions: [TimelineItemMenuAction]) -> some View {
        ForEach(actions, id: \.self) { action in
            Button(role: action.isDestructive ? .destructive : nil) {
                send(action)
            } label: {
                action.label
            }
            .buttonStyle(MenuCardRowButtonStyle(showsSeparator: action != actions.last)) // AGENT-PLATFORM (Brief 0083)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): the actions' cards, as iOS groups a menu: the provider's actions and conditions,
    // shown by kind.
    fileprivate enum MenuCardGroup: CaseIterable {
        case navigate, respond, copy, change, inspect
        
        /// The cards for these actions, each in iOS's order of its kind; a kind with no action has no card.
        static func cards(for actions: [TimelineItemMenuAction]) -> [[TimelineItemMenuAction]] {
            allCases.compactMap { group in
                // Ties keep the provider's order.
                let card = actions.enumerated()
                    .filter { $0.element.menuCard == group }
                    .sorted { ($0.element.rankInMenuCard, $0.offset) < ($1.element.rankInMenuCard, $1.offset) }
                    .map(\.element)
                return card.isEmpty ? nil : card
            }
        }
    }
    
    private func send(_ action: TimelineItemMenuAction) {
        send(.handleTimelineItemMenuAction(itemID: item.id, action: action))
    }
    
    private func send(_ action: TimelineViewAction) {
        dismiss()
        // Otherwise we might get errors that a sheet is already presented
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.send(viewAction: action)
        }
    }
}

private struct VerifiedUserSendFailureView: View {
    let failure: TimelineItemSendFailure.VerifiedUser
    let action: () -> Void
    
    private let memberDisplayName: String
    private let isYou: Bool
    
    init(failure: TimelineItemSendFailure.VerifiedUser,
         members: [String: RoomMemberState],
         ownUserID: String,
         action: @escaping () -> Void) {
        self.failure = failure
        self.action = action
        
        let userIDs = failure.affectedUserIDs
        memberDisplayName = userIDs.first.map { members[$0]?.displayName ?? $0 } ?? ""
        isYou = ownUserID == userIDs.first
    }
    
    var title: String {
        switch failure {
        case .hasUnsignedDevice:
            isYou ? L10n.screenTimelineItemMenuSendFailureYouUnsignedDevice : L10n.screenTimelineItemMenuSendFailureUnsignedDevice(memberDisplayName)
        case .changedIdentity:
            L10n.screenTimelineItemMenuSendFailureChangedIdentity(memberDisplayName)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, icon: \.errorSolid, iconSize: .small, relativeTo: .compound.bodySMSemibold)
                    .font(.compound.bodySMSemibold)
                    .foregroundStyle(.compound.textCriticalPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ListRowAccessory.navigationLink
            }
            // AGENT-PLATFORM (Brief 0083): a row of the message's card.
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
            .contentShape(.rect)
        }
        .buttonStyle(.spiralCardRow) // AGENT-PLATFORM (Brief 0083)
    }
}

// AGENT-PLATFORM (Brief 0083): a row of the menu's cards, as iOS's own menus draw one: the title leading, its glyph
// trailing, both in the action's colour, a separator under it but the last, and a grey fill while pressed. The card
// is the button's shape, so Button Shapes adds none.
private struct MenuCardRowButtonStyle: ButtonStyle {
    let showsSeparator: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(MenuCardRowLabelStyle())
            .foregroundStyle(configuration.role == .destructive ? .compound.textCriticalPrimary : .compound.textActionPrimary)
            .background(configuration.isPressed ? Color.compound.bgActionSecondaryPressed : .clear)
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    SpiralCardSeparator()
                }
            }
            .contentShape(.rect)
    }
}

private struct MenuCardRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            configuration.title
                .font(.compound.bodyLG)
                .frame(maxWidth: .infinity, alignment: .leading)
            configuration.icon
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(minHeight: CompoundDesignTokens.space13X)
    }
}

// AGENT-PLATFORM (Brief 0083): which card an action is drawn on, and where in it.
private extension TimelineItemMenuAction {
    var menuCard: TimelineItemMenu.MenuCardGroup {
        switch self {
        case .viewInRoomTimeline: .navigate
        case .reply, .replyInThread, .forward: .respond
        case .copy, .copyCaption, .copyPermalink, .translate, .downloadMedia: .copy
        case .edit, .addCaption, .editCaption, .editPoll, .editInteractivePost, .endPoll, .pin, .unpin, .removeCaption,
             .react, .toggleReaction, .redact, .report: .change
        case .seenBy, .viewSource, .viewDraftCode: .inspect
        }
    }
    
    var rankInMenuCard: Int {
        switch self {
        case .copy, .copyCaption: 0
        case .copyPermalink: 1
        case .translate: 2
        case .endPoll: -1
        case .removeCaption: 9
        default: 0
        }
    }
}

private extension EncryptionAuthenticity {
    var foregroundStyle: SwiftUI.Color {
        switch color {
        case .red: .compound.textCriticalPrimary
        case .gray: .compound.textSecondary
        }
    }
}

// MARK: - Previews

struct TimelineItemMenu_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    enum ItemType { case incomingText, outgoingMedia, outgoingMediaWithCaption, outgoingText, outgoingPoll } // AGENT-PLATFORM (Brief 0083): own message and poll
    
    static let viewModel = TimelineViewModel.mock
    static let (item, actions) = makeActions()
    static let (backupItem, _) = makeActions(authenticity: .notGuaranteed(color: .gray))
    static let (unsignedItem, _) = makeActions(authenticity: .unsignedDevice(color: .red))
    static let (unencryptedItem, _) = makeActions(authenticity: .sentInClear(color: .red))
    static let (unknownFailureItem, _) = makeActions(deliveryStatus: .sendingFailed(.unknown(reason: nil)))
    static let (identityChangedItem, _) = makeActions(deliveryStatus: .sendingFailed(.verifiedUser(.changedIdentity(users: [
        "@alice:matrix.org"
    ]))))
    static let (unsignedDevicesItem, _) = makeActions(deliveryStatus: .sendingFailed(.verifiedUser(.hasUnsignedDevice(devices: [
        "@alice:matrix.org": ["DEVICE1", "DEVICE2"]
    ]))))
    static let (ownUnsignedDevicesItem, _) = makeActions(deliveryStatus: .sendingFailed(.verifiedUser(.hasUnsignedDevice(devices: [
        RoomMemberProxyMock.mockMe.userID: ["DEVICE1"]
    ]))))
    
    // Media
    
    static let (mediaItem, mediaItemActions) = makeActions(itemType: .outgoingMedia)
    static let (mediaItemWithCaption, mediaItemWithCaptionActions) = makeActions(itemType: .outgoingMediaWithCaption)
    
    // AGENT-PLATFORM (Brief 0083): an own message, an own failed send and a poll, each with its own actions.
    static let (ownItem, ownItemActions) = makeActions(itemType: .outgoingText, hasReaders: true)
    static let (ownFailedItem, ownFailedItemActions) = makeActions(itemType: .outgoingText, deliveryStatus: .sendingFailed(.unknown(reason: nil)))
    static let (pollItem, pollItemActions) = makeActions(itemType: .outgoingPoll)
    
    static var previews: some View {
        TimelineItemMenu(item: item, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Normal")
        
        TimelineItemMenu(item: item, actions: actions)
            .environmentObject(viewModel.context)
            .environment(\._accessibilityShowButtonShapes, true)
            .previewDisplayName("Button shapes")
        
        TimelineItemMenu(item: backupItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Authenticity")
        
        TimelineItemMenu(item: unsignedItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Unsigned")
        
        TimelineItemMenu(item: unencryptedItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Unencrypted")
        
        TimelineItemMenu(item: unknownFailureItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Unknown failure")
        
        TimelineItemMenu(item: unsignedDevicesItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Unsigned Devices")
        
        TimelineItemMenu(item: ownUnsignedDevicesItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Own Unsigned Devices")
        
        TimelineItemMenu(item: identityChangedItem, actions: actions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Identity Changed")
        
        // Media
        
        TimelineItemMenu(item: mediaItem, actions: mediaItemActions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Media")
        
        TimelineItemMenu(item: mediaItemWithCaption, actions: mediaItemWithCaptionActions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Media with Caption")
        
        // AGENT-PLATFORM (Brief 0083): an own message, an own failed send and a poll.
        
        TimelineItemMenu(item: ownItem, actions: ownItemActions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Own message")
        
        TimelineItemMenu(item: ownFailedItem, actions: ownFailedItemActions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Own failed send")
        
        TimelineItemMenu(item: pollItem, actions: pollItemActions)
            .environmentObject(viewModel.context)
            .previewDisplayName("Poll")
    }
    
    static func makeActions(itemType: ItemType = .incomingText,
                            authenticity: EncryptionAuthenticity? = nil,
                            deliveryStatus: TimelineItemDeliveryStatus? = nil,
                            hasReaders: Bool = false) -> (EventBasedTimelineItemProtocol, TimelineItemMenuActions)! {
        guard var item = makeItem(itemType: itemType) else { return nil }
        
        // AGENT-PLATFORM (Brief 0083): the item changes before its actions are made, so a failed send shows its own.
        if var textItem = item as? TextRoomTimelineItem {
            if let authenticity {
                textItem.properties.encryptionAuthenticity = authenticity
            }
            
            if let deliveryStatus {
                textItem.properties.deliveryStatus = deliveryStatus
            }
            item = textItem
        }
        
        let provider = TimelineItemMenuActionProvider(timelineItem: item,
                                                      canCurrentUserSendMessage: true,
                                                      canCurrentUserRedactSelf: true,
                                                      canCurrentUserRedactOthers: false,
                                                      canCurrentUserPin: true,
                                                      pinnedEventIDs: [],
                                                      isViewSourceEnabled: true,
                                                      areThreadsEnabled: true,
                                                      timelineKind: .live,
                                                      emojiProvider: EmojiProvider(userSettings: .mock()),
                                                      hasReaders: hasReaders)
        guard let actions = provider.makeActions() else { return nil }
        
        return (item, actions)
    }
    
    static func makeItem(itemType: ItemType) -> EventBasedTimelineItemProtocol? {
        switch itemType {
        case .incomingText:
            TimelineFixtures.singleMessageChunk.first as? EventBasedTimelineItemProtocol
        case .outgoingMedia:
            TimelineFixtures.mediaChunk[1] as? EventBasedTimelineItemProtocol
        case .outgoingMediaWithCaption:
            TimelineFixtures.mediaChunk[5] as? EventBasedTimelineItemProtocol
        // AGENT-PLATFORM (Brief 0083): an own message you reacted 👍 to, and an own poll.
        case .outgoingText:
            TextRoomTimelineItem(id: .event(uniqueID: .init("TimelineItemMenu.own"), eventOrTransactionID: .eventID("$own")),
                                 timestamp: .mock,
                                 isOutgoing: true,
                                 isEditable: true,
                                 canBeRepliedTo: true,
                                 sender: .init(id: "@alice:matrix.org", displayName: "Alice"),
                                 content: .init(body: "New home office set up!"),
                                 properties: RoomTimelineItemProperties(reactions: [
                                     AggregatedReaction(accountOwnerID: "@alice:matrix.org", key: "👍️",
                                                        senders: [ReactionSender(id: "@alice:matrix.org", timestamp: .mock)])
                                 ]))
        case .outgoingPoll:
            TimelineFixtures.outgoingPolls.first as? EventBasedTimelineItemProtocol
        }
    }
}
