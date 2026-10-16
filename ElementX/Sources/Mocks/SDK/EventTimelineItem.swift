//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import LoremSwiftum
import MatrixRustSDK
import MatrixRustSDKMocks

nonisolated struct EventTimelineItemSDKMockConfiguration {
    var eventID: String = UUID().uuidString
    var sender = ""
    var senderProfile: ProfileDetails?
    var forwarder: String?
    var forwarderProfile: ProfileDetails?
    var isOwn = false
    var isEditable = false
    var canBeRepliedTo = false
    // AGENT-PLATFORM (Brief 0066): was a fixed `[:]`; the post tests need receipts.
    var readReceipts: [String: Receipt] = [:]
    // AGENT-PLATFORM (Brief 0066 § 5.89): was a fixed `nil`; the agent-tools
    // fallback is recognised by its raw JSON.
    var originalJSON: String?
    var content: TimelineItemContent = .msgLike(content: .init(kind: .redacted,
                                                               reactions: [],
                                                               inReplyTo: nil,
                                                               threadRoot: nil,
                                                               threadSummary: nil))
}

nonisolated extension EventTimelineItem {
    init(configuration: EventTimelineItemSDKMockConfiguration) {
        let lazyProvider = LazyTimelineItemProviderSDKMock()
        lazyProvider.containsOnlyEmojisReturnValue = false
        lazyProvider.getShieldsStrictReturnValue = ShieldState.none
        lazyProvider.debugInfoReturnValue = .init(model: "", originalJson: configuration.originalJSON, latestEditJson: nil)
        self.init(isRemote: true,
                  eventOrTransactionId: .eventId(eventId: configuration.eventID),
                  sender: configuration.sender,
                  senderProfile: configuration.senderProfile ?? .pending,
                  forwarder: configuration.forwarder,
                  forwarderProfile: configuration.forwarderProfile,
                  isOwn: configuration.isOwn,
                  isEditable: configuration.isEditable,
                  content: configuration.content,
                  eventTypeRaw: nil,
                  timestamp: UInt64(Date.mock.timeIntervalSince1970 * 1000),
                  localSendState: nil,
                  localCreatedAt: nil,
                  readReceipts: configuration.readReceipts,
                  origin: nil,
                  canBeRepliedTo: configuration.canBeRepliedTo,
                  lazyProvider: lazyProvider)
    }
    
    static var mockMessage: EventTimelineItem {
        let body = Lorem.sentences(Int.random(in: 1...5))
        let messageType = MessageType.text(content: .init(body: body, formatted: nil))
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        return .init(configuration: .init(content: content))
    }
    
    static func mockCallInvite(sender: String) -> EventTimelineItem {
        .init(configuration: .init(sender: sender, content: .callInvite))
    }
    
    // AGENT-PLATFORM (calls-in-app walk F7; decisions 171/172): a call tile
    // as the SDK hands it over, its `RtcCallOutcome` field by field.
    static func mockRtcNotification(sender: String,
                                    notificationType: String = "notification",
                                    declinedBy: [String] = [],
                                    activeMembers: [String] = [],
                                    callStartTsMillis: UInt64? = nil,
                                    isJoined: Bool = false,
                                    answeredBy: [String] = [],
                                    answeredTsMillis: UInt64? = nil,
                                    joinedBy: [String] = [],
                                    firstJoinedTsMillis: UInt64? = nil,
                                    ownUserJoined: Bool = false,
                                    endedTsMillis: UInt64? = nil) -> EventTimelineItem {
        .init(configuration: .init(sender: sender,
                                   content: .rtcNotification(callIntent: "audio",
                                                             declinedBy: declinedBy,
                                                             activeMembers: activeMembers,
                                                             callStartTsMillis: callStartTsMillis,
                                                             isJoined: isJoined,
                                                             notificationType: notificationType,
                                                             lifetimeMs: 30000,
                                                             outcome: .init(answeredBy: answeredBy,
                                                                            answeredTsMillis: answeredTsMillis,
                                                                            joinedBy: joinedBy,
                                                                            firstJoinedTsMillis: firstJoinedTsMillis,
                                                                            ownUserJoined: ownUserJoined,
                                                                            endedTsMillis: endedTsMillis))))
    }
    
    // AGENT-PLATFORM (Brief 0066)
    /// An Interactive Post, optionally carrying the things every other message
    /// carries — so a test can prove a post keeps them rather than assume it.
    static func mockInteractivePost(sender: String,
                                    title: String = "a counter",
                                    reactions: [Reaction] = [],
                                    readReceipts: [String: Receipt] = [:],
                                    isEdited: Bool = false) -> EventTimelineItem {
        let messageType = MessageType.interactivePost(content: .init(body: title,
                                                                     appId: "counter",
                                                                     runtime: "1",
                                                                     title: title,
                                                                     aspect: "4:3",
                                                                     stateChannel: "matrix",
                                                                     sha256: String(repeating: "a", count: 64),
                                                                     url: "mxc://spiral.md/abc",
                                                                     fileJson: nil))
        
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: title,
                                                                                               isEdited: isEdited,
                                                                                               mentions: nil)),
                                                                 reactions: reactions,
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        
        return .init(configuration: .init(sender: sender,
                                          isEditable: false,
                                          canBeRepliedTo: true,
                                          readReceipts: readReceipts,
                                          content: content))
    }
    
    // AGENT-PLATFORM (Brief 0073)
    /// A `com.spiral.notice` as the SDK fork hands it over: `.other(msgtype,
    /// body, data)`.
    static func mockSpiralNotice(sender: String, kind: String = "phrase_changed", body: String = "fallback") -> EventTimelineItem {
        let messageType = MessageType.other(msgtype: SpiralNotice.msgtype,
                                            body: body,
                                            data: #"{"com.spiral.notice":{"kind":"\#(kind)","device_name":"iPhone"}}"#)
        let content = TimelineItemContent.msgLike(content: .init(kind: .message(content: .init(msgType: messageType,
                                                                                               body: body,
                                                                                               isEdited: false,
                                                                                               mentions: nil)),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        return .init(configuration: .init(sender: sender, content: content))
    }
    
    // AGENT-PLATFORM (Brief 0066 § 5.89)
    /// A custom message-like event as the SDK hands it over: `.other`, with
    /// the raw event beside it. The SDK's custom event type cannot be built
    /// here (its payload is a Rust handle), so the kind carries a stand-in and
    /// the raw JSON says what the event is — which is what the factory reads.
    static func mockOtherMessageLike(sender: String, originalJSON: String) -> EventTimelineItem {
        let content = TimelineItemContent.msgLike(content: .init(kind: .other(eventType: .roomMessage),
                                                                 reactions: [],
                                                                 inReplyTo: nil,
                                                                 threadRoot: nil,
                                                                 threadSummary: nil))
        return .init(configuration: .init(sender: sender, originalJSON: originalJSON, content: content))
    }
}
