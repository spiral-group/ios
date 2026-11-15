//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct TimelineItemBubbledStylerView<Content: View>: View {
    @Environment(\.timelineContext) private var context
    @Environment(\.timelineRowContext) private var rowContext // AGENT-PLATFORM (Brief 0083, question 359): all it reads of the state
    @Environment(\.timelineGroupStyle) private var timelineGroupStyle
    @Environment(\.focussedEventID) private var focussedEventID
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn // AGENT-PLATFORM (Brief 0083)
    
    let timelineItem: EventBasedTimelineItemProtocol
    let adjustedDeliveryStatus: TimelineItemDeliveryStatus?
    let content: Content
    
    /// Whether the item's media failed content scanning, in which case the bubble holds the
    /// failure's card. Reported by the item's `ContentScanningView` through the preference key.
    @State private var contentScanningFailure: ContentScanningFailure?
    
    private var hasContentScanningFailure: Bool {
        contentScanningFailure != nil
    }
    
    private var isDM: Bool {
        rowContext.isDM
    }
    
    private var isFocussed: Bool {
        focussedEventID != nil && timelineItem.id.eventID == focussedEventID
    }
    
    private var isMessageSelectionActive: Bool {
        rowContext.isSelecting
    }
    
    private var isSelected: Bool {
        rowContext.isSelected
    }
    
    private var accessibilitySelection: TimelineItemAccessibilityMessageSelection {
        guard isMessageSelectionActive else { return .none }
        return .selecting(isSelected: isSelected, selectedCount: rowContext.selectedCount)
    }
    
    /// The base padding applied to bubbles on either side.
    ///
    /// **Note:** This is on top of the insets applied to the cells by the table view.
    private let bubbleHorizontalPadding: CGFloat = 8
    
    // AGENT-PLATFORM (Brief 0083, question 359): 2 pt between bubbles in a group, 1 in each row.
    private let rowVerticalPadding: CGFloat = 1
    
    // AGENT-PLATFORM (Brief 0083): the column the sender's avatar sits in, at the avatar's own scaled size.
    @ScaledMetric private var senderAvatarWidth = UserAvatarSizeOnScreen.timeline.value
    
    var body: some View {
        #if SPIRAL_TIMELINE_BENCH // AGENT-PLATFORM (Brief 0083, question 359): how many bubbles re-render.
        let _ = TimelineBenchProbe.shared.noteStylerBody(timelineItem.id.uniqueID)
        #endif
        #if DEBUG
        let _ = TimelineSignposts.noteBody(.styler, of: timelineItem.id.uniqueID) // AGENT-PLATFORM (Brief 0083, question 359)
        #endif
        HStack(spacing: 10) {
            if isMessageSelectionActive {
                selectionIndicator
            }
            
            bubble
        }
        .padding(EdgeInsets(top: rowVerticalPadding, leading: 8, bottom: rowVerticalPadding, trailing: 8))
        .highlightedTimelineItem(isFocussed)
        .overlay { selectionOverlay }
        .animation(.elementDefault.disabledDuringTests(), value: isMessageSelectionActive)
        .onPreferenceChange(ContentScanningFailurePreferenceKey.self) { contentScanningFailure = $0 }
    }
    
    private var selectionIndicator: some View {
        // The ZStack keeps the transition on the indicator's appearance rather than its checked state.
        ZStack {
            ListRowAccessory.multiSelection(isSelected)
                .opacity(timelineItem.isForwardable ? 1 : 0) // Keeps the bubbles aligned.
        }
        .padding(.leading, 8)
        .transition(.move(edge: .leading).combined(with: .opacity))
        .accessibilityHidden(true) // The bubble itself carries the selected state.
    }
    
    /// Captures every touch while selecting so the content's own gestures can't fire.
    @ViewBuilder
    private var selectionOverlay: some View {
        if isMessageSelectionActive {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection() }
                .onLongPressGesture { toggleSelection() }
                .accessibilityHidden(true)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, the room's timeline): Messages' layout in a group. The sender's name sits above
    // the first bubble of a group, in the bubble's text column, and their avatar beside the last bubble, on its
    // bottom edge. Element drew both above every group, the avatar overlapping the bubble.
    private var bubble: some View {
        HStack(alignment: .bubbleBottom, spacing: 8) {
            if showsSender {
                senderAvatar
            }
            
            VStack(alignment: alignment, spacing: 2) {
                if showsSender, shouldShowSenderDetails, !isSenderNameInBubble {
                    senderName
                        .chatBackgroundChip()
                        .padding(.horizontal, 12)
                }
                
                HStack(spacing: 0) {
                    if timelineItem.isOutgoing {
                        Spacer()
                    }
                    
                    messageBubbleWithReactions
                }
                .padding(timelineItem.isOutgoing ? .leading : .trailing, 48) // Additional padding to differentiate alignment.
            }
        }
        .padding(.horizontal, bubbleHorizontalPadding)
        .padding(.top, groupTopPadding)
    }
    
    // AGENT-PLATFORM (Brief 0083): the avatar beside a group's last bubble, and an empty column beside the others.
    @ViewBuilder
    private var senderAvatar: some View {
        if timelineGroupStyle.shouldShowSenderAvatar {
            TimelineSenderAvatarView(sender: timelineItem.sender)
                // sender info are read inside the `TimelineAccessibilityModifier`
                .accessibilityHidden(true)
                .onTapGesture {
                    context?.send(viewAction: .tappedOnSenderDetails(sender: timelineItem.sender))
                }
        } else {
            Color.clear
                .frame(width: senderAvatarWidth, height: 0)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357, reversing 331 (b)): the sender's name in their hue, in the bubble, and above
    // a picture or a post with no bubble.
    private var senderName: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                .font(isSenderNameInBubble ? .compound.bodySMSemibold : .compound.bodySM)
                .foregroundStyle(SenderHue(userID: timelineItem.sender.id).color)
            
            if let statusEmoji = timelineItem.sender.status.displayed?.emoji {
                Text(String(statusEmoji))
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textPrimary)
            }
            
            if timelineItem.sender.displayName != nil, timelineItem.sender.isDisplayNameAmbiguous {
                Text(timelineItem.sender.id)
                    .font(.compound.bodyXS)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
        .lineLimit(1)
        // sender info are read inside the `TimelineAccessibilityModifier`
        .accessibilityHidden(true)
        .onTapGesture {
            context?.send(viewAction: .tappedOnSenderDetails(sender: timelineItem.sender))
        }
    }
    
    // AGENT-PLATFORM (Brief 0066 step 6): a row may hang its own chips
    // under the bubble, where reactions go — a draft's Code / Publish.
    @Environment(\.timelineItemAccessory) private var accessory
    
    // AGENT-PLATFORM (Brief 0083, the room's timeline): the bubble, then what belongs to it. Reactions sit under the
    // bubble instead of overlapping its edge.
    private var messageBubbleWithReactions: some View {
        var sendInfo = TimelineItemSendInfo(timelineItem: timelineItem,
                                            adjustedDeliveryStatus: adjustedDeliveryStatus,
                                            hasContentScanningFailure: hasContentScanningFailure,
                                            deliveryStatus: rowContext.deliveryStatus(of: timelineItem, adjustedDeliveryStatus: adjustedDeliveryStatus))
        sendInfo.edgeInset = pictureReachesEdges ? Self.edgeContentInset : 0
        sendInfo.isPinned = rowContext.isPinned
        
        return VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 0) {
                messageBubbleWithActions(sendInfo: sendInfo)
                    .timelineItemAccessibility(timelineItem, selection: accessibilitySelection) {
                        if isMessageSelectionActive {
                            toggleSelection()
                        } else {
                            context?.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id))
                        }
                    }
                    .sendInfoAccessibility(sendInfo)
                
                // AGENT-PLATFORM (Brief 0083): a failed send's mark beside the bubble, as Messages draws it.
                if sendInfo.showsFailureMark {
                    TimelineItemSendFailureMark(sendInfo: sendInfo)
                        .accessibilityHidden(isMessageSelectionActive)
                }
            }
            .alignmentGuide(.bubbleBottom) { $0[.bottom] }
            
            if let accessory {
                accessory
                    .padding(.horizontal, 4)
                    // As for reactions: keep the long press off the chips.
                    .onTapGesture { }
            }
            
            // Do not display reactions in the pinned events timeline
            if rowContext.timelineKind != .pinned,
               !timelineItem.properties.reactions.isEmpty {
                TimelineReactionsView(context: context,
                                      itemID: timelineItem.id,
                                      reactions: timelineItem.properties.reactions,
                                      isLayoutRTL: timelineItem.isOutgoing)
                    // Workaround to stop the message long press stealing the touch from the reaction buttons
                    .onTapGesture { }
                    .accessibilityHidden(isMessageSelectionActive)
            }
            
            if rowContext.areThreadsEnabled,
               !rowContext.timelineKind.isThread,
               let threadSummary = timelineItem.properties.threadSummary {
                TimelineThreadSummaryView(threadSummary: threadSummary) {
                    context?.send(viewAction: .displayThread(itemID: timelineItem.id))
                }
                .chatBackgroundChip()
                .accessibilityHidden(isMessageSelectionActive)
            }
            
            // AGENT-PLATFORM (Brief 0083, decision 323): a failed send says so under the bubble. Its time is in the bubble.
            if sendInfo.showsFailureMark {
                TimelineItemSendFailureLabel(sendInfo: sendInfo)
                    .padding(.horizontal, 6)
            }
        }
    }
    
    func messageBubbleWithActions(sendInfo: TimelineItemSendInfo) -> some View {
        messageBubble(sendInfo: sendInfo)
            .onTapGesture {
                // We need a tap gesture before the long press gesture below, otherwise something
                // on iOS 17 hijacks the long press and you can't bring up the context menu. This
                // is no longer an issue on iOS 18. Note: it's fine for this to be empty, we handle
                // specific taps within the timeline views themselves.
            }
            // The UIKit recogniser would still receive touches through the selection overlay.
            .longPressWithFeedback(isEnabled: !isMessageSelectionActive) {
                context?.send(viewAction: .displayTimelineItemMenu(itemID: timelineItem.id))
            }
            .swipeRightAction {
                CompoundIcon(\.reply)
                    .foregroundColor(.compound.iconPrimary)
                    .accessibilityHidden(true)
            } shouldStartAction: {
                !isMessageSelectionActive && timelineItem.canBeRepliedTo
            } action: {
                context?.send(viewAction: .handleTimelineItemMenuAction(itemID: timelineItem.id,
                                                                        action: .reply(isThread: timelineItem.properties.isThreaded)))
            }
            .macContextMenu {
                if !isMessageSelectionActive {
                    macContextMenu
                }
            }
    }
    
    @ViewBuilder
    private var macContextMenu: some View {
        if let context {
            TimelineItemMacContextMenu(item: timelineItem) {
                let viewState = context.viewState
                return TimelineItemMenuActionProvider(timelineItem: timelineItem,
                                                      canCurrentUserSendMessage: viewState.canCurrentUserSendMessage,
                                                      canCurrentUserRedactSelf: viewState.canCurrentUserRedactSelf,
                                                      canCurrentUserRedactOthers: viewState.canCurrentUserRedactOthers,
                                                      canCurrentUserPin: viewState.canCurrentUserPin,
                                                      pinnedEventIDs: viewState.pinnedEventIDs,
                                                      isViewSourceEnabled: viewState.isViewSourceEnabled,
                                                      areThreadsEnabled: viewState.areThreadsEnabled,
                                                      timelineKind: viewState.timelineKind,
                                                      emojiProvider: viewState.emojiProvider,
                                                      hasReaders: viewState.hasReaders(timelineItem))
            } send: { action in
                context.send(viewAction: .handleTimelineItemMenuAction(itemID: timelineItem.id, action: action))
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 343): the bubble's shape is the only clip around a post. Measured on iOS 27,
    // the mask of the post's old strip, nested inside it, cancelled it there: the post's top corners came out square.
    func messageBubble(sendInfo: TimelineItemSendInfo) -> some View {
        contentWithReply
            .timelineItemSendInfo(sendInfo)
            .bubbleBackground(insets: pictureReachesEdges ? .zero : timelineItem.bubbleInsets(hasContentScanningFailure: hasContentScanningFailure),
                              color: bubbleFill,
                              borderColor: ownBubbleInk?.outline,
                              cornerRadius: timelineItem.bubbleCornerRadius,
                              // A sticker's outline is its own, not a rectangle's.
                              shadowClearance: hasContentScanningFailure || !(timelineItem is StickerRoomTimelineItem) ? rowVerticalPadding + groupTopPadding : nil)
            // AGENT-PLATFORM (Brief 0083, decision 300a): what draws on an own bubble takes its ink.
            .environment(\.ownBubbleInk, ownBubbleInk)
            .environment(\.isTimelineItemPinned, sendInfo.isPinned)
            // AGENT-PLATFORM: cap the bubble width (ADR-0005) — long
            // messages no longer span edge-to-edge; matches the
            // Apple/Telegram reference and improves iPad readability.
            .frame(maxWidth: 340, alignment: timelineItem.isOutgoing ? .trailing : .leading)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): on the room's background, what was grey on the canvas takes the canvas's own
    // surface, and a bubble with no fill keeps its text off the picture: grey reads 2.09:1 on the hills' deepest blue, 4.62:1 here.
    private var bubbleFill: Color? {
        guard timelineItem.hasBubbleSurface || hasContentScanningFailure else { return nil }
        guard let ownBubbleInk else {
            return isChatBackgroundDrawn ? .spiral.chatBackgroundSurface : .compound._bgBubbleIncoming
        }
        return ownBubbleInk.fill ?? (isChatBackgroundDrawn ? .spiral.chatBackgroundSurface.opacity(0.85) : nil)
    }
    
    private var isSenderNameInBubble: Bool {
        showsSender && shouldShowSenderDetails && (timelineItem.hasBubbleSurface || hasContentScanningFailure)
    }
    
    /// Level with the bubble's text, whatever inset the bubble itself has.
    private var senderNameInsets: EdgeInsets {
        let insets = pictureReachesEdges ? .zero : timelineItem.bubbleInsets(hasContentScanningFailure: hasContentScanningFailure)
        return EdgeInsets(top: insets.top == 0 ? 8 : 0, leading: 12 - insets.leading, bottom: -5, trailing: 12 - insets.trailing)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): nil on a bubble that keeps the neutral colours. A blocked file stays on its
    // sender's side, with the bubble it would have had (question 359).
    private var ownBubbleInk: OwnBubbleInk? {
        hasContentScanningFailure ? (timelineItem.isOutgoing ? .solid : nil) : timelineItem.ownBubbleInk
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): the picture touches the bubble, and what sits with it keeps the inset.
    private var pictureReachesEdges: Bool {
        !hasContentScanningFailure && timelineItem.pictureReachesEdges
    }
    
    private static var edgeContentInset: CGFloat {
        8
    }
    
    private var edgeHeaderInsets: EdgeInsets {
        guard pictureReachesEdges else { return .zero }
        return EdgeInsets(top: Self.edgeContentInset, leading: Self.edgeContentInset, bottom: 0, trailing: Self.edgeContentInset)
    }
    
    @ViewBuilder
    var contentWithReply: some View {
        // AGENT-PLATFORM (Brief 0083, question 359): most bubbles hold their content alone, which has nothing to lay out.
        if isSenderNameInBubble || showsThreadDecorator || timelineItem.properties.replyDetails != nil {
            TimelineBubbleLayout(spacing: 8) {
                if isSenderNameInBubble {
                    senderName
                        .padding(senderNameInsets)
                        .timelineBubbleLayoutSize(.natural)
                }
                
                if showsThreadDecorator {
                    ThreadDecorator()
                        .padding(.leading, 4)
                        .padding(edgeHeaderInsets)
                        .timelineBubbleLayoutSize(.natural)
                }
                
                if let replyDetails = timelineItem.properties.replyDetails {
                    // The rendered reply bubble with a greedy width. The custom layout prevents
                    // the infinite width from increasing the overall width of the view.
                    
                    TimelineReplyView(placement: .timeline, timelineItemReplyDetails: replyDetails, maxWidth: .infinity)
                        .padding(edgeHeaderInsets)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .rendering))
                        .onTapGesture {
                            if rowContext.timelineKind != .pinned {
                                context?.send(viewAction: .focusOnEventID(replyDetails.eventID))
                            }
                        }
                    
                    // Add a fixed width reply bubble that is used for layout calculations but won't be rendered.
                    TimelineReplyView(placement: .timeline, timelineItemReplyDetails: replyDetails)
                        .padding(edgeHeaderInsets)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .layout))
                        .hidden()
                }
                
                bubbleContent
                    .timelineBubbleLayoutSize(.natural)
            }
        } else {
            bubbleContent
        }
    }
    
    private var showsThreadDecorator: Bool {
        !rowContext.timelineKind.isThread && timelineItem.properties.isThreaded
    }
    
    private var bubbleContent: some View {
        content
            .cornerRadius(pictureReachesEdges ? 0 : timelineItem.contentCornerRadius)
    }
    
    private func toggleSelection() {
        guard timelineItem.isForwardable else { return }
        context?.send(viewAction: .toggleMessageSelection(itemID: timelineItem.id))
    }
    
    // AGENT-PLATFORM (Brief 0083): one gap above every group, incoming or own.
    private var groupTopPadding: CGFloat {
        timelineGroupStyle == .single || timelineGroupStyle == .first ? 8 : 0
    }
    
    private var alignment: HorizontalAlignment {
        timelineItem.isOutgoing ? .trailing : .leading
    }
    
    // AGENT-PLATFORM (Brief 0083): the sender's name and avatar, in a group room's incoming messages.
    private var showsSender: Bool {
        !timelineItem.isOutgoing && !isDM
    }
    
    private var shouldShowSenderDetails: Bool {
        timelineGroupStyle.shouldShowSenderDetails
    }
}

