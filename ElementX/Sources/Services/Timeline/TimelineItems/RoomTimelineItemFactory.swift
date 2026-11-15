//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK
import UIKit
import UniformTypeIdentifiers

nonisolated struct RoomTimelineItemFactory: RoomTimelineItemFactoryProtocol {
    private let attributedStringBuilder: AttributedStringBuilderProtocol
    private let stateEventStringBuilder: RoomStateEventStringBuilder
    
    /// The Matrix ID of the current user.
    private let userID: String
    
    init(userID: String,
         attributedStringBuilder: AttributedStringBuilderProtocol,
         stateEventStringBuilder: RoomStateEventStringBuilder) {
        self.userID = userID
        self.attributedStringBuilder = attributedStringBuilder
        self.stateEventStringBuilder = stateEventStringBuilder
    }
    
    // MARK: - Public
    
    func buildTimelineItem(for eventItemProxy: EventTimelineItemProxy, isDM: Bool) -> RoomTimelineItemProtocol? {
        let isOutgoing = eventItemProxy.isOwn
        
        switch eventItemProxy.content {
        case .msgLike(let messageLikeContent):
            switch messageLikeContent.kind {
            case .message(let messageContent):
                return buildMessageTimelineItem(eventItemProxy, messageLikeContent, messageContent, isOutgoing)
            case .sticker(let body, let imageInfo, let mediaSource):
                return buildStickerTimelineItem(eventItemProxy, messageLikeContent, body, imageInfo, mediaSource, isOutgoing)
            case .poll(question: let question, kind: let kind, maxSelections: let maxSelections, answers: let answers, votes: let votes, endTime: let endTime, let edited):
                return buildPollTimelineItem(eventItemProxy, messageLikeContent, question, kind, maxSelections, answers, votes, endTime, isOutgoing, edited)
            case .redacted:
                return buildRedactedTimelineItem(eventItemProxy, messageLikeContent, isOutgoing)
            case .unableToDecrypt(let encryptedMessage):
                return buildEncryptedTimelineItem(eventItemProxy, messageLikeContent, encryptedMessage, isOutgoing)
            case .liveLocation(let content):
                return buildLiveLocationTimelineItem(eventItemProxy, messageLikeContent, content, isOutgoing)
            case .other:
                // AGENT-PLATFORM (Brief 0066 § 5.89): the agent-tools fallback
                // reads as the state row it stands in for. Recognised by the
                // raw event's `type` (the SDK's custom event type cannot be
                // built in a test, the JSON can); every other custom
                // message-like event stays hidden, as upstream has it.
                return buildSpiralToolsFallbackTimelineItem(for: eventItemProxy, isOutgoing: isOutgoing)
            }
        case .failedToParseMessageLike(let eventType, let error):
            return buildUnsupportedTimelineItem(eventItemProxy, eventType, error, isOutgoing)
        case .failedToParseState(let eventType, _, let error):
            return buildUnsupportedTimelineItem(eventItemProxy, eventType, error, isOutgoing)
        case .state(_, let content):
            if isDM, case .roomCreate = content {
                return nil
            }
            return buildStateTimelineItem(for: eventItemProxy, state: content, isOutgoing: isOutgoing)
        case .roomMembership(userId: let userID, let displayName, change: let change, let reason):
            if isDM, change == .joined, userID == self.userID {
                return nil
            }
            return buildStateMembershipChangeTimelineItem(for: eventItemProxy, memberUserID: userID, memberDisplayName: displayName, membershipChange: change, reason: reason, isOutgoing: isOutgoing)
        case .profileChange(let displayName, let prevDisplayName, let avatarUrl, let prevAvatarUrl):
            return buildStateProfileChangeTimelineItem(for: eventItemProxy,
                                                       displayName: displayName,
                                                       previousDisplayName: prevDisplayName,
                                                       avatarURLString: avatarUrl,
                                                       previousAvatarURLString: prevAvatarUrl,
                                                       isOutgoing: isOutgoing)
        case .callInvite:
            return buildCallInviteTimelineItem(for: eventItemProxy)
        case .rtcNotification(let callIntent, let declinedBy, let activeMembers, _, let isJoined,
                              let notificationType, _, let outcome):
            return buildCallNotificationTimelineItem(for: eventItemProxy,
                                                     isDM: isDM,
                                                     callIntent: callIntent,
                                                     declinedBy: declinedBy,
                                                     activeMembers: activeMembers,
                                                     isJoined: isJoined,
                                                     notificationType: notificationType,
                                                     outcome: outcome)
        }
    }
    
    func buildTimelineItemReply(_ details: MatrixRustSDK.InReplyToDetails) -> TimelineItemReply {
        let isThreaded = details.event().isThreaded
        switch details.event() {
        case .unavailable:
            return .init(details: .notLoaded(eventID: details.eventId()), isThreaded: isThreaded)
        case .pending:
            return .init(details: .loading(eventID: details.eventId()), isThreaded: isThreaded)
        case let .ready(timelineItem, senderID, senderProfile, _, _):
            let sender = TimelineItemSender(senderID: senderID, senderProfile: senderProfile)
            
            let replyContent: TimelineEventContent
            
            switch timelineItem {
            case .msgLike(let messageLikeContent):
                switch messageLikeContent.kind {
                case .message(let messageContent):
                    return .init(details: .loaded(sender: sender,
                                                  eventID: details.eventId(),
                                                  eventContent: buildEventContent(messageType: messageContent.msgType,
                                                                                  senderID: sender.id,
                                                                                  senderDisplayName: sender.displayName)),
                                 isThreaded: isThreaded)
                case .poll(let question, _, _, _, _, _, _):
                    replyContent = .poll(question: question)
                case .sticker(let body, _, _):
                    replyContent = .message(.text(.init(body: body)))
                case .redacted:
                    replyContent = .redacted
                case .liveLocation:
                    replyContent = .liveLocation
                default:
                    replyContent = .message(.text(.init(body: L10n.commonUnsupportedEvent)))
                }
            default:
                replyContent = .message(.text(.init(body: L10n.commonUnsupportedEvent)))
            }
            
            return .init(details: .loaded(sender: sender, eventID: details.eventId(), eventContent: replyContent), isThreaded: isThreaded)
        case let .error(message):
            return .init(details: .error(eventID: details.eventId(), message: message), isThreaded: isThreaded)
        }
    }
    
    /// What a message looks like when something else STANDS IN for it — a
    /// reply, a thread summary, a search result.
    ///
    /// A post names its kind here, the way a poll quotes its question. Without
    /// it the fallback was `.message(.text(title))`, so a quoted post read as
    /// somebody having typed its name — which is precisely the information a
    /// quotation exists to carry.
    func buildEventContent(messageType: MessageType, senderID: String, senderDisplayName: String?) -> TimelineEventContent {
        if case .interactivePost(let content) = messageType {
            return .interactivePost(title: content.title)
        }

        return .message(buildMessageTimelineItemContent(messageType: messageType,
                                                        senderID: senderID,
                                                        senderDisplayName: senderDisplayName))
    }

    func buildMessageTimelineItemContent(messageType: MessageType?, senderID: String, senderDisplayName: String?) -> EventBasedMessageTimelineItemContentType {
        switch messageType {
        case .audio(let content):
            if content.voice != nil {
                .voice(buildAudioTimelineItemContent(content))
            } else {
                .audio(buildAudioTimelineItemContent(content))
            }
        case .emote(let content):
            .emote(buildEmoteTimelineItemContent(senderDisplayName: senderDisplayName, senderID: senderID, messageContent: content))
        case .file(let content):
            .file(buildFileTimelineItemContent(content))
        case .image(let content):
            .image(buildImageTimelineItemContent(content))
        case .notice(let content):
            .notice(buildNoticeTimelineItemContent(content))
        case .text(let content):
            .text(buildTextTimelineItemContent(content, senderID: senderID))
        case .video(let content):
            .video(buildVideoTimelineItemContent(content))
        case .location(let content):
            .location(buildLocationTimelineItemContent(content))
        case .gallery(let content):
            .gallery(buildGalleryTimelineItemContent(content, timelineItemID: .randomEvent))
        // A reply or a pinned preview of a post: its title, as text. The live
        // app belongs to the post's own row, not to a quotation of it.
        case .interactivePost(let content):
            .text(.init(body: content.title))
        case .interactiveDraft(let content):
            .text(.init(body: content.title))
        // AGENT-PLATFORM (Brief 0073): a notice quoted in a reply reads in
        // the reader's language, as it does in the timeline.
        case .other(let msgtype, let body, let data):
            .text(.init(body: SpiralNotice(msgtype: msgtype, data: data)?.plainText ?? body))
        case .none:
            .text(.init(body: L10n.commonUnsupportedEvent))
        }
    }
    
    // MARK: - Private
    
    // MARK: - MsgLike Events
    
    private func buildMessageTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                          _ messageLikeContent: MsgLikeContent,
                                          _ messageContent: MessageContent,
                                          _ isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        switch messageContent.msgType {
        case .text(content: let textMessageContent):
            return buildTextTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, textMessageContent, isOutgoing)
        case .image(content: let imageMessageContent):
            return buildImageTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, imageMessageContent, isOutgoing)
        case .video(let videoMessageContent):
            return buildVideoTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, videoMessageContent, isOutgoing)
        case .file(let fileMessageContent):
            return buildFileTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, fileMessageContent, isOutgoing)
        case .notice(content: let noticeMessageContent):
            return buildNoticeTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, noticeMessageContent, isOutgoing)
        case .emote(content: let emoteMessageContent):
            return buildEmoteTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, emoteMessageContent, isOutgoing)
        case .audio(let audioMessageContent):
            if audioMessageContent.voice != nil {
                return buildVoiceTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, audioMessageContent, isOutgoing)
            } else {
                return buildAudioTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, audioMessageContent, isOutgoing)
            }
        case .location(let locationMessageContent):
            return buildLocationTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, locationMessageContent, isOutgoing)
        case .gallery(let galleryMessageContent):
            return buildGalleryTimelineItem(for: eventItemProxy, messageLikeContent, messageContent, galleryMessageContent, isOutgoing)
        // AGENT-PLATFORM (Brief 0066, ADR-0007): an Interactive Post is a
        // message type of its own, the way a photo is `m.image`.
        case .interactivePost(let postContent):
            return buildInteractivePostTimelineItem(eventItemProxy, messageLikeContent, messageContent, postContent, isOutgoing)
        // A draft's card publishes its code as the reader with one tap, so
        // only the platform's agents get one — of THIS server: an
        // `@assistant-…` elsewhere is anybody's name (N6). From anyone else
        // it is the plain text it says it is.
        case .interactiveDraft(let draftContent):
            guard SpiralAgentRoomGrants.isLocalAgent(eventItemProxy.sender.id, ownUserID: userID) else {
                return buildNoticeTimelineItem(for: eventItemProxy, messageLikeContent, messageContent,
                                               notice: nil, fallbackBody: messageContent.body, isOutgoing)
            }
            return buildInteractiveDraftTimelineItem(eventItemProxy, messageLikeContent, messageContent, draftContent, isOutgoing)
        // The agent's «generating» marker (§ 5.71) — a msgtype of its own the
        // SDK passes through as `.other`; every other unknown msgtype stays hidden.
        // AGENT-PLATFORM (Brief 0073): a client-rendered notice — the server
        // sent the facts, the words are chosen here. An unknown kind shows
        // its English fallback body like any text message.
        // Only the platform's agents post notices (their MXIDs live in the
        // application service's exclusive namespace); from anyone else the
        // same msgtype is plain text — a person cannot forge a «sign-in
        // phrase changed» or «joined through your invitation» card.
        case .other(let msgtype, let body, let data) where msgtype == SpiralNotice.msgtype:
            let isFromAgent = SpiralAppPostSession.isAgent(eventItemProxy.sender.id)
            // AGENT-PLATFORM (decision 371): the one kind that stays a message.
            if isFromAgent, let summary = SpiralCallSummary(msgtype: msgtype, data: data) {
                return buildCallSummaryTimelineItem(eventItemProxy, messageLikeContent, messageContent, summary, body: body, isOutgoing)
            }
            let notice = isFromAgent ? SpiralNotice(msgtype: msgtype, data: data) : nil
            return buildNoticeTimelineItem(for: eventItemProxy, messageLikeContent, messageContent,
                                           notice: notice, fallbackBody: body, isOutgoing)
        case .other(let msgtype, let body, _) where msgtype == InteractiveGeneratingRoomTimelineItem.msgtype:
            return InteractiveGeneratingRoomTimelineItem(id: eventItemProxy.id,
                                                         body: body,
                                                         timestamp: eventItemProxy.timestamp,
                                                         isOutgoing: isOutgoing,
                                                         isEditable: false,
                                                         canBeRepliedTo: false,
                                                         sender: eventItemProxy.sender,
                                                         properties: .init(isThreaded: messageLikeContent.threadRoot != nil))
        case .other:
            return nil
        }
    }

    /// The row for an Interactive Post.
    ///
    /// Nothing is parsed here: the SDK already read the post's claims about
    /// itself, so the row is sized and named from typed content. A post that
    /// names no artifact never reaches this — it converts to an ordinary
    /// unknown message, which is what it is.
    ///
    /// `properties` is built exactly as every other message builds it. It was
    /// once left at its default, and the nine things it carries — reactions,
    /// read receipts, delivery status, replies, threads, the edited marker and
    /// the encryption shields — were all silently dead on a post while looking
    /// deliberate.
    private func buildInteractivePostTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                                  _ messageLikeContent: MsgLikeContent,
                                                  _ messageContent: MessageContent,
                                                  _ postContent: InteractivePostContent,
                                                  _ isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        let post = SpiralAppPost(postContent)

        return InteractivePostRoomTimelineItem(id: eventItemProxy.id,
                                               // A catalogue template's post reads in the reader's language,
                                               // not the publisher's it was stored in.
                                               body: SpiralAppTemplateTitles.standard.title(forAppID: post.appID) ?? post.title,
                                               timestamp: eventItemProxy.timestamp,
                                               isOutgoing: isOutgoing,
                                               isEditable: eventItemProxy.isEditable,
                                               canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                               sender: eventItemProxy.sender,
                                               post: post,
                                               properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                                 isThreaded: messageLikeContent.threadRoot != nil,
                                                                 threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                                 isEdited: messageContent.isEdited,
                                                                 reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                                 deliveryStatus: eventItemProxy.deliveryStatus,
                                                                 encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                                 encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildInteractiveDraftTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                                   _ messageLikeContent: MsgLikeContent,
                                                   _ messageContent: MessageContent,
                                                   _ draftContent: InteractiveDraftContent,
                                                   _ isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        let draft = SpiralAppDraft(draftContent)

        return InteractiveDraftRoomTimelineItem(id: eventItemProxy.id,
                                                body: draft.title,
                                                timestamp: eventItemProxy.timestamp,
                                                isOutgoing: isOutgoing,
                                                isEditable: false,
                                                canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                                sender: eventItemProxy.sender,
                                                draft: draft,
                                                properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                                  isThreaded: messageLikeContent.threadRoot != nil,
                                                                  threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                                  isEdited: messageContent.isEdited,
                                                                  reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                                  deliveryStatus: eventItemProxy.deliveryStatus,
                                                                  encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                                  encryptionForwarder: eventItemProxy.forwarder))
    }

    private func buildTextTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                       _ messageLikeContent: MsgLikeContent,
                                       _ messageContent: MessageContent,
                                       _ textMessageContent: TextMessageContent,
                                       _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        TextRoomTimelineItem(id: eventItemProxy.id,
                             timestamp: eventItemProxy.timestamp,
                             isOutgoing: isOutgoing,
                             isEditable: eventItemProxy.isEditable,
                             canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                             shouldBoost: eventItemProxy.shouldBoost,
                             sender: eventItemProxy.sender,
                             content: buildTextTimelineItemContent(textMessageContent, senderID: eventItemProxy.sender.id),
                             properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                               isThreaded: messageLikeContent.threadRoot != nil,
                                               threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                               isEdited: messageContent.isEdited,
                                               reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                               deliveryStatus: eventItemProxy.deliveryStatus,
                                               encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                               encryptionForwarder: eventItemProxy.forwarder))
    }
    
    // AGENT-PLATFORM (decision 371)
    private func buildCallSummaryTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                              _ messageLikeContent: MsgLikeContent,
                                              _ messageContent: MessageContent,
                                              _ summary: SpiralCallSummary,
                                              body: String,
                                              _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        CallSummaryRoomTimelineItem(id: eventItemProxy.id,
                                    timestamp: eventItemProxy.timestamp,
                                    isOutgoing: isOutgoing,
                                    isEditable: false,
                                    canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                    sender: eventItemProxy.sender,
                                    content: TextRoomTimelineItemContent(body: body),
                                    summary: summary,
                                    properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                      isThreaded: messageLikeContent.threadRoot != nil,
                                                      threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                      isEdited: messageContent.isEdited,
                                                      reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                      deliveryStatus: eventItemProxy.deliveryStatus,
                                                      encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                      encryptionForwarder: eventItemProxy.forwarder))
    }
    
    // AGENT-PLATFORM (Brief 0073): a notice this client knows is a card of
    // its own (`SpiralNoticeRoomTimelineItem`); a kind it does not know yet
    // shows its English fallback as an ordinary text row.
    private func buildNoticeTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                         _ messageLikeContent: MsgLikeContent,
                                         _ messageContent: MessageContent,
                                         notice: SpiralNotice?,
                                         fallbackBody: String,
                                         _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        if let notice {
            return SpiralNoticeRoomTimelineItem(id: eventItemProxy.id,
                                                timestamp: eventItemProxy.timestamp,
                                                sender: eventItemProxy.sender,
                                                notice: notice)
        }
        
        let content = TextRoomTimelineItemContent(body: fallbackBody, formattedBody: attributedStringBuilder.fromPlain(fallbackBody))
        return TextRoomTimelineItem(id: eventItemProxy.id,
                                    timestamp: eventItemProxy.timestamp,
                                    isOutgoing: isOutgoing,
                                    isEditable: false,
                                    canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                    shouldBoost: eventItemProxy.shouldBoost,
                                    sender: eventItemProxy.sender,
                                    content: content,
                                    properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                      isThreaded: messageLikeContent.threadRoot != nil,
                                                      threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                      isEdited: messageContent.isEdited,
                                                      reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                      deliveryStatus: eventItemProxy.deliveryStatus,
                                                      encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                      encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildImageTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        _ messageLikeContent: MsgLikeContent,
                                        _ messageContent: MessageContent,
                                        _ imageMessageContent: ImageMessageContent,
                                        _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        ImageRoomTimelineItem(id: eventItemProxy.id,
                              timestamp: eventItemProxy.timestamp,
                              isOutgoing: isOutgoing,
                              isEditable: eventItemProxy.isEditable,
                              canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                              shouldBoost: eventItemProxy.shouldBoost,
                              sender: eventItemProxy.sender,
                              content: buildImageTimelineItemContent(imageMessageContent),
                              properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                isThreaded: messageLikeContent.threadRoot != nil,
                                                threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                isEdited: messageContent.isEdited,
                                                reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                deliveryStatus: eventItemProxy.deliveryStatus,
                                                encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildVideoTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        _ messageLikeContent: MsgLikeContent,
                                        _ messageContent: MessageContent,
                                        _ videoMessageContent: VideoMessageContent,
                                        _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        VideoRoomTimelineItem(id: eventItemProxy.id,
                              timestamp: eventItemProxy.timestamp,
                              isOutgoing: isOutgoing,
                              isEditable: eventItemProxy.isEditable,
                              canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                              shouldBoost: eventItemProxy.shouldBoost,
                              sender: eventItemProxy.sender,
                              content: buildVideoTimelineItemContent(videoMessageContent),
                              properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                isThreaded: messageLikeContent.threadRoot != nil,
                                                threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                isEdited: messageContent.isEdited,
                                                reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                deliveryStatus: eventItemProxy.deliveryStatus,
                                                encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildAudioTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        _ messageLikeContent: MsgLikeContent,
                                        _ messageContent: MessageContent,
                                        _ audioMessageContent: AudioMessageContent,
                                        _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        AudioRoomTimelineItem(id: eventItemProxy.id,
                              timestamp: eventItemProxy.timestamp,
                              isOutgoing: isOutgoing,
                              isEditable: eventItemProxy.isEditable,
                              canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                              shouldBoost: eventItemProxy.shouldBoost,
                              sender: eventItemProxy.sender,
                              content: buildAudioTimelineItemContent(audioMessageContent),
                              properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                isThreaded: messageLikeContent.threadRoot != nil,
                                                threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                isEdited: messageContent.isEdited,
                                                reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                deliveryStatus: eventItemProxy.deliveryStatus,
                                                encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildVoiceTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        _ messageLikeContent: MsgLikeContent,
                                        _ messageContent: MessageContent,
                                        _ audioMessageContent: AudioMessageContent,
                                        _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        VoiceMessageRoomTimelineItem(id: eventItemProxy.id,
                                     timestamp: eventItemProxy.timestamp,
                                     isOutgoing: isOutgoing,
                                     isEditable: eventItemProxy.isEditable,
                                     canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                     sender: eventItemProxy.sender,
                                     content: buildAudioTimelineItemContent(audioMessageContent),
                                     properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                       isThreaded: messageLikeContent.threadRoot != nil,
                                                       threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                       isEdited: messageContent.isEdited,
                                                       reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                       deliveryStatus: eventItemProxy.deliveryStatus,
                                                       encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                       encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildFileTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                       _ messageLikeContent: MsgLikeContent,
                                       _ messageContent: MessageContent,
                                       _ fileMessageContent: FileMessageContent,
                                       _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        FileRoomTimelineItem(id: eventItemProxy.id,
                             timestamp: eventItemProxy.timestamp,
                             isOutgoing: isOutgoing,
                             isEditable: eventItemProxy.isEditable,
                             canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                             shouldBoost: eventItemProxy.shouldBoost,
                             sender: eventItemProxy.sender,
                             content: buildFileTimelineItemContent(fileMessageContent),
                             properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                               isThreaded: messageLikeContent.threadRoot != nil,
                                               threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                               isEdited: messageContent.isEdited,
                                               reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                               deliveryStatus: eventItemProxy.deliveryStatus,
                                               encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                               encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildNoticeTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                         _ messageLikeContent: MsgLikeContent,
                                         _ messageContent: MessageContent,
                                         _ noticeMessageContent: NoticeMessageContent,
                                         _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        NoticeRoomTimelineItem(id: eventItemProxy.id,
                               timestamp: eventItemProxy.timestamp,
                               isOutgoing: isOutgoing,
                               isEditable: eventItemProxy.isEditable,
                               canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                               sender: eventItemProxy.sender,
                               content: buildNoticeTimelineItemContent(noticeMessageContent),
                               properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                 isThreaded: messageLikeContent.threadRoot != nil,
                                                 threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                 isEdited: messageContent.isEdited,
                                                 reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                 deliveryStatus: eventItemProxy.deliveryStatus,
                                                 encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                 encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildEmoteTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        _ messageLikeContent: MsgLikeContent,
                                        _ messageContent: MessageContent,
                                        _ emoteMessageContent: EmoteMessageContent,
                                        _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        EmoteRoomTimelineItem(id: eventItemProxy.id,
                              timestamp: eventItemProxy.timestamp,
                              isOutgoing: isOutgoing,
                              isEditable: eventItemProxy.isEditable,
                              canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                              sender: eventItemProxy.sender,
                              content: buildEmoteTimelineItemContent(senderDisplayName: eventItemProxy.sender.displayName, senderID: eventItemProxy.sender.id, messageContent: emoteMessageContent),
                              properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                isThreaded: messageLikeContent.threadRoot != nil,
                                                threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                isEdited: messageContent.isEdited,
                                                reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                deliveryStatus: eventItemProxy.deliveryStatus,
                                                encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildLocationTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                           _ messageLikeContent: MsgLikeContent,
                                           _ messageContent: MessageContent,
                                           _ locationMessageContent: LocationContent,
                                           _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        LocationRoomTimelineItem(id: eventItemProxy.id,
                                 timestamp: eventItemProxy.timestamp,
                                 isOutgoing: isOutgoing,
                                 isEditable: eventItemProxy.isEditable,
                                 canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                 sender: eventItemProxy.sender,
                                 content: buildLocationTimelineItemContent(locationMessageContent),
                                 properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                   isThreaded: messageLikeContent.threadRoot != nil,
                                                   threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                   isEdited: messageContent.isEdited,
                                                   reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                   deliveryStatus: eventItemProxy.deliveryStatus,
                                                   encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                   encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildGalleryTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                          _ messageLikeContent: MsgLikeContent,
                                          _ messageContent: MessageContent,
                                          _ galleryMessageContent: GalleryMessageContent,
                                          _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        GalleryRoomTimelineItem(id: eventItemProxy.id,
                                timestamp: eventItemProxy.timestamp,
                                isOutgoing: isOutgoing,
                                isEditable: eventItemProxy.isEditable,
                                canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                shouldBoost: eventItemProxy.shouldBoost,
                                sender: eventItemProxy.sender,
                                content: buildGalleryTimelineItemContent(galleryMessageContent, timelineItemID: eventItemProxy.id),
                                properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                  isThreaded: messageLikeContent.threadRoot != nil,
                                                  threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                  isEdited: messageContent.isEdited,
                                                  reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                  deliveryStatus: eventItemProxy.deliveryStatus,
                                                  encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                  encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildGalleryTimelineItemContent(_ messageContent: GalleryMessageContent, timelineItemID: TimelineItemIdentifier) -> GalleryRoomTimelineItemContent {
        let htmlCaption = messageContent.formatted?.format == .html ? messageContent.formatted?.body : nil
        let plainCaption = messageContent.formatted?.format != .html ? messageContent.formatted?.body : nil
        let formattedCaption = htmlCaption != nil ? attributedStringBuilder.fromHTML(htmlCaption) : (plainCaption.flatMap(attributedStringBuilder.fromPlain))
        
        let items = messageContent.itemtypes.enumerated().map { index, itemType in
            buildGalleryItem(itemType, id: GalleryItemID(timelineItemID: timelineItemID, mediaIndex: index))
        }
        
        return GalleryRoomTimelineItemContent(body: messageContent.body,
                                              caption: plainCaption ?? messageContent.body,
                                              formattedCaption: formattedCaption,
                                              formattedCaptionHTMLString: htmlCaption,
                                              items: items)
    }
    
    private func buildGalleryItem(_ itemType: GalleryItemType, id: GalleryItemID) -> GalleryItem {
        switch itemType {
        case .image(let content):
            .image(id: id, buildImageTimelineItemContent(content))
        case .video(let content):
            .video(id: id, buildVideoTimelineItemContent(content))
        case .audio(let content):
            .audio(id: id, buildAudioTimelineItemContent(content))
        case .file(let content):
            .file(id: id, buildFileTimelineItemContent(content))
        case .other(_, let body):
            .other(id: id, filename: body)
        }
    }
    
    private func buildStickerTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                          _ messageLikeContent: MsgLikeContent,
                                          _ body: String,
                                          _ info: MatrixRustSDK.ImageInfo,
                                          _ mediaSource: MediaSource,
                                          _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        let imageInfo = ImageInfoProxy(source: mediaSource, width: info.width, height: info.height, mimeType: info.mimetype, fileSize: info.size.map(UInt.init))
        
        return StickerRoomTimelineItem(id: eventItemProxy.id,
                                       body: body,
                                       timestamp: eventItemProxy.timestamp,
                                       isOutgoing: isOutgoing,
                                       isEditable: eventItemProxy.isEditable,
                                       canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                       sender: eventItemProxy.sender,
                                       imageInfo: imageInfo,
                                       blurhash: info.blurhash,
                                       properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                         isThreaded: messageLikeContent.threadRoot != nil,
                                                         threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                         reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                         deliveryStatus: eventItemProxy.deliveryStatus,
                                                         encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                         encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildPollTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                       _ messageLikeContent: MsgLikeContent,
                                       _ question: String,
                                       _ pollKind: PollKind,
                                       _ maxSelections: UInt64,
                                       _ answers: [PollAnswer],
                                       _ votes: [String: [String]],
                                       _ endTime: UInt64?,
                                       _ isOutgoing: Bool,
                                       _ edited: Bool) -> RoomTimelineItemProtocol {
        let allVotes = votes.reduce(0) { count, pair in
            count + pair.value.count
        }
        
        let maxOptionVotes = votes.map(\.value.count).max()
        
        let options = answers.map { answer in
            let optionVotesCount = votes[answer.id]?.count
            
            return Poll.Option(id: answer.id,
                               text: answer.text,
                               votes: optionVotesCount ?? 0,
                               allVotes: allVotes,
                               isSelected: votes[answer.id]?.contains(userID) ?? false,
                               isWinning: optionVotesCount.map { $0 == maxOptionVotes } ?? false)
        }
        
        let pollKind: Poll.Kind = switch pollKind {
        case .disclosed:
            .disclosed
        case .undisclosed:
            .undisclosed
        }
        
        let poll = Poll(question: question,
                        kind: pollKind,
                        maxSelections: Int(maxSelections),
                        options: options,
                        votes: votes,
                        endDate: endTime.map { Date(timeIntervalSince1970: TimeInterval($0 / 1000)) },
                        createdByAccountOwner: eventItemProxy.sender.id == userID)
        
        return PollRoomTimelineItem(id: eventItemProxy.id,
                                    poll: poll,
                                    body: poll.question,
                                    timestamp: eventItemProxy.timestamp,
                                    isOutgoing: isOutgoing,
                                    isEditable: eventItemProxy.isEditable,
                                    canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                    sender: eventItemProxy.sender,
                                    properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                      isThreaded: messageLikeContent.threadRoot != nil,
                                                      threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                      isEdited: edited,
                                                      reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                      deliveryStatus: eventItemProxy.deliveryStatus,
                                                      encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                      encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildLiveLocationTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                               _ messageLikeContent: MsgLikeContent,
                                               _ liveLocationContent: LiveLocationContent,
                                               _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        LiveLocationRoomTimelineItem(id: eventItemProxy.id,
                                     timestamp: eventItemProxy.timestamp,
                                     isOutgoing: isOutgoing,
                                     isEditable: eventItemProxy.isEditable,
                                     canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                     sender: eventItemProxy.sender,
                                     content: .init(from: liveLocationContent, timestamp: eventItemProxy.timestamp),
                                     properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                       isThreaded: messageLikeContent.threadRoot != nil,
                                                       threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary),
                                                       reactions: buildAggregatedReactions(eventItemProxy.reactions),
                                                       deliveryStatus: eventItemProxy.deliveryStatus,
                                                       encryptionAuthenticity: buildEncryptionAuthenticity(eventItemProxy.shieldState),
                                                       encryptionForwarder: eventItemProxy.forwarder))
    }
    
    private func buildRedactedTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                           _ messageLikeContent: MsgLikeContent,
                                           _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        RedactedRoomTimelineItem(id: eventItemProxy.id,
                                 body: L10n.commonMessageRemoved,
                                 timestamp: eventItemProxy.timestamp,
                                 isOutgoing: isOutgoing,
                                 isEditable: eventItemProxy.isEditable,
                                 canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                 sender: eventItemProxy.sender,
                                 properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                   isThreaded: messageLikeContent.threadRoot != nil,
                                                   threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary)))
    }
    
    private func buildEncryptedTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                            _ messageLikeContent: MsgLikeContent,
                                            _ encryptedMessage: EncryptedMessage,
                                            _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        var encryptionType = EncryptedRoomTimelineItem.EncryptionType.unknown
        var errorLabel = L10n.commonWaitingForDecryptionKey
        switch encryptedMessage {
        case .megolmV1AesSha2(let sessionID, let cause):
            switch cause {
            case .unknown:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .unknown)
                errorLabel = L10n.commonWaitingForDecryptionKey
            case .verificationViolation:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .verificationViolation)
                errorLabel = L10n.commonUnableToDecryptVerificationViolation
            case .unsignedDevice, .unknownDevice:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .insecureDevice)
                errorLabel = L10n.commonUnableToDecryptInsecureDevice
            case .sentBeforeWeJoined:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .sentBeforeWeJoined)
                errorLabel = L10n.commonUnableToDecryptNoAccess
            case .historicalMessageAndBackupIsDisabled:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .historicalMessageAndBackupDisabled)
                errorLabel = L10n.timelineDecryptionFailureHistoricalEventNoKeyBackup
            case .historicalMessageAndDeviceIsUnverified:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .historicalMessageAndDeviceIsUnverified)
                errorLabel = L10n.timelineDecryptionFailureHistoricalEventUnverifiedDevice
            case .withheldForUnverifiedOrInsecureDevice:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .withheldForUnverifiedOrInsecureDevice)
                errorLabel = L10n.timelineDecryptionFailureWithheldUnverified
            case .withheldBySender:
                encryptionType = .megolmV1AesSha2(sessionID: sessionID, cause: .witheldBySender)
                errorLabel = L10n.timelineDecryptionFailureUnableToDecrypt
            }
        case .olmV1Curve25519AesSha2(let senderKey):
            encryptionType = .olmV1Curve25519AesSha2(senderKey: senderKey)
        case .unknown:
            break
        }
        
        return EncryptedRoomTimelineItem(id: eventItemProxy.id,
                                         body: errorLabel,
                                         encryptionType: encryptionType,
                                         timestamp: eventItemProxy.timestamp,
                                         isOutgoing: isOutgoing,
                                         isEditable: eventItemProxy.isEditable,
                                         canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                         sender: eventItemProxy.sender,
                                         properties: .init(replyDetails: buildTimelineItemReplyDetails(messageLikeContent.inReplyTo),
                                                           isThreaded: messageLikeContent.threadRoot != nil,
                                                           threadSummary: buildTimelineItemThreadSummary(messageLikeContent.threadSummary)))
    }
    
    // MARK: - Message events content
    
    private func buildTextTimelineItemContent(_ messageContent: TextMessageContent, senderID: String) -> TextRoomTimelineItemContent {
        let htmlBody = messageContent.formatted?.format == .html ? messageContent.formatted?.body : nil
        // AGENT-PLATFORM (coverage walk F6): an agent writes Markdown in a plain body; it renders like a formatted message.
        let agentHTML = htmlBody == nil && SpiralAppPostSession.isAgent(senderID) ? SpiralAgentMarkdown.html(fromBody: messageContent.body) : nil
        let formattedBody = if let html = htmlBody ?? agentHTML {
            attributedStringBuilder.fromHTML(html)
        } else {
            attributedStringBuilder.fromPlain(messageContent.body)
        }
        
        return .init(body: messageContent.body, formattedBody: formattedBody, formattedBodyHTMLString: htmlBody)
    }
    
    private func buildAudioTimelineItemContent(_ messageContent: AudioMessageContent) -> AudioRoomTimelineItemContent {
        let htmlCaption = messageContent.formattedCaption?.format == .html ? messageContent.formattedCaption?.body : nil
        let formattedCaption = htmlCaption != nil ? attributedStringBuilder.fromHTML(htmlCaption) : attributedStringBuilder.fromPlain(messageContent.caption)
        
        var waveform: EstimatedWaveform?
        if let audioWaveform = messageContent.audio?.waveform {
            waveform = EstimatedWaveform(data: audioWaveform)
        }
        
        return AudioRoomTimelineItemContent(filename: messageContent.filename,
                                            caption: messageContent.caption,
                                            formattedCaption: formattedCaption,
                                            formattedCaptionHTMLString: htmlCaption,
                                            duration: messageContent.audio?.duration ?? 0,
                                            waveform: waveform,
                                            source: MediaSourceProxy(source: messageContent.source, mimeType: messageContent.info?.mimetype),
                                            fileSize: messageContent.info?.size.map(UInt.init),
                                            contentType: UTType(mimeType: messageContent.info?.mimetype, fallbackFilename: messageContent.filename))
    }
    
    private func buildImageTimelineItemContent(_ messageContent: ImageMessageContent) -> ImageRoomTimelineItemContent {
        let htmlCaption = messageContent.formattedCaption?.format == .html ? messageContent.formattedCaption?.body : nil
        let formattedCaption = htmlCaption != nil ? attributedStringBuilder.fromHTML(htmlCaption) : attributedStringBuilder.fromPlain(messageContent.caption)
        
        let thumbnailInfo = ImageInfoProxy(source: messageContent.info?.thumbnailSource,
                                           width: messageContent.info?.thumbnailInfo?.width,
                                           height: messageContent.info?.thumbnailInfo?.height,
                                           mimeType: messageContent.info?.thumbnailInfo?.mimetype,
                                           fileSize: messageContent.info?.size.map(UInt.init))
        
        let imageInfo = ImageInfoProxy(source: messageContent.source,
                                       width: messageContent.info?.width,
                                       height: messageContent.info?.height,
                                       mimeType: messageContent.info?.mimetype,
                                       fileSize: messageContent.info?.size.map(UInt.init))
        
        return .init(filename: messageContent.filename,
                     caption: messageContent.caption,
                     formattedCaption: formattedCaption,
                     formattedCaptionHTMLString: htmlCaption,
                     imageInfo: imageInfo,
                     thumbnailInfo: thumbnailInfo,
                     blurhash: messageContent.info?.blurhash,
                     contentType: UTType(mimeType: messageContent.info?.mimetype, fallbackFilename: messageContent.filename))
    }
    
    private func buildVideoTimelineItemContent(_ messageContent: VideoMessageContent) -> VideoRoomTimelineItemContent {
        let htmlCaption = messageContent.formattedCaption?.format == .html ? messageContent.formattedCaption?.body : nil
        let formattedCaption = htmlCaption != nil ? attributedStringBuilder.fromHTML(htmlCaption) : attributedStringBuilder.fromPlain(messageContent.caption)
        
        let thumbnailInfo = ImageInfoProxy(source: messageContent.info?.thumbnailSource,
                                           width: messageContent.info?.thumbnailInfo?.width,
                                           height: messageContent.info?.thumbnailInfo?.height,
                                           mimeType: messageContent.info?.thumbnailInfo?.mimetype,
                                           fileSize: messageContent.info?.size.map(UInt.init))
        
        let videoInfo = VideoInfoProxy(source: messageContent.source,
                                       duration: messageContent.info?.duration ?? 0,
                                       width: messageContent.info?.width,
                                       height: messageContent.info?.height,
                                       mimeType: messageContent.info?.mimetype,
                                       fileSize: messageContent.info?.size.map(UInt.init))
        
        return .init(filename: messageContent.filename,
                     caption: messageContent.caption,
                     formattedCaption: formattedCaption,
                     formattedCaptionHTMLString: htmlCaption,
                     videoInfo: videoInfo,
                     thumbnailInfo: thumbnailInfo,
                     blurhash: messageContent.info?.blurhash,
                     contentType: UTType(mimeType: messageContent.info?.mimetype, fallbackFilename: messageContent.filename))
    }
    
    private func buildLocationTimelineItemContent(_ locationContent: LocationContent) -> LocationRoomTimelineItemContent {
        LocationRoomTimelineItemContent(body: locationContent.body,
                                        geoURI: .init(string: locationContent.geoUri),
                                        kind: .init(from: locationContent.asset))
    }
    
    private func buildFileTimelineItemContent(_ messageContent: FileMessageContent) -> FileRoomTimelineItemContent {
        let htmlCaption = messageContent.formattedCaption?.format == .html ? messageContent.formattedCaption?.body : nil
        let formattedCaption = htmlCaption != nil ? attributedStringBuilder.fromHTML(htmlCaption) : attributedStringBuilder.fromPlain(messageContent.caption)
        
        let thumbnailSource = messageContent.info?.thumbnailSource.map { MediaSourceProxy(source: $0, mimeType: messageContent.info?.thumbnailInfo?.mimetype) }
        
        return .init(filename: messageContent.filename,
                     caption: messageContent.caption,
                     formattedCaption: formattedCaption,
                     formattedCaptionHTMLString: htmlCaption,
                     source: MediaSourceProxy(source: messageContent.source, mimeType: messageContent.info?.mimetype),
                     fileSize: messageContent.info?.size.map(UInt.init),
                     thumbnailSource: thumbnailSource,
                     contentType: UTType(mimeType: messageContent.info?.mimetype, fallbackFilename: messageContent.filename))
    }
    
    private func buildNoticeTimelineItemContent(_ messageContent: NoticeMessageContent) -> NoticeRoomTimelineItemContent {
        let htmlBody = messageContent.formatted?.format == .html ? messageContent.formatted?.body : nil
        let formattedBody = (htmlBody != nil ? attributedStringBuilder.fromHTML(htmlBody) : attributedStringBuilder.fromPlain(messageContent.body))
        
        return .init(body: messageContent.body, formattedBody: formattedBody)
    }
    
    private func buildEmoteTimelineItemContent(senderDisplayName: String?, senderID: String, messageContent: EmoteMessageContent) -> EmoteRoomTimelineItemContent {
        let name = senderDisplayName ?? senderID
        
        let htmlBody = messageContent.formatted?.format == .html ? messageContent.formatted?.body : nil
        
        var formattedBody: AttributedString?
        if let htmlBody {
            formattedBody = buildEmoteFormattedBodyFromHTML(html: htmlBody, name: name)
        } else {
            formattedBody = attributedStringBuilder.fromPlain(L10n.commonEmote(name, messageContent.body))
        }
        
        return .init(body: messageContent.body, formattedBody: formattedBody, formattedBodyHTMLString: htmlBody)
    }
    
    /// This fixes the issue of the name not belonging to the first <p> defined paragraph
    private func buildEmoteFormattedBodyFromHTML(html: String, name: String) -> AttributedString? {
        let htmlBodyPlaceholder = "{htmlBodyPlaceholder}"
        var finalString = AttributedString(L10n.commonEmote(name, htmlBodyPlaceholder))
        guard let htmlBodyString = attributedStringBuilder.fromHTML(html) else {
            return nil
        }
        finalString.replace(htmlBodyPlaceholder, with: htmlBodyString)
        return finalString
    }
    
    // MARK: - EventBasedTimelineItem Properties
    
    private func buildAggregatedReactions(_ reactions: [Reaction]) -> [AggregatedReaction] {
        reactions.map { reaction in
            let senders = reaction.senders
                .map { senderData in
                    ReactionSender(id: senderData.senderId, timestamp: Date(timeIntervalSince1970: TimeInterval(senderData.timestamp / 1000)))
                }
                .sorted { a, b in
                    // Sort reactions within an aggregation by timestamp descending.
                    // This puts the most recent at the top, useful in cases like the
                    // reaction summary view.
                    a.timestamp > b.timestamp
                }
            return AggregatedReaction(accountOwnerID: userID, key: reaction.key, senders: senders)
        }
        .sorted { a, b in
            // Sort aggregated reactions by count and then timestamp ascending, using
            // the most recent reaction in the aggregation(hence index 0).
            // This appends new aggregations on the end of the reaction layout
            // and the deterministic sort avoids reactions jumping around if the reactions timeline
            // view reloads.
            if a.count == b.count {
                return a.senders[0].timestamp < b.senders[0].timestamp
            }
            return a.count > b.count
        }
    }
    
    private func buildEncryptionAuthenticity(_ shieldState: ShieldState?) -> EncryptionAuthenticity? {
        shieldState.flatMap(EncryptionAuthenticity.init)
    }
    
    private func buildTimelineItemThreadSummary(_ threadSummary: MatrixRustSDK.ThreadSummary?) -> TimelineItemThreadSummary? {
        guard let threadSummary else { return nil }
        // AGENT-PLATFORM (S4): opening a thread makes the SDK store an empty summary for its root, which
        // rendered as a loading placeholder forever. A thread with no replies has nothing to summarise.
        guard threadSummary.numReplies() > 0 else { return nil }
        
        switch threadSummary.latestEvent() {
        case .unavailable:
            return .notLoaded
        case .pending:
            return .loading
        case .ready(let content, let senderID, let senderProfile, _, _):
            let sender = TimelineItemSender(senderID: senderID, senderProfile: senderProfile)
            
            let latestEventContent: TimelineEventContent = switch content {
            case .msgLike(let messageLikeContent):
                switch messageLikeContent.kind {
                case .message(let messageContent):
                    buildEventContent(messageType: messageContent.msgType,
                                      senderID: senderID,
                                      senderDisplayName: sender.displayName)
                case .poll(let question, _, _, _, _, _, _):
                    .poll(question: question)
                case .sticker(let body, _, _):
                    .message(.text(.init(body: body)))
                case .redacted:
                    .redacted
                default:
                    .message(.text(.init(body: L10n.commonUnsupportedEvent)))
                }
            default:
                .message(.text(.init(body: L10n.commonUnsupportedEvent)))
            }
            
            return .loaded(senderID: senderID,
                           sender: sender,
                           latestEventContent: latestEventContent,
                           numberOfReplies: Int(threadSummary.numReplies()))
            
        case .error(let message):
            return .error(message: message)
        }
    }
    
    // MARK: - Other Events
    
    private func buildUnsupportedTimelineItem(_ eventItemProxy: EventTimelineItemProxy,
                                              _ eventType: String,
                                              _ error: String,
                                              _ isOutgoing: Bool) -> RoomTimelineItemProtocol {
        UnsupportedRoomTimelineItem(id: eventItemProxy.id,
                                    body: L10n.commonUnsupportedEvent,
                                    eventType: eventType,
                                    error: error,
                                    timestamp: eventItemProxy.timestamp,
                                    isOutgoing: isOutgoing,
                                    isEditable: eventItemProxy.isEditable,
                                    canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                    sender: eventItemProxy.sender,
                                    properties: .init())
    }
    
    private func buildCallInviteTimelineItem(for eventItemProxy: EventTimelineItemProxy) -> RoomTimelineItemProtocol {
        CallInviteRoomTimelineItem(id: eventItemProxy.id,
                                   timestamp: eventItemProxy.timestamp,
                                   isEditable: eventItemProxy.isEditable,
                                   canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                                   sender: eventItemProxy.sender)
    }
    
    // AGENT-PLATFORM (Brief 0063 G11/G12; decisions 171/172): a tombstoned
    // ring classifies from the SDK's `RtcCallOutcome`, which it computes from
    // every call membership by server time, whatever order the timeline
    // loaded in. The app applies no ring window of its own.
    private func buildCallNotificationTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                                   isDM: Bool,
                                                   callIntent: String?,
                                                   declinedBy: [String],
                                                   activeMembers: [String],
                                                   isJoined: Bool,
                                                   notificationType: String?,
                                                   outcome: RtcCallOutcome) -> RoomTimelineItemProtocol {
        let isVoiceCall = callIntent == CallIntent.audio.rawValue
        let isOutgoing = eventItemProxy.sender.id == userID

        let callState: CallNotificationRoomTimelineItem.CallState
        if activeMembers.count > 0 {
            callState = .active(activeMembers: activeMembers,
                                isJoined: isJoined,
                                callStartTimestamp: Self.activeCallStart(outcome, isDM: isDM))
        } else if isDM {
            callState = .tombstoned(outcome: dmCallOutcome(outcome,
                                                           isOutgoing: isOutgoing,
                                                           declinedBy: declinedBy,
                                                           isRing: notificationType == "ring"))
        } else {
            callState = .tombstoned(outcome: groupCallOutcome(outcome, isOutgoing: isOutgoing, declinedBy: declinedBy))
        }

        return CallNotificationRoomTimelineItem(id: eventItemProxy.id,
                                                timestamp: eventItemProxy.timestamp,
                                                sender: eventItemProxy.sender,
                                                isDM: isDM,
                                                isVoiceCall: isVoiceCall,
                                                callState: callState,
                                                isOutgoing: isOutgoing)
    }

    // MARK: - State Events
    
    private func buildStateTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        state: OtherState,
                                        isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        guard let text = stateEventStringBuilder.buildString(for: state,
                                                             sender: eventItemProxy.sender,
                                                             isOutgoing: isOutgoing,
                                                             rawEventJSON: eventItemProxy.debugInfo.originalJSON) else { return nil }
        // AGENT-PLATFORM: a fold names a run of tool changes.
        var isAgentToolChange = false
        if case .custom(let eventType) = state {
            isAgentToolChange = eventType == SpiralToolsStateReader.eventType
        }
        return buildStateTimelineItem(for: eventItemProxy,
                                      text: text,
                                      isOutgoing: isOutgoing,
                                      isAgentToolChange: isAgentToolChange,
                                      isAgentToolChangeByYou: isAgentToolChange && isAgentToolChangeByYou(eventItemProxy))
    }
    
    private func buildStateMembershipChangeTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                                        memberUserID: String,
                                                        memberDisplayName: String?,
                                                        membershipChange: MembershipChange?,
                                                        reason: String?,
                                                        isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        guard let text = stateEventStringBuilder.buildString(for: membershipChange,
                                                             reason: reason,
                                                             memberUserID: memberUserID,
                                                             memberDisplayName: memberDisplayName,
                                                             sender: eventItemProxy.sender,
                                                             isOutgoing: isOutgoing) else {
            return nil
        }
        
        return buildStateTimelineItem(for: eventItemProxy, text: text, isOutgoing: isOutgoing)
    }
    
    private func buildStateProfileChangeTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                                     displayName: String?,
                                                     previousDisplayName: String?,
                                                     avatarURLString: String?,
                                                     previousAvatarURLString: String?,
                                                     isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        guard let text = stateEventStringBuilder.buildProfileChangeString(displayName: displayName,
                                                                          previousDisplayName: previousDisplayName,
                                                                          avatarURLString: avatarURLString,
                                                                          previousAvatarURLString: previousAvatarURLString,
                                                                          memberID: eventItemProxy.sender.id,
                                                                          memberDisplayName: eventItemProxy.sender.disambiguatedDisplayName ?? eventItemProxy.sender.id,
                                                                          memberIsYou: isOutgoing) else { return nil }
        return buildStateTimelineItem(for: eventItemProxy, text: text, isOutgoing: isOutgoing)
    }
    
    private func buildStateTimelineItem(for eventItemProxy: EventTimelineItemProxy,
                                        text: String,
                                        isOutgoing: Bool,
                                        isAgentToolChange: Bool = false,
                                        isAgentToolChangeByYou: Bool = false) -> RoomTimelineItemProtocol {
        StateRoomTimelineItem(id: eventItemProxy.id,
                              body: text,
                              timestamp: eventItemProxy.timestamp,
                              isOutgoing: isOutgoing,
                              isEditable: false,
                              canBeRepliedTo: eventItemProxy.canBeRepliedTo,
                              sender: eventItemProxy.sender,
                              isAgentToolChange: isAgentToolChange,
                              isAgentToolChangeByYou: isAgentToolChangeByYou)
    }
    
    // MARK: - Reply details
    
    private func buildTimelineItemReplyDetails(_ details: MatrixRustSDK.InReplyToDetails?) -> TimelineItemReplyDetails? {
        guard let details else {
            return nil
        }
        
        return buildTimelineItemReply(details).details
    }
}

