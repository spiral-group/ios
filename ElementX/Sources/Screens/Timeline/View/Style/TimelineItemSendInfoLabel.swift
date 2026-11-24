//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

// AGENT-PLATFORM (Brief 0083, question 357): the time and the ticks sit in the bubble's bottom corner, on every message.
// This reverses the line under the bubble of the room's timeline batch (336).

extension View {
    /// Adds the send info (timestamp along indicators for edits, delivery and encryption issues) to this view.
    func timelineItemSendInfo(_ sendInfo: TimelineItemSendInfo) -> some View {
        modifier(TimelineItemSendInfoModifier(sendInfo: sendInfo))
    }
}

/// Adds the send info to a view with the correct layout.
private struct TimelineItemSendInfoModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.timelineContext) private var context
    
    let sendInfo: TimelineItemSendInfo
    
    var layout: AnyLayout {
        switch sendInfo.layoutType {
        // AGENT-PLATFORM (Brief 0083, question 357): at accessibility sizes the time would squeeze a file's name or a
        // voice message's controls to a letter per line, so it goes under them.
        case .horizontal where dynamicTypeSize.isAccessibilitySize:
            AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))
        case .horizontal(let spacing):
            AnyLayout(HStackLayout(alignment: .bottom, spacing: spacing))
        case .vertical(let spacing):
            AnyLayout(GridLayout(alignment: .leading, verticalSpacing: spacing))
        case .below:
            AnyLayout(VStackLayout(alignment: .trailing, spacing: 0))
        case .overlay, .hidden:
            AnyLayout(ZStackLayout(alignment: .bottomTrailing))
        }
    }
    
    func body(content: Content) -> some View {
        layout {
            content
            
            TimelineItemSendInfoLabel(sendInfo: sendInfo)
                .accessibilityHidden(sendInfo.isAccessibilityHidden)
                // The label is small and the bubble's text is the only thing around it, so a status reaches further.
                .contentShape(.interaction, Rectangle().inset(by: sendInfo.isTappable ? -14 : 0))
                // Only tappable labels get the identifier, plain timestamps would be ambiguous matches.
                .accessibilityIdentifier(sendInfo.isTappable ? A11yIdentifiers.roomScreen.sendInfo : "")
                // Tap gesture to avoid the message being detected as a button by VoiceOver
                // (and the action shows a description that is already read to the user).
                .onTapGesture {
                    guard sendInfo.isTappable else { return }
                    context?.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
                }
        }
    }
}

/// "Sending failed" under a failed send's bubble, in the time's old place. Tapping it offers the retry.
struct TimelineItemSendFailureLabel: View {
    @Environment(\.timelineContext) private var context
    
    let sendInfo: TimelineItemSendInfo
    
    var body: some View {
        Text(L10n.commonSendingFailed)
            .font(.compound.bodyXS)
            .foregroundStyle(.compound.textCriticalPrimary)
            .chatBackgroundChip() // AGENT-PLATFORM (Brief 0083, question 357)
            .accessibilityHidden(sendInfo.isAccessibilityHidden)
            // AGENT-PLATFORM (Brief 0083): a 44 pt target in the layout, extending down into its own room, so it takes
            // no tap from the reactions or the thread above it, nor reaches out of its cell.
            .frame(minHeight: 44, alignment: .top)
            .contentShape(.rect)
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.sendInfo)
            // Tap gesture to avoid the message being detected as a button by VoiceOver
            // (and the action shows a description that is already read to the user).
            .onTapGesture {
                context?.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
            }
    }
}

// AGENT-PLATFORM (Brief 0083): a failed send's red disc beside the own bubble, as Messages draws it: a 22 pt glyph in
// a 44 pt square of the layout, the whole square its target. The same action as the send info's: the retry and discard
// choice.
struct TimelineItemSendFailureMark: View {
    @Environment(\.timelineContext) private var context
    
    let sendInfo: TimelineItemSendInfo
    
    var body: some View {
        CompoundIcon(\.errorSolid, size: .custom(22), relativeTo: .compound.bodyLG)
            .foregroundStyle(.compound.iconCriticalPrimary)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .onTapGesture {
                context?.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.commonSendingFailed)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                context?.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.sendInfo)
    }
}