private extension View {
    /// AGENT-PLATFORM (Brief 0083, question 359): the menu is a Mac's alone. Everywhere else it was an empty context menu on every bubble.
    @ViewBuilder
    func macContextMenu(@ViewBuilder menuItems: () -> some View) -> some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            contextMenu(menuItems: menuItems)
        } else {
            self
        }
    }
}

// AGENT-PLATFORM (Brief 0083): VoiceOver reads the send info with the message, once. The label in the bubble is hidden.
private struct SendInfoAccessibilityModifier: ViewModifier {
    let sendInfo: TimelineItemSendInfo
    
    func body(content: Content) -> some View {
        if sendInfo.isReadWithMessage {
            content
                .accessibilityLabel { label in
                    label
                    if sendInfo.isPinned {
                        Text(L10n.commonPinned)
                    }
                    Text(sendInfo.localizedString)
                    if let statusAccessibilityLabel = sendInfo.statusAccessibilityLabel {
                        Text(statusAccessibilityLabel)
                    }
                    if let deliveryStatus = sendInfo.deliveryStatus {
                        Text(deliveryStatus.accessibilityLabel)
                    }
                }
        } else if sendInfo.isGallery, sendInfo.isPinned || sendInfo.deliveryStatus != nil {
            content
                .accessibilityLabel { label in
                    label
                    if sendInfo.isPinned {
                        Text(L10n.commonPinned)
                    }
                    if let deliveryStatus = sendInfo.deliveryStatus {
                        Text(deliveryStatus.accessibilityLabel)
                    }
                }
        } else {
            content
        }
    }
}

