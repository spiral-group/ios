//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Foundation
import SwiftUI

struct CallNotificationRoomTimelineView: View {
    @Environment(\.timelineContext) private var context

    let timelineItem: CallNotificationRoomTimelineItem
    
    var body: some View {
        switch timelineItem.callState {
        case .tombstoned(let outcome):
            tombstonedCallView(outcome: outcome)
        case .active(let activeMembers, let isJoined, let callStartTimestamp):
            ActiveCallTimelineItemView(isDM: timelineItem.isDM,
                                       isVoiceCall: timelineItem.isVoiceCall,
                                       activeMembers: activeMembers,
                                       sender: timelineItem.sender,
                                       isOutgoing: timelineItem.isOutgoing,
                                       isJoined: isJoined,
                                       callStartTimestamp: callStartTimestamp)
        }
    }
    
    // MARK: - Tombstoned Call View

    // AGENT-PLATFORM (Brief 0063, G11/G12 — `17 · Call tiles in chat`):
    // ended calls carry their outcome. Only a missed DM ring reads critical
    // and taps straight into a call back; the caller's own cancelled ring is
    // grey (decision 172). The length and direction replace the
    // clock-time-only tile the design review flagged.
    //
    // AGENT-PLATFORM (Brief 0083, question 359): a bubble on the side of whoever called.
    private func tombstonedCallView(outcome: CallNotificationRoomTimelineItem.TombstonedOutcome) -> some View {
        TimelineCallBubble(sender: timelineItem.sender,
                           isDM: timelineItem.isDM,
                           isOutgoing: timelineItem.isOutgoing,
                           isMissed: outcome == .missed,
                           icon: iconKeyPath(outcome: outcome),
                           title: tileTitle(outcome: outcome)) {
            if let subtitle = tileSubtitle(outcome: outcome) {
                Text(subtitle)
            }
            
            Text(timelineItem.timestamp.formattedTime())
        } accessory: {
            EmptyView()
        }
        // The call-back affordance: a missed tile IS the redial button.
        .onTapGesture {
            guard outcome == .missed else { return }
            context?.send(viewAction: .joinActiveCall(isVoiceCall: timelineItem.isVoiceCall))
        }
    }
    
    // MARK: - Private
    
    private func tileTitle(outcome: CallNotificationRoomTimelineItem.TombstonedOutcome) -> String {
        timelineItem.tombstoneTitle(for: outcome) // AGENT-PLATFORM (walk F7)
    }

    private func tileSubtitle(outcome: CallNotificationRoomTimelineItem.TombstonedOutcome) -> String? {
        timelineItem.tombstoneSubtitle(for: outcome)
    }
    
    private func iconKeyPath(outcome: CallNotificationRoomTimelineItem.TombstonedOutcome) -> KeyPath<CompoundIcons, Image> {
        switch outcome {
        case .declined(let byMe) where timelineItem.isDM || byMe:
            // As per design only have declined variants in DM
            timelineItem.isVoiceCall ? \.voiceCallDeclinedSolid : \.videoCallDeclinedSolid
        case .missed:
            timelineItem.isVoiceCall ? \.voiceCallMissedSolid : \.videoCallMissedSolid
        case .cancelled:
            timelineItem.isVoiceCall ? \.voiceCallOutgoingSolid : \.videoCallOutgoingSolid
        case .answered where timelineItem.isOutgoing:
            timelineItem.isVoiceCall ? \.voiceCallOutgoingSolid : \.videoCallOutgoingSolid
        default:
            timelineItem.isVoiceCall ? \.voiceCallSolid : \.videoCallSolid
        }
    }
}

struct CallNotificationRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static var previews: some View {
        dmTiles.environmentObject(viewModel.context)
            .previewDisplayName("DM")
        groupTiles.environmentObject(viewModel.context)
            .previewDisplayName("Group")
    }
    
    // Tombstoned call previews (`17 · Call tiles in chat`)
    static var dmTiles: some View {
        VStack(spacing: 0) {
            tile(isDM: true, isVoiceCall: true, .tombstoned(outcome: .declined(byMe: false)))
            Divider()
            tile(isDM: true, isVoiceCall: false, .tombstoned(outcome: .declined(byMe: true)))
            Divider()
            // G11 — missed, critical with the call-back affordance.
            tile(isDM: true, isVoiceCall: true, .tombstoned(outcome: .missed))
            Divider()
            // Decision 172 — the caller's own unanswered ring, grey.
            tile(isDM: true, isVoiceCall: true, .tombstoned(outcome: .cancelled), isOutgoing: true)
            Divider()
            // G12 — ended calls carry their length and direction.
            tile(isDM: true, isVoiceCall: true, .tombstoned(outcome: .answered(duration: 321)), isOutgoing: true)
            Divider()
            tile(isDM: true, isVoiceCall: false, .tombstoned(outcome: .answered(duration: 1458)))
        }
        .padding()
    }
    
    static var groupTiles: some View {
        VStack(spacing: 0) {
            tile(isDM: false, isVoiceCall: false, .tombstoned(outcome: .unclassified))
            Divider()
            // Decision 172 — a finished group call, joined and never joined.
            tile(isDM: false, isVoiceCall: false, .tombstoned(outcome: .groupCall(duration: 754, ownUserJoined: true)))
            Divider()
            tile(isDM: false, isVoiceCall: false, .tombstoned(outcome: .groupCall(duration: 754, ownUserJoined: false)))
            Divider()
            tile(isDM: false, isVoiceCall: false, .active(activeMembers: ["@alice:example.org"],
                                                          isJoined: false,
                                                          callStartTimestamp: Date()))
        }
        .padding()
    }
    
    private static func tile(isDM: Bool,
                             isVoiceCall: Bool,
                             _ callState: CallNotificationRoomTimelineItem.CallState,
                             isOutgoing: Bool = false) -> CallNotificationRoomTimelineView {
        CallNotificationRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             sender: .init(id: "@sender:localhost", displayName: "John"),
                                                             isDM: isDM,
                                                             isVoiceCall: isVoiceCall,
                                                             callState: callState,
                                                             isOutgoing: isOutgoing))
    }
}