/// The label shown for a timeline item with info about it's timestamp and various other indicators.
private struct TimelineItemSendInfoLabel: View {
    @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
    
    let sendInfo: TimelineItemSendInfo
    
    var body: some View {
        switch sendInfo.layoutType {
        case .overlay(capsuleStyle: true):
            capsule(content)
        // AGENT-PLATFORM (Brief 0083): in from the side, level with the text: the bubble's corner is round.
        case .horizontal, .overlay(capsuleStyle: false):
            content
                .padding(.trailing, 4 + sendInfo.edgeInset)
                .padding(.bottom, -4 + sendInfo.edgeInset)
        case .vertical:
            GridRow {
                content
                    .padding(.trailing, sendInfo.edgeInset)
                    .padding(.bottom, sendInfo.edgeInset)
                    .gridColumnAlignment(.trailing)
            }
        case .below:
            // A strip the width of the post: the time at its end. Overlaid, as on a photo, it covered whatever the post
            // drew in its corner (§ 5.60), and a mask here squares the post's top corners on iOS 27 (343).
            content
                .padding(.horizontal, 12)
                .padding(.top, 3)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .hidden:
            // AGENT-PLATFORM (Brief 0083, question 359): a running live share has no time, and can still be pinned.
            if sendInfo.isPinned {
                capsule(pinMark.foregroundStyle(plainStyle))
            }
        }
    }
    
    private func capsule(_ content: some View) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.compound.bgSubtleSecondary, in: .capsule)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
    }
    
    private var pinMark: some View {
        CompoundIcon(\.pinSolid, size: .custom(TimelineItemSendInfo.pinSize), relativeTo: .compound.bodyXS)
            .accessibilityLabel(L10n.commonPinned)
    }
    
    var content: some View {
        HStack(spacing: 4) {
            // AGENT-PLATFORM (Brief 0083, question 359): a pinned message says so beside its time, inside the bubble.
            if sendInfo.isPinned {
                pinMark
            }
            
            Text(sendInfo.localizedString)
            
            if !sendInfo.showsFailureMark, let statusIcon = sendInfo.statusIcon {
                statusIconView(statusIcon) // AGENT-PLATFORM (Brief 0083)
                    .accessibilityLabel(sendInfo.statusAccessibilityLabel ?? "")
                    .accessibilityHidden(sendInfo.statusAccessibilityLabel == nil)
            }
            
            // AGENT-PLATFORM (Brief 0083, question 357): the ticks, in the colour of a time with nothing to report.
            if let deliveryStatus = sendInfo.deliveryStatus {
                TimelineDeliveryStatusView(deliveryStatus: deliveryStatus)
                    .foregroundStyle(plainStyle)
            }
        }
        .font(.compound.bodyXS)
        .foregroundStyle(plainStyle) // AGENT-PLATFORM (Brief 0083)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 300a, question 357): the own bubble's ink, as grey and red fall under 4.5:1 on
    // the blue. `textSecondary` reads 4.69:1 on the incoming grey and on a capsule over media, which has its own background.
    private var plainStyle: Color {
        ink?.secondaryText ?? .compound.textSecondary
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 300a, question 357): a red authenticity warning stays in its mark. In the bubble
    // the red time fell under 4.5:1 on the grey in dark, so the time keeps the plain colour. On an own blue bubble the
    // mark keeps its red on a white disc: red on the fill reads 1.2:1; on white, 5.67:1 in light and 3.49:1 in dark.
    @ViewBuilder
    private func statusIconView(_ icon: KeyPath<CompoundIcons, Image>) -> some View {
        if sendInfo.status?.isCritical == true {
            CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodyXS)
                .foregroundStyle(.compound.iconCriticalPrimary)
                .background(ink?.criticalMarkDisc ?? .clear, in: .circle)
        } else {
            CompoundIcon(icon, size: .xSmall, relativeTo: .compound.bodyXS)
        }
    }
    
    /// A capsule has its own background.
    private var ink: OwnBubbleInk? {
        isCapsule ? nil : ownBubbleInk
    }
    
    private var isCapsule: Bool {
        sendInfo.layoutType == .overlay(capsuleStyle: true) || sendInfo.layoutType == .hidden
    }
}