private extension View {
    func sendInfoAccessibility(_ sendInfo: TimelineItemSendInfo) -> some View {
        modifier(SendInfoAccessibilityModifier(sendInfo: sendInfo))
    }
}

// AGENT-PLATFORM (Brief 0083): the bottom edge of the bubble, which the sender's avatar sits on.
private extension VerticalAlignment {
    enum BubbleBottom: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.bottom]
        }
    }
    
    static let bubbleBottom = VerticalAlignment(BubbleBottom.self)
}

/// A view a row hangs under its bubble, drawn where reactions are drawn and
/// in their style (`TimelineReactionButtonLabel`): outside the bubble, so
/// the bubble keeps its own shape — which for an Interactive Post is the
/// shape the room gives it.
private struct TimelineItemAccessoryKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var timelineItemAccessory: AnyView? {
        get { self[TimelineItemAccessoryKey.self] }
        set { self[TimelineItemAccessoryKey.self] = newValue }
    }
}

extension EventBasedTimelineItemProtocol {
    // AGENT-PLATFORM (Brief 0083, decision 300a, question 357): everything you send is blue, whatever it holds, and what can't
    // be shown is hollow. A photo, a video or a map alone has no surface, so it has no ink.
    var ownBubbleInk: OwnBubbleInk? {
        guard isOutgoing, hasBubbleSurface else { return nil }
        switch self {
        case is RedactedRoomTimelineItem, is EncryptedRoomTimelineItem, is UnsupportedRoomTimelineItem:
            return .hollow
        default:
            return .solid
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 357): a picture reaches its bubble's edges, on either side, so a fill never frames it.
    // A location with no map is a line of text, and a gallery of files a list.
    var pictureReachesEdges: Bool {
        switch self {
        case is ImageRoomTimelineItem, is VideoRoomTimelineItem, is LiveLocationRoomTimelineItem:
            true
        case let locationTimelineItem as LocationRoomTimelineItem:
            locationTimelineItem.content.geoURI != nil
        case let galleryTimelineItem as GalleryRoomTimelineItem:
            !galleryTimelineItem.usesListLayout
        default:
            false
        }
    }
}

private extension EventBasedTimelineItemProtocol {
    var hasBubbleSurface: Bool {
        switch self {
        case is ImageRoomTimelineItem, is VideoRoomTimelineItem:
            // In case a reply detail or a thread decorator is present we render the color and the padding
            return properties.replyDetails != nil || properties.isThreaded || hasMediaCaption
        // AGENT-PLATFORM (question 413): an album alone is its pictures, as a photo is, with the chat between its tiles.
        case let galleryTimelineItem as GalleryRoomTimelineItem:
            return galleryTimelineItem.usesListLayout || properties.replyDetails != nil || properties.isThreaded || hasMediaCaption
        case is StickerRoomTimelineItem:
            return false
        // AGENT-PLATFORM (Brief 0083): a map reaches the bubble's edges, as `bubbleInsets` lays it out, so a fill
        // behind it showed only at its corners, as a 1 pt halo (blue on an own bubble). A text or a reply keeps it.
        case let locationTimelineItem as LocationRoomTimelineItem:
            return locationTimelineItem.content.geoURI == nil || properties.replyDetails != nil || properties.isThreaded
        case is LiveLocationRoomTimelineItem:
            return properties.replyDetails != nil || properties.isThreaded
        // AGENT-PLATFORM (Brief 0066): a post draws its own surface edge to
        // edge, like a photo. A bubble behind it is a second background nobody
        // can see, except at the corners where it shows as a grey halo.
        // `isThreaded` is not consulted: a draft always lives in a thread and
        // a post may, and in the thread's own timeline there is no decorator
        // to make room for — the post is drawn as the room will draw it. A
        // draft IS a post, with an actions row under it; same surface.
        //
        // AGENT-PLATFORM (Brief 0083, question 357): the strip with its time is a part of the bubble now, so the fill
        // is what draws it, and the bubble's shape rounds the strip's corners with no mask around the post (343).
        // A draft is a post with a Publish button under it, as a poll has
        // "End poll": the bubble's fill runs behind both.
        default:
            return true
        }
    }
    
