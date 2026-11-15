//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import Foundation
import SwiftUI

/// A reusable view component for rendering active call notifications.
/// This view displays information about an ongoing call including participants, duration, and a join button.
struct ActiveCallTimelineItemView: View {
    @Environment(\.timelineContext) private var context
    
    let isDM: Bool
    let isVoiceCall: Bool
    let activeMembers: [String]
    let sender: TimelineItemSender
    var isOutgoing = false // AGENT-PLATFORM (Brief 0083, question 359)
    let isJoined: Bool
    let callStartTimestamp: Date?
    
    static let maxAvatars = 3
    
    private var avatars: [StackedAvatarInfo] {
        activeMembers
            .prefix(ActiveCallTimelineItemView.maxAvatars)
            .map { userID in
                let member = context?.viewState.member(userID) // AGENT-PLATFORM (Brief 0083, question 359)
                return StackedAvatarInfo(url: member?.avatarURL, name: member?.displayName, contentID: userID)
            }
    }
    
    private var extraGroupLabel: String {
        if activeMembers.count == 1, activeMembers.first == sender.id {
            return L10n.commonUserStartedACall(sender.displayName ?? sender.id)
        } else {
            return L10n.screenTimelineActiveCallJoinedCount(activeMembers.count)
        }
    }
    
    // AGENT-PLATFORM (Brief 0063): an agent in the room must not relabel a 1:1 call.
    /// The tile describes the CALL, not the room: a DM whose assistant has
    /// actually connected is truthfully a 3-party group call, while an idle
    /// assistant in the room must not turn a 1:1 call into a "group call".
    static func isGroupPresentation(isDM: Bool, activeMemberCount: Int) -> Bool {
        !isDM || activeMemberCount > 2
    }
    
    private var isGroupPresentation: Bool {
        Self.isGroupPresentation(isDM: isDM, activeMemberCount: activeMembers.count)
    }
    
    private var title: String {
        if isGroupPresentation { // AGENT-PLATFORM (Brief 0063): was `if isDM`.
            L10n.commonGroupCallInProgress
        } else if activeMembers.count == 1, activeMembers.first == sender.id {
            L10n.commonUserStartedACall(sender.displayName ?? sender.id)
        } else {
            L10n.commonCallInProgress
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359): a bubble on the side of whoever called, as an ended call is.
    var body: some View {
        TimelineCallBubble(sender: sender,
                           isDM: isDM,
                           isOutgoing: isOutgoing,
                           icon: isVoiceCall ? \.voiceCallSolid : \.videoCallSolid,
                           title: title) {
            StackedAvatarsView(overlap: 6,
                               lineWidth: 1,
                               avatars: avatars,
                               avatarSize: .user(on: .readReceipt),
                               mediaProvider: context?.mediaProvider)
                .padding(-1)
            
            if isGroupPresentation {
                Text(extraGroupLabel)
            }
            
            callTimer
                .monospacedDigit()
        } accessory: {
            if !isJoined {
                joinButton
            }
        }
    }
    
    @ViewBuilder
    private var joinButton: some View {
        let button = Button { context?.send(viewAction: .joinActiveCall(isVoiceCall: isVoiceCall)) } label: {
            Text(L10n.actionJoin)
                .font(.compound.bodyMDSemibold)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isOutgoing ? OwnBubbleInk.solid.onStrongFill : .compound.textOnSolidPrimary)
                .padding(.vertical, 8)
                .background(isOutgoing ? OwnBubbleInk.solid.strongFill : .compound.bgActionPrimaryRest, in: .capsule)
                .contentShape(.capsule)
        }
        
        button.buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var callTimer: some View {
        if let callStartTimestamp {
            if ProcessInfo.isRunningTests {
                Text("0:00") // A slow runner can take more than a second to record the snapshot 🤦‍♂️
            } else {
                Text(callStartTimestamp, style: .timer)
            }
        }
    }
}

// MARK: - Previews

struct ActiveCallTimelineItemView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static let twoMembers = [
        "@alice:example.org",
        "@bob:example.org"
    ]
    
    static let memberIDs = [
        "@alice:example.org",
        "@bob:example.org",
        "@charlie:example.org",
        "@dave:example.org",
        "@joe:example.org",
        "@jackie:example.org"
    ]
    
    static var previews: some View {
        VStack(spacing: 0) {
            // Single member
            ActiveCallTimelineItemView(isDM: false,
                                       isVoiceCall: false,
                                       activeMembers: ["@alice:example.org"],
                                       sender: .init(id: "@alice:example.org", displayName: "Alice"),
                                       isJoined: false,
                                       callStartTimestamp: Date())
            
            Divider()
            
            // Multiple members
            ActiveCallTimelineItemView(isDM: false,
                                       isVoiceCall: false,
                                       activeMembers: memberIDs,
                                       sender: .init(id: "@sender:localhost"),
                                       isJoined: false,
                                       callStartTimestamp: nil)
            
            Divider()
            
            // Voice call
            ActiveCallTimelineItemView(isDM: false,
                                       isVoiceCall: true,
                                       activeMembers: memberIDs,
                                       sender: .init(id: "@sender:localhost"),
                                       isJoined: false,
                                       callStartTimestamp: nil)
            
            Divider()
            
            // DM
            ActiveCallTimelineItemView(isDM: true,
                                       isVoiceCall: false,
                                       activeMembers: twoMembers,
                                       sender: .init(id: "@sender:localhost"),
                                       isJoined: false,
                                       callStartTimestamp: nil)
            
            Divider()
            
            // DM with single member
            ActiveCallTimelineItemView(isDM: true,
                                       isVoiceCall: false,
                                       activeMembers: ["@sender:localhost"],
                                       sender: .init(id: "@sender:localhost", displayName: "John"),
                                       isJoined: false,
                                       callStartTimestamp: nil)
        }
        .padding()
        .environmentObject(viewModel.context)
    }
}
