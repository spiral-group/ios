//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

nonisolated struct CallNotificationRoomTimelineItem: RoomTimelineItemProtocol, Equatable {
    let id: TimelineItemIdentifier
    let timestamp: Date
    let sender: TimelineItemSender
    let isDM: Bool
    let isVoiceCall: Bool
    
    /// Represents the state of the call notification - either tombstoned (ended) or active (ongoing)
    enum CallState: Equatable {
        /// A tombstoned/ended call notification
        case tombstoned(outcome: TombstonedOutcome)
        /// An active/ongoing call notification
        case active(activeMembers: [String],
                    isJoined: Bool,
                    callStartTimestamp: Date?)
    }

    // AGENT-PLATFORM (Brief 0063 G11/G12; decisions 171/172): how an ended
    // call resolved, from the SDK's `RtcCallOutcome` and MSC4310 declines.
    // Missed and cancelled are DM rings only; a group call has no direction.
    enum TombstonedOutcome: Equatable {
        /// An MSC4310 decline references the ring (in a group, only when
        /// nobody else joined).
        case declined(byMe: Bool)
        /// DM: someone else's ring that I never answered.
        case missed
        /// DM: my own ring that nobody answered, timed out or cancelled.
        case cancelled
        /// DM: the call was answered and has ended; `duration` from the
        /// answer to the end, when both are known.
        case answered(duration: TimeInterval?)
        /// Group: someone other than the starter joined; `duration` from
        /// that first join to the end, when both are known.
        case groupCall(duration: TimeInterval?, ownUserJoined: Bool)
        /// Not enough data to classify (a non-ring DM notification, a group
        /// call nobody else joined) — the plain "Call ended" tile.
        case unclassified
    }

    let callState: CallState
    /// G12 — whether WE rang: incoming and outgoing ended tiles differ.
    var isOutgoing = false

    var properties = RoomTimelineItemProperties()
}

// AGENT-PLATFORM (calls-in-app walk F7; decisions 171/172): an ended tile's
// words live on the model so fixtures can check them. A tombstoned call has
// ended, so the fallback reads "Call ended"; upstream's "Call started" read as
// a call still running after everyone had left.
nonisolated extension CallNotificationRoomTimelineItem {
    func tombstoneTitle(for outcome: TombstonedOutcome) -> String {
        switch outcome {
        case .declined(let byMe):
            // As per design only have declined variants in DM
            isDM
                ? (byMe ? L10n.commonCallYouDeclined : L10n.commonCallDeclined)
                : UntranslatedL10n.screenNativeCallTileEnded
        case .missed:
            UntranslatedL10n.screenNativeCallTileMissed
        case .cancelled:
            UntranslatedL10n.screenNativeCallTileCancelled
        case .answered:
            isOutgoing
                ? UntranslatedL10n.screenNativeCallTileOutgoing
                : UntranslatedL10n.screenNativeCallTileIncoming
        case .groupCall:
            UntranslatedL10n.screenNativeCallTileGroup
        case .unclassified:
            UntranslatedL10n.screenNativeCallTileEnded
        }
    }

    func tombstoneSubtitle(for outcome: TombstonedOutcome) -> String? {
        switch outcome {
        case .missed:
            return UntranslatedL10n.screenNativeCallTileCallBack
        case .answered(let duration):
            return duration.flatMap(Self.formattedLength)
        case .groupCall(let duration, let ownUserJoined):
            let parts = [duration.flatMap(Self.formattedLength),
                         ownUserJoined ? nil : UntranslatedL10n.screenNativeCallTileNotJoined].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .declined, .cancelled, .unclassified:
            return nil
        }
    }

    private static func formattedLength(_ duration: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }
}