    /// The insets for the full bubble content.
    /// Padding affecting just the "send info" should be added inside `TimelineItemSendInfoLabel`
    func bubbleInsets(hasContentScanningFailure: Bool) -> EdgeInsets {
        let defaultInsets: EdgeInsets = .init(around: 8)
        
        // The content scanner failure placeholder is always rendered inset within the critical bubble.
        if hasContentScanningFailure {
            return defaultInsets
        }
        
        switch self {
        case is StickerRoomTimelineItem:
            return .zero
        case is CallSummaryRoomTimelineItem:
            return CallSummaryCard.insets // AGENT-PLATFORM (decision 371)
        case is PollRoomTimelineItem:
            return .init(top: 12, leading: 12, bottom: 4, trailing: 12)
        // In case a reply detail or a thread decorator is present we render the color and the padding
        case is ImageRoomTimelineItem, is VideoRoomTimelineItem:
            return properties.replyDetails != nil || properties.isThreaded || hasMediaCaption ? defaultInsets : .zero
        case let locationTimelineItem as LocationRoomTimelineItem:
            return locationTimelineItem.content.geoURI == nil ||
                properties.replyDetails != nil ||
                properties.isThreaded ? defaultInsets : .zero
        case is LiveLocationRoomTimelineItem:
            return properties.replyDetails != nil ||
                properties.isThreaded ? defaultInsets : .zero
        case is InteractivePostRoomTimelineItem:
            return properties.replyDetails != nil ? defaultInsets : .zero
        // Zero: the post reaches the bubble's edges and the bubble's own
        // radius clips it; the button pads itself.
        case is InteractiveDraftRoomTimelineItem, is InteractiveGeneratingRoomTimelineItem:
            return .zero
        default:
            return defaultInsets
        }
    }
    
