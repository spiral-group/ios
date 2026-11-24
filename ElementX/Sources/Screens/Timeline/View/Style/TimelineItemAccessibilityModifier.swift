//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

/// How a timeline item takes part in an active multi-selection, for accessibility purposes.
enum TimelineItemAccessibilityMessageSelection {
    /// No selection is active, the item offers its regular message actions.
    case none
    /// A selection is active, the item acts as a toggle when it can be selected.
    case selecting(isSelected: Bool, selectedCount: Int)
}

private struct TimelineItemAccessibilityModifier: ViewModifier {
    @Environment(\.timelineContext) private var context // AGENT-PLATFORM (question 413)
    
    let timelineItem: RoomTimelineItemProtocol
    let selection: TimelineItemAccessibilityMessageSelection
    let action: () -> Void
    
    private var isSelecting: Bool {
        if case .selecting = selection {
            return true
        }
        return false
    }
    
    func body(content: Content) -> some View {
        switch timelineItem {
        case is PollRoomTimelineItem:
            // The answers stay traversable on their own, unless the whole poll acts as a selection toggle.
            if isSelecting {
                interactions(for: content.accessibilityElement(children: .combine))
            } else {
                interactions(for: content)
            }
        // AGENT-PLATFORM (question 413): an album is one element, read as a photo is: who sent it, what it replies to,
        // how many it holds and its caption; the send info follows. Each of its pictures opens from an action, as each
        // opens from a tap on its tile.
        case let timelineItem as GalleryRoomTimelineItem where !timelineItem.usesListLayout:
            // Combined as a photo is, so that the reply and what the parts offer stay. The tiles are hidden in the view.
            let album = content
                .accessibilityElement(children: .combine)
                .accessibilityLabel { label in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    label
                    Text(timelineItem.albumAccessibilityLabel)
                }
                .accessibilityAddTraits(.isImage)
            if isSelecting {
                interactions(for: album)
            } else {
                interactions(for: album
                    .accessibilityAction { openAlbumItem(0, of: timelineItem) }
                    .accessibilityActions {
                        ForEach(timelineItem.content.items.indices, id: \.self) { index in
                            Button(UntranslatedL10n.a11yAlbumOpenItem(index + 1)) {
                                openAlbumItem(index, of: timelineItem)
                            }
                        }
                    })
            }
        // A gallery is a container so that each of its attachments can be focussed on its own.
        // Everything that isn't an attachment is announced when entering it, as the caption and
        // the send info are hidden where they're shown to avoid being read twice.
        case let timelineItem as GalleryRoomTimelineItem:
            interactions(for: content
                .accessibilityElement(children: isSelecting ? .combine : .contain)
                .accessibilityLabel { _ in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    if let caption = timelineItem.content.caption, !caption.isBlank {
                        Text(caption)
                    }
                    Text(timelineItem.localizedSendInfo)
                })
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
            interactions(for: content
                .accessibilityElement(children: isSelecting ? .combine : .contain)
                .accessibilityLabel { _ in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    Text(UntranslatedL10n.a11ySpiralAppPost(timelineItem.body))
                    Text(timelineItem.localizedSendInfo)
                })
        // AGENT-PLATFORM (decision 371): the whole summary is read, however the card is folded, and a combined row has no
        // button to reach, so the fold is an action of the row.
        case let timelineItem as CallSummaryRoomTimelineItem:
            interactions(for: content
                .accessibilityElement(children: .combine)
                .accessibilityLabel { _ in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    Text(timelineItem.summary.accessibilityText)
                }
                .modifier(CallSummaryFoldAccessibilityAction(timelineItem: timelineItem, isEnabled: !isSelecting)))
        // AGENT-PLATFORM (Brief 0083): the sender is read first through the label, as before. A representation
        // laid the name out above an undrawn copy of the content, whose texts sat about 24 pt below the drawn
        // ones, so the contrast audit measured pixels that weren't theirs (contrast triage, cause I).
        case let timelineItem as EventBasedTimelineItemProtocol:
            interactions(for: content
                .accessibilityElement(children: .combine)
                .accessibilityLabel { label in
                    Text(timelineItem.sender.displayName ?? timelineItem.sender.id)
                    label
                })
        default:
            content
                .accessibilityElement(children: .combine)
        }
    }
    
    private func openAlbumItem(_ index: Int, of timelineItem: GalleryRoomTimelineItem) {
        context?.send(viewAction: .galleryItemTapped(.init(timelineItemID: timelineItem.id, mediaIndex: index)))
    }
    
    /// Offers the message actions, or turns the item into a selection toggle while selecting.
    @ViewBuilder
    private func interactions(for view: some View) -> some View {
        switch selection {
        case .none:
            view
                .accessibilityActions {
                    Button(L10n.commonMessageActions) {
                        action()
                    }
                }
        case .selecting(let isSelected, let selectedCount):
            if let item = timelineItem as? EventBasedTimelineItemProtocol, item.isForwardable {
                view
                    .accessibilityLabel { label in
                        Text(L10n.screenRoomSelectionCount(selectedCount))
                        label
                    }
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction(.default, action)
            } else {
                // Items that can't be selected are inert while selecting.
                view
            }
        }
    }
}

/// AGENT-PLATFORM (decision 371): its own modifier, so that only this row reads what the action needs.
private struct CallSummaryFoldAccessibilityAction: ViewModifier {
    @Environment(\.timelineContext) private var context
    @Environment(\.timelineRowContext.isCallSummaryExpanded) private var isExpanded
    
    let timelineItem: CallSummaryRoomTimelineItem
    let isEnabled: Bool
    
    func body(content: Content) -> some View {
        if isEnabled, timelineItem.summary.isLong {
            content.accessibilityAction(named: Text(CallSummaryCard.foldTitle(isExpanded: isExpanded))) {
                context?.expandedCallSummaries.formSymmetricDifference([timelineItem.id])
            }
        } else {
            content
        }
    }
}

extension View {
    func timelineItemAccessibility(_ timelineItem: RoomTimelineItemProtocol,
                                   selection: TimelineItemAccessibilityMessageSelection = .none,
                                   action: @escaping () -> Void) -> some View {
        modifier(TimelineItemAccessibilityModifier(timelineItem: timelineItem, selection: selection, action: action))
    }
}

extension GalleryRoomTimelineItem {
    /// How many it holds and its caption. The sender and the reply are read before it, the send info after it.
    var albumAccessibilityLabel: String {
        var parts = [UntranslatedL10n.a11yAlbumItems(content.items.count)]
        if let caption = content.caption, !caption.isBlank {
            parts.append(caption)
        }
        return parts.joined(separator: ", ")
    }
}
