//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import Synchronization
import UIKit

nonisolated protocol EventBasedTimelineItemProtocol: RoomTimelineItemProtocol, CustomStringConvertible {
    var timestamp: Date { get }
    var isOutgoing: Bool { get }
    var isEditable: Bool { get }
    var canBeRepliedTo: Bool { get }
    
    var sender: TimelineItemSender { get }
    
    var body: String { get }
    
    var properties: RoomTimelineItemProperties { get }
}

nonisolated extension EventBasedTimelineItemProtocol {
    var description: String {
        "\(String(describing: Self.self)): id: \(id), timestamp: \(timestamp), isOutgoing: \(isOutgoing), properties: \(properties)"
    }
    
    var isForwardable: Bool {
        isRemoteMessage
            && !isRedacted
            && !hasFailedDecryption
            && !(self is StateRoomTimelineItem)
            && !(self is UnsupportedRoomTimelineItem)
            && !(self is PollRoomTimelineItem)
            && !(self is LiveLocationRoomTimelineItem)
            && !(self is StickerRoomTimelineItem) // The SDK can only forward m.room.message content and stickers are m.sticker events.
    }
    
    var isRemoteMessage: Bool {
        id.eventID != nil
    }
    
    var isRedacted: Bool {
        self is RedactedRoomTimelineItem
    }
    
    var pollIfAvailable: Poll? {
        (self as? PollRoomTimelineItem)?.poll
    }
    
    var hasFailedToSend: Bool {
        properties.deliveryStatus?.isSendingFailed == true
    }
    
    var hasFailedDecryption: Bool {
        self is EncryptedRoomTimelineItem
    }
    
    var timelineMenuDescription: String {
        switch self {
        case is VoiceMessageRoomTimelineItem:
            return L10n.commonVoiceMessage
        default:
            return body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// The inline area to reserve at the trailing edge of the message text so the
    /// bubble's natural size accommodates the timestamp (which is overlaid on the
    /// bubble's bottom-trailing corner). Text wraps around this area: if it fits on
    /// the last line, the timestamp tucks inline; otherwise it sits on a new line.
    /// Sized using the same dynamic-type-aware font as the rendered timestamp.
    var trailingReservedSize: CGSize {
        let textStyle: UIFont.TextStyle = .caption1 // matches compound.bodyXS
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        let hasIcon = properties.encryptionAuthenticity != nil || properties.encryptionForwarder != nil
        // AGENT-PLATFORM (Brief 0083, question 357): the ticks' slot, the same width for one tick as for two, so a
        // message doesn't reflow when it's read. A failed send has its mark beside the bubble instead.
        let hasTicks = isOutgoing && !hasFailedToSend
        
        // AGENT-PLATFORM (Brief 0083, question 359): the same for every row of that time, and measuring text isn't cheap.
        return TrailingReservedSizes.size(for: .init(sendInfo: localizedSendInfo, pointSize: font.pointSize, hasIcon: hasIcon, hasTicks: hasTicks)) {
            let metrics = UIFontMetrics(forTextStyle: textStyle)
            let textSize = (localizedSendInfo as NSString).size(withAttributes: [.font: font])
            var width = textSize.width
            var height = textSize.height
            if hasIcon {
                // CompoundIcon at .xSmall is 16pt at the base size; scale with the same UIFontMetrics
                // as the icon's `relativeTo: .compound.bodyXS` modifier, plus the 4pt HStack spacing.
                let iconSize = metrics.scaledValue(for: 16)
                width += iconSize + 4
                height = max(height, iconSize)
            }
            if hasTicks {
                width += metrics.scaledValue(for: TimelineDeliveryStatusView.slotWidth) + 4
            }
            // Small visual gap between the text content and the overlaid timestamp.
            width += 4
            return CGSize(width: ceil(width), height: ceil(height))
        }
    }
    
    /// contains the timestamp and an optional edited localised prefix
    /// example: (edited) 12:17 PM
    var localizedSendInfo: String {
        var start = ""
        if properties.isEdited {
            start = "\(L10n.commonEditedSuffix) "
        }
        return start + timestamp.formattedTime()
    }
    
    var isCopyable: Bool {
        guard let messageBasedItem = self as? EventBasedMessageTimelineItemProtocol else {
            return false
        }
        
        switch messageBasedItem.contentType {
        case .audio, .file, .image, .video, .location, .voice, .gallery:
            return false
        case .text, .emote, .notice:
            return true
        }
    }
    
    var supportsMediaCaption: Bool {
        guard let messageBasedItem = self as? EventBasedMessageTimelineItemProtocol else { return false }
        return messageBasedItem.supportsMediaCaption
    }
    
    var hasMediaCaption: Bool {
        guard let messageBasedItem = self as? EventBasedMessageTimelineItemProtocol else { return false }
        return messageBasedItem.hasMediaCaption
    }
}

/// AGENT-PLATFORM (Brief 0083, question 359): keyed by all a reserved size hangs on, the text size included, through the font.
nonisolated enum TrailingReservedSizes {
    struct Key: Hashable {
        let sendInfo: String
        let pointSize: CGFloat
        let hasIcon: Bool
        let hasTicks: Bool
    }
    
    private static let limit = 2000
    private static let sizes = Mutex<[Key: CGSize]>([:])
    
    static func purge() {
        sizes.withLock { $0.removeAll() }
    }
    
    static func size(for key: Key, measure: () -> CGSize) -> CGSize {
        if let size = sizes.withLock({ $0[key] }) {
            return size
        }
        
        let size = measure()
        sizes.withLock { sizes in
            if sizes.count >= limit {
                sizes.removeAll()
            }
            sizes[key] = size
        }
        return size
    }
}