    // AGENT-PLATFORM (decision 371): a card keeps the round of the call cards.
    var bubbleCornerRadius: CGFloat {
        self is CallSummaryRoomTimelineItem ? SpiralRadius.callBubble : SpiralRadius.bubble
    }
    
    // AGENT-PLATFORM (Brief 0083): media inside a bubble take the thumbnail radius.
    var contentCornerRadius: CGFloat {
        switch self {
        case is InteractivePostRoomTimelineItem, is InteractiveDraftRoomTimelineItem, is InteractiveGeneratingRoomTimelineItem:
            return properties.replyDetails != nil ? SpiralRadius.thumbnail : .zero
        case is ImageRoomTimelineItem, is VideoRoomTimelineItem, is LocationRoomTimelineItem, is LiveLocationRoomTimelineItem:
            return properties.replyDetails != nil || properties.isThreaded ? SpiralRadius.thumbnail : .zero
        default:
            return .zero
        }
    }
}

private extension EdgeInsets {
    init(around: CGFloat) {
        self.init(top: around, leading: around, bottom: around, trailing: around)
    }
    
    static var zero: Self = .init(around: 0)
}

private extension TimelineItemKeyForwarder {
    static var test: TimelineItemKeyForwarder {
        TimelineItemKeyForwarder(id: "@alice:matrix.org", displayName: "alice")
    }
}

// MARK: - Previews

struct TimelineItemBubbledStylerView_Previews: PreviewProvider, TestablePreview {
    static let viewModel: TimelineViewModel = {
        let userSettings = UserSettings.mock()
        userSettings.app.threadsEnabled = true
        let userSession = UserSessionMock(.init(userSettings: userSettings))
        
        let roomProxy = JoinedRoomProxyMock(.init())
        return TimelineViewModel(roomProxy: roomProxy,
                                 focussedEventID: nil,
                                 timelineController: TimelineControllerMock(.init()),
                                 userSession: userSession,
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: userSettings),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }()
    
