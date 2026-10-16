//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

private struct TimelineItemAccessibilityModifier: ViewModifier {
    let timelineItem: RoomTimelineItemProtocol
    let action: () -> Void
    
    func body(content: Content) -> some View {
        switch timelineItem {
        case is PollRoomTimelineItem:
            content
                .accessibilityActions {
                    Button(L10n.commonMessageActions) {
                        action()
                    }
                }
        // A gallery is a container so that each of its attachments can be focussed on its own.
        // Everything that isn't an attachment is announced when entering it, as the caption and
        // the send info are hidden where they're shown to avoid being read twice.
        case let timelineItem as GalleryRoomTimelineItem:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel { _ in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    if let caption = timelineItem.content.caption, !caption.isBlank {
                        Text(caption)
                    }
                    Text(timelineItem.localizedSendInfo)
                }
                .accessibilityActions {
                    Button(L10n.commonMessageActions) {
                        action()
                    }
                }
        // AGENT-PLATFORM (Brief 0066, ADR-0007): a running app is a set of
        // controls, so the row is a container and they stay reachable one at a
        // time — the same shape as a gallery above, and as a poll's options.
        //
        // The case below replaces the whole subtree with a representation, and
        // an Interactive Post took it for months: every button an app drew was
        // collapsed into the post's own title, leaving a VoiceOver reader a row
        // they could hear and not use. That was blamed on WebKit in the
        // notebook. It was this.
        //
        // The label is what the post IS, announced on entering. What it
        // currently SAYS is the app's own content, and is read by navigating
        // into it.
        case let timelineItem as InteractivePostRoomTimelineItem:
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel { _ in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    Text(UntranslatedL10n.a11ySpiralAppPost(timelineItem.body))
                    Text(timelineItem.localizedSendInfo)
                }
                .accessibilityActions {
                    Button(L10n.commonMessageActions) {
                        action()
                    }
                }
        case let timelineItem as EventBasedTimelineItemProtocol:
            content
                .accessibilityRepresentation {
                    VStack(spacing: 8) {
                        Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                        content
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    Button(L10n.commonMessageActions) {
                        action()
                    }
                }
        default:
            content
                .accessibilityElement(children: .combine)
        }
    }
}

extension View {
    func timelineItemAccessibility(_ timelineItem: RoomTimelineItemProtocol, action: @escaping () -> Void) -> some View {
        modifier(TimelineItemAccessibilityModifier(timelineItem: timelineItem, action: action))
    }
}