extension EnvironmentValues {
    /// Tells a bubble's text to leave room for the pin beside the time.
    @Entry var isTimelineItemPinned = false
}

/// All the data needed to render a timeline item's send info label.
struct TimelineItemSendInfo {
    enum Status {
        case sendingFailed
        case encryptionAuthenticity(EncryptionAuthenticity)
        case encryptionForwarder(TimelineItemKeyForwarder)
        
        // AGENT-PLATFORM (Brief 0083): the statuses drawn in red.
        var isCritical: Bool {
            switch self {
            case .sendingFailed: true
            case .encryptionAuthenticity(let authenticity): authenticity.color == .red
            case .encryptionForwarder: false
            }
        }
    }
    
    /// Describes how the content and the send info should be arranged inside a bubble
    enum LayoutType: Equatable {
        case horizontal(spacing: CGFloat = 4)
        case vertical(spacing: CGFloat = 4)
        case overlay(capsuleStyle: Bool)
        // AGENT-PLATFORM (§ 5.60): under the content, in a full-width strip.
        case below
        case hidden
    }
    
    let itemID: TimelineItemIdentifier
    let localizedString: String
    var status: Status?
    let layoutType: LayoutType
    /// What's drawn beside the time of an own message.
    var deliveryStatus: TimelineDeliveryStatusView.Status?
    var isOutgoing = false
    /// The message's own accessibility label reads the send info, so the label in the bubble is hidden.
    var isReadWithMessage = false
    /// A gallery announces the time when entering it, and a message that reads it has it already.
    var isAccessibilityHidden = false
    var isGallery = false
    /// In from the bubble's edge when the bubble itself has no inset, around a picture that reaches its edges.
    var edgeInset: CGFloat = 0
    /// Draws the pin beside the time.
    var isPinned = false
    
    /// Smaller than the time's other marks: the pin is a note, not a status.
    static let pinSize: CGFloat = 12
    
    /// The room the pin takes beside the time, with the same metrics as the time's other marks.
    static var pinSlotWidth: CGFloat {
        UIFontMetrics(forTextStyle: .caption1).scaledValue(for: pinSize) + 4
    }
    
    /// A failed send: its mark is drawn beside the bubble.
    var showsFailureMark: Bool {
        guard layoutType != .hidden, case .sendingFailed = status else { return false }
        return true
    }
    
    /// Whether tapping the label explains a status. A failed send's mark and label do that.
    var isTappable: Bool {
        status != nil && !showsFailureMark
    }
    
    var statusIcon: KeyPath<CompoundIcons, Image>? {
        switch status {
        case .sendingFailed: \.errorSolid
        case .encryptionAuthenticity(let authenticity): authenticity.icon
        case .encryptionForwarder: \.info
        case .none: nil
        }
    }
    
    var statusAccessibilityLabel: String? {
        switch status {
        case .sendingFailed: L10n.commonSendingFailed
        case .encryptionAuthenticity(let authenticity): authenticity.message
        case .encryptionForwarder(let forwarder): forwarder.message
        case .none: nil
        }
    }
}