    static let unsafeViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
    
    static let selectingViewModel: TimelineViewModel = {
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init()),
                                          focussedEventID: nil,
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(userSettings: .mock()),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        viewModel.state.messageSelection.isActive = true
        viewModel.state.messageSelection.selectedEventIDs = ["selected"]
        return viewModel
    }()
    
    static var previews: some View {
        mockTimeline
            .previewDisplayName("Mock Timeline")
            .previewLayout(.fixed(width: 390, height: 900))
            .padding(.bottom, 20)
        mockTimeline
            .environment(\.layoutDirection, .rightToLeft)
            .previewDisplayName("Mock Timeline RTL")
            .previewLayout(.fixed(width: 390, height: 900))
            .padding(.bottom, 20)
        replies
            .previewDisplayName("Replies")
        threadDecorator
            .previewDisplayName("Thread decorator")
            .previewLayout(.fixed(width: 390, height: 1700))
            .padding(.bottom, 20)
        threadSummary
            .previewDisplayName("Thread summary")
            .previewLayout(.fixed(width: 390, height: 1700))
            .padding(.bottom, 20)
        encryptionAuthenticity
            .previewDisplayName("Encryption Indicators")
        encryptionForwarder
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Encryption Forwarder Info")
        pinned
            .previewDisplayName("Pinned messages")
            .previewLayout(.fixed(width: 390, height: 1150))
            .padding(.bottom, 20)
        selection
            .previewDisplayName("Selection")
    }
    
