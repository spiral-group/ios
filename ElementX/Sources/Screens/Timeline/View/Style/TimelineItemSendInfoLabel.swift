//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

extension View {
    /// Adds the send info (timestamp along indicators for edits and delivery/encryption issues) for the given timeline item to this view.
    func timelineItemSendInfo(timelineItem: EventBasedTimelineItemProtocol,
                              adjustedDeliveryStatus: TimelineItemDeliveryStatus?,
                              hasContentScanningFailure: Bool = false,
                              context: TimelineViewModel.Context) -> some View {
        modifier(TimelineItemSendInfoModifier(sendInfo: .init(timelineItem: timelineItem,
                                                              adjustedDeliveryStatus: adjustedDeliveryStatus,
                                                              hasContentScanningFailure: hasContentScanningFailure),
                                              // A gallery announces this when entering it instead.
                                              isAccessibilityHidden: timelineItem is GalleryRoomTimelineItem,
                                              context: context))
    }
}

/// Adds the send info to a view with the correct layout.
private struct TimelineItemSendInfoModifier: ViewModifier {
    let sendInfo: TimelineItemSendInfo
    let isAccessibilityHidden: Bool
    let context: TimelineViewModel.Context
    
    var layout: AnyLayout {
        switch sendInfo.layoutType {
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
            if case .below = sendInfo.layoutType {
                // The strip is inside the bubble, so the bubble's rounding
                // (16, `bubbleBackground`) lands on the strip's corners and
                // left the post above it square at the bottom (§ 5.60). The
                // post keeps its own corners, as a photo does.
                content
                    .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
            } else {
                content
            }
            
            TimelineItemSendInfoLabel(sendInfo: sendInfo)
                .accessibilityHidden(isAccessibilityHidden)
                .contentShape(.rect)
                // Tap gesture to avoid the message being detected as a button by VoiceOver
                // (and the action shows a description that is already read to the user).
                .onTapGesture {
                    guard sendInfo.status != nil else { return }
                    context.send(viewAction: .itemSendInfoTapped(itemID: sendInfo.itemID))
                }
        }
    }
}

/// The label shown for a timeline item with info about it's timestamp and various other indicators.
private struct TimelineItemSendInfoLabel: View {
    let sendInfo: TimelineItemSendInfo
    
    var statusIcon: KeyPath<CompoundIcons, Image>? {
        switch sendInfo.status {
        case .sendingFailed: \.errorSolid
        case .encryptionAuthenticity(let authenticity): authenticity.icon
        case .encryptionForwarder: \.info
        case .none: nil
        }
    }
    
    var statusIconAccessibilityLabel: String? {
        switch sendInfo.status {
        case .sendingFailed: L10n.commonSendingFailed
        case .encryptionAuthenticity(let authenticity): authenticity.message
        case .encryptionForwarder(let forwarder): forwarder.message
        case .none: nil
        }
    }
    
    var body: some View {
        switch sendInfo.layoutType {
        case .overlay(capsuleStyle: true):
            content
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.compound.bgSubtleSecondary)
                .cornerRadius(10)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
        case .horizontal, .overlay(capsuleStyle: false):
            content
                .padding(.bottom, -4)
        case .vertical:
            GridRow {
                content
                    .gridColumnAlignment(.trailing)
            }
        case .below:
            // A strip the width of the post: the time at its end, and the
            // whole strip a place to long-press — the post above it is a web
            // view that takes every touch (§ 5.60).
            content
                .padding(.horizontal, 8)
                .padding(.top, 3)
                .padding(.bottom, 5)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .hidden:
            EmptyView()
        }
    }
    
    var content: some View {
        HStack(spacing: 4) {
            Text(sendInfo.localizedString)
            
            if let statusIcon {
                CompoundIcon(statusIcon, size: .xSmall, relativeTo: .compound.bodyXS)
                    .accessibilityLabel(statusIconAccessibilityLabel ?? "")
                    .accessibilityHidden(statusIconAccessibilityLabel == nil)
            }
        }
        .font(.compound.bodyXS)
        .foregroundStyle(sendInfo.foregroundStyle)
    }
}

/// All the data needed to render a timeline item's send info label.
private struct TimelineItemSendInfo {
    enum Status {
        case sendingFailed
        case encryptionAuthenticity(EncryptionAuthenticity)
        case encryptionForwarder(TimelineItemKeyForwarder)
    }
    
    /// Describes how the content and the send info should be arranged inside a bubble
    enum LayoutType {
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
    
    var foregroundStyle: Color {
        switch status {
        case .sendingFailed:
            .compound.textCriticalPrimary
        case .encryptionAuthenticity(let authenticity):
            authenticity.foregroundStyle
        case .encryptionForwarder:
            .compound.textSecondary
        case .none:
            .compound.textSecondary
        }
    }
}

private extension TimelineItemSendInfo {
    init(timelineItem: EventBasedTimelineItemProtocol,
         adjustedDeliveryStatus: TimelineItemDeliveryStatus?,
         hasContentScanningFailure: Bool = false) {
        itemID = timelineItem.id
        localizedString = timelineItem.localizedSendInfo
        
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
            case is TextBasedRoomTimelineItem:
                .overlay(capsuleStyle: false)
            case let liveLocationTimelineItem as LiveLocationRoomTimelineItem:
                liveLocationTimelineItem.layout
            case let message as EventBasedMessageTimelineItemProtocol:
                switch message {
                case is ImageRoomTimelineItem, is VideoRoomTimelineItem:
                    .overlay(capsuleStyle: !message.hasMediaCaption)
                case is GalleryRoomTimelineItem:
                    // Without a caption, append the send info below the grid rather than overlaying
                    // a capsule on top of the media.
                    message.hasMediaCaption ? .overlay(capsuleStyle: false) : .vertical()
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
            // AGENT-PLATFORM (§ 5.60): UNDER the app, not over it. Overlaid, as
            // on a photo, the capsule covered whatever the post drew in its
            // bottom-right corner — a card's last avatar, the end of a line —
            // and the web view took every long press on the post, so the menu
            // («Change», «Forward») opened only from that capsule. Below, the
            // time covers nothing, and the strip it sits in is a place to
            // long-press. Beside the post it would still reshape it.
            case is InteractivePostRoomTimelineItem:
                .below
            case is PollRoomTimelineItem:
                .vertical(spacing: 16)
            // A draft is drawn as a post, and its capsule covered the end of
            // the Publish button: under it too.
            case is InteractiveDraftRoomTimelineItem:
                .below
            // The generating card stands where the draft will (§ 5.71): the
            // same strip under it, else the time widened the square and sat on
            // the band.
            case is InteractiveGeneratingRoomTimelineItem:
                .below
            default:
                .horizontal()
            }
        }
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

private extension EncryptionAuthenticity {
    var foregroundStyle: SwiftUI.Color {
        switch color {
        case .red: .compound.textCriticalPrimary
        case .gray: .compound.textSecondary
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
                                                      status: .sendingFailed,
                                                      layoutType: .horizontal()))
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