extension TimelineItemSendInfo {
    init(timelineItem: EventBasedTimelineItemProtocol,
         adjustedDeliveryStatus: TimelineItemDeliveryStatus?,
         hasContentScanningFailure: Bool = false,
         deliveryStatus: TimelineDeliveryStatusView.Status?) {
        itemID = timelineItem.id
        localizedString = timelineItem.localizedSendInfo
        self.deliveryStatus = deliveryStatus
        isOutgoing = timelineItem.isOutgoing
        
        status = if case .sendingFailed = adjustedDeliveryStatus {
            .sendingFailed
        } else if let authenticity = timelineItem.properties.encryptionAuthenticity {
            .encryptionAuthenticity(authenticity)
        } else if let forwarder = timelineItem.properties.encryptionForwarder {
            .encryptionForwarder(forwarder)
        } else {
            nil
        }
        
        layoutType = if hasContentScanningFailure {
            // The content scanner failure placeholder replaces the media,
            // so the send info is laid out like it is for a text message.
            timelineItem.hasMediaCaption ? .overlay(capsuleStyle: false) : .horizontal()
        } else {
            switch timelineItem {
            // AGENT-PLATFORM (decision 371): under the card's text, as on a notice's card.
            case is CallSummaryRoomTimelineItem:
                .vertical(spacing: 2)
            case is TextBasedRoomTimelineItem:
                .overlay(capsuleStyle: false)
            case let liveLocationTimelineItem as LiveLocationRoomTimelineItem:
                liveLocationTimelineItem.layout
            case let message as EventBasedMessageTimelineItemProtocol:
                switch message {
                case is ImageRoomTimelineItem, is VideoRoomTimelineItem:
                    .overlay(capsuleStyle: !message.hasMediaCaption)
                // AGENT-PLATFORM (question 413): an album's time sits on it in a chip, as a photo's does. A list of files
                // has it below the list.
                case let gallery as GalleryRoomTimelineItem:
                    if message.hasMediaCaption {
                        .overlay(capsuleStyle: false)
                    } else {
                        gallery.usesListLayout ? .vertical() : .overlay(capsuleStyle: true)
                    }
                case is AudioRoomTimelineItem, is FileRoomTimelineItem:
                    // swiftlint:disable:next void_function_in_ternary
                    message.hasMediaCaption ? .overlay(capsuleStyle: false) : .horizontal(spacing: 0) // No spacing as the content already contains it.
                case let locationTimelineItem as LocationRoomTimelineItem:
                    .overlay(capsuleStyle: locationTimelineItem.content.geoURI != nil)
                default:
                    .horizontal()
                }
            case is StickerRoomTimelineItem:
                .overlay(capsuleStyle: true)
            // AGENT-PLATFORM (§ 5.60): under the post, not over it, where a capsule covered what the post drew in its
            // corner and the end of a draft's Publish button. The generating card stands where the draft will (§ 5.71).
            case is InteractivePostRoomTimelineItem, is InteractiveDraftRoomTimelineItem, is InteractiveGeneratingRoomTimelineItem:
                .below
            case is PollRoomTimelineItem:
                .vertical(spacing: 16)
            default:
                .horizontal()
            }
        }
        
        isGallery = timelineItem is GalleryRoomTimelineItem
        // AGENT-PLATFORM (question 413): an album is one element, as a photo is, so it reads its send info as a photo does.
        let isAlbum = (timelineItem as? GalleryRoomTimelineItem)?.usesListLayout == false
        // A poll's answers stay their own elements, so its send info does too, and so does a running post's.
        isReadWithMessage = layoutType != .hidden && !(timelineItem is PollRoomTimelineItem) && (!isGallery || isAlbum) &&
            !(timelineItem is InteractivePostRoomTimelineItem) // AGENT-PLATFORM (Brief 0083)
        isAccessibilityHidden = isReadWithMessage || isGallery
    }
}

private extension LiveLocationRoomTimelineItem {
    var layout: TimelineItemSendInfo.LayoutType {
        if content.isLive, isOutgoing {
            .hidden
        } else {
            .overlay(capsuleStyle: true)
        }
    }
}

private extension TimelineItemKeyForwarder {
    static var test: TimelineItemKeyForwarder {
        TimelineItemKeyForwarder(id: "@alice:matrix.org", displayName: "alice")
    }
}

// MARK: - Previews

struct TimelineItemSendInfoLabel_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 16) {
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      layoutType: .horizontal(),
                                                      deliveryStatus: .sending))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      layoutType: .horizontal(),
                                                      deliveryStatus: .sent))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      layoutType: .horizontal(),
                                                      deliveryStatus: .read))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.unsignedDevice(color: .red)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.notGuaranteed(color: .gray)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionAuthenticity(.sentInClear(color: .red)),
                                                      layoutType: .horizontal()))
            TimelineItemSendInfoLabel(sendInfo: .init(itemID: .randomEvent,
                                                      localizedString: "09:47 AM",
                                                      status: .encryptionForwarder(.test),
                                                      layoutType: .horizontal()))
        }
    }
}