    static var selection: some View {
        let rowContextInputs = TimelineRowContextInputs(selectingViewModel.state)
        let items: [RoomTimelineItemProtocol] = [TextRoomTimelineItem(id: .event(uniqueID: .init("1"), eventOrTransactionID: .eventID("selected")),
                                                                      timestamp: .mock,
                                                                      isOutgoing: false,
                                                                      isEditable: false,
                                                                      canBeRepliedTo: true,
                                                                      sender: .init(id: "@alice:matrix.org", displayName: "Alice"),
                                                                      content: .init(body: "A selected message.")),
                                                 TextRoomTimelineItem(id: .event(uniqueID: .init("2"), eventOrTransactionID: .eventID("unselected")),
                                                                      timestamp: .mock,
                                                                      isOutgoing: true,
                                                                      isEditable: false,
                                                                      canBeRepliedTo: true,
                                                                      sender: .init(id: "@bob:matrix.org"),
                                                                      content: .init(body: "A message that isn't selected.")),
                                                 RedactedRoomTimelineItem(id: .event(uniqueID: .init("3"), eventOrTransactionID: .eventID("redacted")),
                                                                          body: "Message removed",
                                                                          timestamp: .mock,
                                                                          isOutgoing: false,
                                                                          isEditable: false,
                                                                          canBeRepliedTo: false,
                                                                          sender: .init(id: "@alice:matrix.org", displayName: "Alice"))]
        
        return VStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                RoomTimelineItemView(viewState: .init(item: item, groupStyle: .single, rowContext: rowContextInputs.rowContext(for: item.id)))
            }
        }
        .environment(\.timelineContext, selectingViewModel.context)
    }
    
    static var mockTimeline: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.state.timelineState.itemViewStates) { viewState in
                    RoomTimelineItemView(viewState: viewState)
                }
            }
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var replies: some View {
        VStack(spacing: 0) {
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "A long message that should be on multiple lines."),
                                                                             properties: .init(replyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                                                                     eventID: "123",
                                                                                                                     eventContent: .message(.text(.init(body: "Short")))))),
                                                  groupStyle: .single))
            
            let properties = RoomTimelineItemProperties(replyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                              eventID: "123",
                                                                              eventContent: .message(.text(.init(body: "A long message that should be on more than 2 lines and so will be clipped by the layout.")))))
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Short message"),
                                                                             properties: properties),
                                                  groupStyle: .single))
            
            RoomTimelineItemView(viewState: .init(item: FileRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(filename: "unsafe.pdf",
                                                                                            caption: "Replying with an unsafe file.",
                                                                                            formattedCaption: nil,
                                                                                            source: try? MediaSourceProxy(url: .mockMXCFile, mimeType: nil),
                                                                                            fileSize: 3 * 1024 * 1024,
                                                                                            thumbnailSource: nil,
                                                                                            contentType: nil),
                                                                             properties: .init(replyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                                                                     eventID: "123",
                                                                                                                     eventContent: .message(.text(.init(body: "Short")))))),
                                                  groupStyle: .single))
                .environmentObject(unsafeViewModel.context)
                .environment(\.timelineContext, unsafeViewModel.context)
            
            // A safe message replying to an unsafe image: only the reply preview shows the failure.
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Replying to an unsafe image."),
                                                                             properties: .init(replyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                                                                     eventID: "123",
                                                                                                                     eventContent: .message(.image(.init(filename: "amazing.jpeg",
                                                                                                                                                         imageInfo: .mockImage,
                                                                                                                                                         thumbnailInfo: .mockThumbnail)))))),
                                                  groupStyle: .single))
                .environmentObject(unsafeViewModel.context)
                .environment(\.timelineContext, unsafeViewModel.context)
            
            // An unsafe file replying to an unsafe image: the whole bubble and the reply preview show the failure.
            RoomTimelineItemView(viewState: .init(item: FileRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(filename: "unsafe.pdf",
                                                                                            caption: "Replying with an unsafe file to an unsafe image.",
                                                                                            formattedCaption: nil,
                                                                                            source: try? MediaSourceProxy(url: .mockMXCFile, mimeType: nil),
                                                                                            fileSize: 3 * 1024 * 1024,
                                                                                            thumbnailSource: nil,
                                                                                            contentType: nil),
                                                                             properties: .init(replyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                                                                     eventID: "123",
                                                                                                                     eventContent: .message(.image(.init(filename: "amazing.jpeg",
                                                                                                                                                         imageInfo: .mockImage,
                                                                                                                                                         thumbnailInfo: .mockThumbnail)))))),
                                                  groupStyle: .single))
                .environmentObject(unsafeViewModel.context)
                .environment(\.timelineContext, unsafeViewModel.context)
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var threadDecorator: some View {
        ScrollView {
            MockTimelineContent(isThreaded: true)
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var threadSummary: some View {
        ScrollView {
            let threadSummary = TimelineItemThreadSummary.loaded(senderID: "@alice:matrix.org",
                                                                 sender: .init(id: "@alice:matrix.org", displayName: "Alice"),
                                                                 latestEventContent: .message(.text(.init(body: "This is a very long, multi-lined, threaded message"))),
                                                                 numberOfReplies: 42)
            
            MockTimelineContent(threadSummary: threadSummary)
        }
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var pinned: some View {
        ScrollView {
            MockTimelineContent(isPinned: true)
        }
        .environment(\.timelineRowContext, .init(isPinned: true))
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var encryptionAuthenticity: some View {
        VStack(spacing: 0) {
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "A long message that should be on multiple lines."),
                                                                             properties: RoomTimelineItemProperties(encryptionAuthenticity: .unsignedDevice(color: .red))),
                                                  groupStyle: .single))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "A long message that should be on multiple lines."),
                                                                             properties: RoomTimelineItemProperties(isEdited: true,
                                                                                                                    encryptionAuthenticity: .unsignedDevice(color: .red))),
                                                  groupStyle: .single))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: false,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Short message"),
                                                                             properties: RoomTimelineItemProperties(encryptionAuthenticity: .unknownDevice(color: .red))),
                                                  groupStyle: .first))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: false,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Message goes Here"),
                                                                             properties: RoomTimelineItemProperties(encryptionAuthenticity: .notGuaranteed(color: .gray))),
                                                  groupStyle: .last))
            
            ImageRoomTimelineView(timelineItem: ImageRoomTimelineItem(id: .randomEvent,
                                                                      timestamp: .mock,
                                                                      isOutgoing: false,
                                                                      isEditable: false,
                                                                      canBeRepliedTo: true,
                                                                      sender: .init(id: "Bob"),
                                                                      content: .init(filename: "other.png",
                                                                                     imageInfo: .mockImage,
                                                                                     thumbnailInfo: nil),
                                                                      
                                                                      properties: RoomTimelineItemProperties(encryptionAuthenticity: .notGuaranteed(color: .gray))))
            
            VoiceMessageRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: true,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: ""),
                                                             content: .init(filename: "audio.ogg",
                                                                            duration: 100,
                                                                            waveform: EstimatedWaveform.mockWaveform,
                                                                            source: nil,
                                                                            fileSize: nil,
                                                                            contentType: nil),
                                                             properties: RoomTimelineItemProperties(isThreaded: true,
                                                                                                    encryptionAuthenticity: .notGuaranteed(color: .gray))),
                                         playerState: AudioPlayerState(id: .timelineItemIdentifier(.randomEvent),
                                                                       title: L10n.commonVoiceMessage,
                                                                       duration: 10,
                                                                       waveform: EstimatedWaveform.mockWaveform))
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
    
    static var encryptionForwarder: some View {
        VStack(spacing: 0) {
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "A long message that should be on multiple lines."),
                                                                             properties: RoomTimelineItemProperties(isEdited: true, encryptionForwarder: .test)),
                                                  groupStyle: .single))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: true,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "A long message that should be on multiple lines."),
                                                                             properties: RoomTimelineItemProperties(encryptionForwarder: .test)),
                                                  groupStyle: .single))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: false,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Short message"),
                                                                             properties: RoomTimelineItemProperties(encryptionForwarder: .test)),
                                                  groupStyle: .first))
            
            RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: .randomEvent,
                                                                             timestamp: .mock,
                                                                             isOutgoing: false,
                                                                             isEditable: false,
                                                                             canBeRepliedTo: true,
                                                                             sender: .init(id: "whoever"),
                                                                             content: .init(body: "Message goes Here"),
                                                                             properties: RoomTimelineItemProperties(encryptionForwarder: .test)),
                                                  groupStyle: .last))
            
            ImageRoomTimelineView(timelineItem: ImageRoomTimelineItem(id: .randomEvent,
                                                                      timestamp: .mock,
                                                                      isOutgoing: false,
                                                                      isEditable: false,
                                                                      canBeRepliedTo: true,
                                                                      sender: .init(id: "Bob"),
                                                                      content: .init(filename: "other.png",
                                                                                     imageInfo: .mockImage,
                                                                                     thumbnailInfo: nil),
                                                                      properties: RoomTimelineItemProperties(encryptionForwarder: .test)))
            
            VoiceMessageRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             isOutgoing: true,
                                                             isEditable: false,
                                                             canBeRepliedTo: true,
                                                             sender: .init(id: ""),
                                                             content: .init(filename: "audio.ogg",
                                                                            duration: 100,
                                                                            waveform: EstimatedWaveform.mockWaveform,
                                                                            source: nil,
                                                                            fileSize: nil,
                                                                            contentType: nil),
                                                             properties: RoomTimelineItemProperties(isThreaded: true,
                                                                                                    encryptionForwarder: .test)),
                                         playerState: AudioPlayerState(id: .timelineItemIdentifier(.randomEvent),
                                                                       title: L10n.commonVoiceMessage,
                                                                       duration: 10,
                                                                       waveform: EstimatedWaveform.mockWaveform))
        }
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
}