private nonisolated extension EmbeddedEventDetails {
    var isThreaded: Bool {
        switch self {
        case .ready(.msgLike(let messageLikeContent), _, _, _, _):
            return messageLikeContent.threadRoot != nil
        default:
            return false
        }
    }
}

nonisolated extension ReadReceipt {
    /// An event's receipts, ordered from newest to oldest.
    static func ordered(_ receipts: [String: Receipt]) -> [ReadReceipt] {
        receipts
            .sorted { firstElement, secondElement in
                // If there is no timestamp we order them as last
                let firstTimestamp = firstElement.value.dateTimestamp ?? Date(timeIntervalSince1970: 0)
                let secondTimestamp = secondElement.value.dateTimestamp ?? Date(timeIntervalSince1970: 0)
                return firstTimestamp > secondTimestamp
            }
            .map { key, receipt in
                ReadReceipt(userID: key, formattedTimestamp: receipt.dateTimestamp?.formattedMinimal())
            }
    }
}

private nonisolated extension Receipt {
    var dateTimestamp: Date? {
        guard let timestamp else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(timestamp / 1000))
    }
}

// AGENT-PLATFORM (decisions 171/172): how an ended call tile resolves.
nonisolated extension RoomTimelineItemFactory {
    /// A DM call is answered when the callee joined before it ended. That
    /// includes a join after the SDK's answer window: a CallKit answer
    /// tapped at the end of the app's 30 s ring publishes its membership a
    /// second or two later, and the call really happened.
    private func dmCallOutcome(_ outcome: RtcCallOutcome,
                               isOutgoing: Bool,
                               declinedBy: [String],
                               isRing: Bool) -> CallNotificationRoomTimelineItem.TombstonedOutcome {
        if !declinedBy.isEmpty {
            return .declined(byMe: declinedBy.contains(userID))
        }

        // `firstJoinedTsMillis` is only ever someone other than the sender.
        let calleeJoinedBeforeEnd = switch (outcome.firstJoinedTsMillis, outcome.endedTsMillis) {
        case let (joined?, ended?): joined < ended
        case (.some, nil): true
        case (nil, _): false
        }
        if !outcome.answeredBy.isEmpty || calleeJoinedBeforeEnd {
            return .answered(duration: Self.callLength(from: outcome.answeredTsMillis ?? outcome.firstJoinedTsMillis,
                                                       to: outcome.endedTsMillis))
        }

        guard isRing else { return .unclassified }
        // The caller missed nothing: their own unanswered ring was cancelled.
        return isOutgoing ? .cancelled : .missed
    }

    /// A group call describes the call, not an answer: no ring window, no
    /// direction. Its length runs from the first join by someone other than
    /// the starter. A call nobody else joined keeps the decline or the plain
    /// ended tile.
    private func groupCallOutcome(_ outcome: RtcCallOutcome,
                                  isOutgoing: Bool,
                                  declinedBy: [String]) -> CallNotificationRoomTimelineItem.TombstonedOutcome {
        if let firstJoined = outcome.firstJoinedTsMillis {
            // The SDK sees only loaded joins; the starter's membership, sent
            // just before the ring, may not be loaded, yet they were in it.
            return .groupCall(duration: Self.callLength(from: firstJoined, to: outcome.endedTsMillis),
                              ownUserJoined: outcome.ownUserJoined || isOutgoing)
        }
        return declinedBy.isEmpty ? .unclassified : .declined(byMe: declinedBy.contains(userID))
    }

    /// A running call's timer starts at the answer, as the call bar's does,
    /// and the same way the ended tile measures its length: in a DM the
    /// answer (or the callee's join), in a group the first join by someone
    /// other than the starter. A call still ringing has no timer.
    private static func activeCallStart(_ outcome: RtcCallOutcome, isDM: Bool) -> Date? {
        let startMillis = isDM ? outcome.answeredTsMillis ?? outcome.firstJoinedTsMillis : outcome.firstJoinedTsMillis
        return startMillis.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    /// No length when either end is unknown; the ring time never counts.
    private static func callLength(from startMillis: UInt64?, to endMillis: UInt64?) -> TimeInterval? {
        guard let startMillis, let endMillis else { return nil }
        return TimeInterval(endMillis > startMillis ? endMillis - startMillis : 0) / 1000
    }
}

// AGENT-PLATFORM: the agent-tools rows, kept apart from upstream's body.
private extension RoomTimelineItemFactory {
    // AGENT-PLATFORM (Brief 0066 § 5.89)
    func buildSpiralToolsFallbackTimelineItem(for eventItemProxy: EventTimelineItemProxy, isOutgoing: Bool) -> RoomTimelineItemProtocol? {
        guard let rawEventJSON = eventItemProxy.debugInfo.originalJSON,
              let text = stateEventStringBuilder.buildSpiralToolsFallbackString(rawEventJSON: rawEventJSON,
                                                                                sender: eventItemProxy.sender) else {
            return nil
        }
        return buildStateTimelineItem(for: eventItemProxy,
                                      text: text,
                                      isOutgoing: isOutgoing,
                                      isAgentToolChangeByYou: isAgentToolChangeByYou(eventItemProxy))
    }

    func isAgentToolChangeByYou(_ eventItemProxy: EventTimelineItemProxy) -> Bool {
        guard let rawEventJSON = eventItemProxy.debugInfo.originalJSON else { return false }
        return stateEventStringBuilder.isSpiralToolsEventByYou(rawEventJSON: rawEventJSON, sender: eventItemProxy.sender)
    }
}