private struct MockTimelineContent: View {
    var isThreaded = false
    var isPinned = false
    var threadSummary: TimelineItemThreadSummary?
    
    var body: some View {
        RoomTimelineItemView(viewState: .init(item: TextRoomTimelineItem(id: makeItemIdentifier(),
                                                                         timestamp: .mock,
                                                                         isOutgoing: true,
                                                                         isEditable: false,
                                                                         canBeRepliedTo: true,
                                                                         sender: .init(id: "whoever"),
                                                                         content: .init(body: "A long message that should be on multiple lines."),
                                                                         properties: .init(replyDetails: replyDetails,
                                                                                           isThreaded: isThreaded,
                                                                                           threadSummary: threadSummary)),
                                              groupStyle: .single,
                                              rowContext: .init(isPinned: isPinned)))
        
        AudioRoomTimelineView(timelineItem: .init(id: makeItemIdentifier(),
                                                  timestamp: .mock,
                                                  isOutgoing: true,
                                                  isEditable: false,
                                                  canBeRepliedTo: true,
                                                  sender: .init(id: ""),
                                                  content: .init(filename: "audio.ogg",
                                                                 duration: 100,
                                                                 waveform: EstimatedWaveform.mockWaveform,
                                                                 source: nil,
                                                                 fileSize: nil,
                                                                 contentType: nil),
                                                  properties: .init(replyDetails: replyDetails,
                                                                    isThreaded: isThreaded,
                                                                    threadSummary: threadSummary)))
        
        FileRoomTimelineView(timelineItem: .init(id: makeItemIdentifier(),
                                                 timestamp: .mock,
                                                 isOutgoing: false,
                                                 isEditable: false,
                                                 canBeRepliedTo: true,
                                                 sender: .init(id: ""),
                                                 content: .init(filename: "file.txt",
                                                                caption: "File",
                                                                source: nil,
                                                                fileSize: nil,
                                                                thumbnailSource: nil,
                                                                contentType: nil),
                                                 properties: .init(replyDetails: replyDetails,
                                                                   isThreaded: isThreaded,
                                                                   threadSummary: threadSummary)))
        
        ImageRoomTimelineView(timelineItem: .init(id: makeItemIdentifier(),
                                                  timestamp: .mock,
                                                  isOutgoing: true,
                                                  isEditable: true,
                                                  canBeRepliedTo: true,
                                                  sender: .init(id: ""),
                                                  content: .init(filename: "image.jpg",
                                                                 imageInfo: .mockImage,
                                                                 thumbnailInfo: nil),
                                                  properties: .init(replyDetails: replyDetails,
                                                                    isThreaded: isThreaded,
                                                                    threadSummary: threadSummary)))
        
        LocationRoomTimelineView(timelineItem: .init(id: makeItemIdentifier(),
                                                     timestamp: .mock,
                                                     isOutgoing: false,
                                                     isEditable: false,
                                                     canBeRepliedTo: true,
                                                     sender: .init(id: "Bob"),
                                                     content: .init(body: "Fallback geo uri description",
                                                                    geoURI: .init(latitude: 41.902782,
                                                                                  longitude: 12.496366)),
                                                     properties: .init(replyDetails: replyDetails,
                                                                       isThreaded: isThreaded,
                                                                       threadSummary: threadSummary)))
        
        VoiceMessageRoomTimelineView(timelineItem: .init(id: makeItemIdentifier(),
                                                         timestamp: .mock,
                                                         isOutgoing: true,
                                                         isEditable: false,
                                                         canBeRepliedTo: true,
                                                         sender: .init(id: ""),
                                                         content: .init(filename: "audio.ogg",
                                                                        duration: 100,
                                                                        waveform: EstimatedWaveform.mockWaveform,
                                                                        source: nil,
                                                                        fileSize: nil,
                                                                        contentType: nil),
                                                         properties: .init(replyDetails: replyDetails,
                                                                           isThreaded: isThreaded,
                                                                           threadSummary: threadSummary)),
                                     playerState: AudioPlayerState(id: .timelineItemIdentifier(.randomEvent),
                                                                   title: L10n.commonVoiceMessage,
                                                                   duration: 10,
                                                                   waveform: EstimatedWaveform.mockWaveform))
    }
    
    func makeItemIdentifier() -> TimelineItemIdentifier {
        isPinned ? .event(uniqueID: .init(""), eventOrTransactionID: .eventID("pinned")) : .randomEvent
    }
    
    var replyDetails: TimelineItemReplyDetails? {
        isThreaded ? .loaded(sender: .init(id: "", displayName: "Alice"),
                             eventID: "123",
                             eventContent: .message(.text(.init(body: "Short")))) : nil
    }
}
