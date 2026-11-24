//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK
@testable import Spiral
import Testing

struct RoomEventStringBuilderTests {
    private let ownUserID: String
    private let stringBuilder: RoomEventStringBuilder
    
    init() {
        ownUserID = "@alice:matrix.org"
        let stateEventStringBuilder = RoomStateEventStringBuilder(userID: ownUserID)
        let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
        
        stringBuilder = RoomEventStringBuilder(stateEventStringBuilder: stateEventStringBuilder,
                                               messageEventStringBuilder: RoomMessageEventStringBuilder(attributedStringBuilder: attributedStringBuilder,
                                                                                                        style: .senderPrefixed),
                                               shouldPrefixSenderName: true)
    }
    
    @Test
    func senderPrefix() {
        let ownMessageString = stringBuilder.buildAttributedString(for: makeMessageItem(senderID: ownUserID, senderDisplayName: "Alice"))
        #expect(ownMessageString?.string == "You: Hello, World!", "Your own messages should be prefixed with 'You'")
        
        let otherMessageString = stringBuilder.buildAttributedString(for: makeMessageItem(senderID: "@bob:matrix.org", senderDisplayName: "Bob"))
        #expect(otherMessageString?.string == "Bob: Hello, World!", "Everyone else's messages should be prefixed with their display name.")
        
        let ambiguousMessageString = stringBuilder.buildAttributedString(for: makeMessageItem(senderID: "@charlie:matrix.org",
                                                                                              senderDisplayName: "Charlie",
                                                                                              senderDisplayNameAmbiguous: true))
        #expect(ambiguousMessageString?.string == "Charlie (@charlie:matrix.org): Hello, World!",
                "Messages from senders with ambiguous display names should include their user ID in the prefix.")
        
        let ownEmoteString = stringBuilder.buildAttributedString(for: makeMessageItem(senderID: ownUserID,
                                                                                      senderDisplayName: "Alice",
                                                                                      type: .emote,
                                                                                      message: "laughs"))
        #expect(ownEmoteString?.string == "* Alice laughs", "Your own emotes shouldn't contain 'You'")
        
        let otherEmoteString = stringBuilder.buildAttributedString(for: makeMessageItem(senderID: "@bob:matrix.org",
                                                                                        senderDisplayName: "Bob",
                                                                                        type: .emote,
                                                                                        message: "sighs"))
        #expect(otherEmoteString?.string == "* Bob sighs", "Everyone else's emotes should contain their display name.")
        
        let ownPollString = stringBuilder.buildAttributedString(for: makePollItem(senderID: ownUserID, senderDisplayName: "Alice"))
        #expect(ownPollString?.string == "You: Poll: Which is better?", "Your own polls should be prefixed with 'You'")
        
        let otherPollString = stringBuilder.buildAttributedString(for: makePollItem(senderID: "@bob:matrix.org", senderDisplayName: "Bob"))
        #expect(otherPollString?.string == "Bob: Poll: Which is better?", "Everyone else's polls should be prefixed with their display name.")
    }
    
    // MARK: - Helpers
    
    private enum MockMessageType { case textMessage, emote }
    
    private func makeMessageItem(senderID: String,
                                 senderDisplayName: String? = nil,
                                 senderDisplayNameAmbiguous: Bool = false,
                                 type: MockMessageType = .textMessage,
                                 message: String = "Hello, World!") -> EventTimelineItemProxy {
        let content = switch type {
        case .textMessage: makeTextContent(message: message)
        case .emote: makeEmoteContent(message: message)
        }
        
        return .init(item: .init(configuration: .init(eventID: "1234",
                                                      sender: senderID,
                                                      senderProfile: .ready(displayName: senderDisplayName,
                                                                            displayNameAmbiguous: senderDisplayNameAmbiguous,
                                                                            avatarUrl: nil,
                                                                            status: nil,
                                                                            call: nil),
                                                      isOwn: senderID == ownUserID,
                                                      content: .msgLike(content: .init(kind: .message(content: .init(msgType: content,
                                                                                                                     body: message,
                                                                                                                     isEdited: false,
                                                                                                                     mentions: nil)),
                                                                                       inReplyTo: nil,
                                                                                       threadRoot: nil,
                                                                                       threadSummary: nil)))),
                     uniqueID: .init("0"))
    }
    
    private func makeTextContent(message: String) -> MessageType {
        .text(content: .init(body: message, formatted: nil))
    }
    
    private func makeEmoteContent(message: String) -> MessageType {
        .emote(content: .init(body: message, formatted: nil))
    }
    
    private func makePollItem(senderID: String,
                              senderDisplayName: String? = nil,
                              senderDisplayNameAmbiguous: Bool = false,
                              question: String = "Which is better?") -> EventTimelineItemProxy {
        .init(item: .init(configuration: .init(eventID: "1234",
                                               sender: senderID,
                                               senderProfile: .ready(displayName: senderDisplayName,
                                                                     displayNameAmbiguous: senderDisplayNameAmbiguous,
                                                                     avatarUrl: nil,
                                                                     status: nil,
                                                                     call: nil),
                                               isOwn: senderID == ownUserID,
                                               content: .msgLike(content: .init(kind: .poll(question: question,
                                                                                            kind: .disclosed,
                                                                                            maxSelections: 1,
                                                                                            answers: [],
                                                                                            votes: [:],
                                                                                            endTime: nil,
                                                                                            hasBeenEdited: false),
                                                                                inReplyTo: nil,
                                                                                threadRoot: nil,
                                                                                threadSummary: nil)))),
              uniqueID: .init("0"))
    }
}

// AGENT-PLATFORM: the chat list's last-message line.
extension RoomEventStringBuilderTests {
    /// Only an agent's notice reads as a Spiral notice, as in the timeline: a member sending the same
    /// msgtype gets its plain body, so nobody can fake a «sign-in phrase changed» line in the chat list.
    @Test
    func aNoticePreviewsAsANoticeOnlyFromAnAgent() throws {
        let notice = try #require(SpiralNotice(msgtype: SpiralNotice.msgtype, data: #"{"com.spiral.notice":{"kind":"phrase_changed","device_name":"iPhone"}}"#))
        
        let fromAgent = EventTimelineItemProxy(item: .mockSpiralNotice(sender: "@assistant-bob:spiral.md"), uniqueID: .init("0"))
        #expect(stringBuilder.buildAttributedString(for: fromAgent)?.string.hasSuffix(": \(notice.plainText)") == true)
        
        let fromPerson = EventTimelineItemProxy(item: .mockSpiralNotice(sender: "@mallory:spiral.md"), uniqueID: .init("1"))
        let line = try #require(stringBuilder.buildAttributedString(for: fromPerson)?.string)
        #expect(line.hasSuffix(": fallback"))
        #expect(!line.contains(notice.plainText))
    }
    
    /// A template's post previews under the title its card shows, in the reader's language.
    @Test
    func aTemplatePostPreviewsUnderTheReadersTitle() {
        let builder = RoomMessageEventStringBuilder(attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                    style: .plain,
                                                    templateTitle: { $0 == "tpl-tug-of-war" ? "Tug of war" : nil })
        func line(appID: String) -> String {
            let post = InteractivePostContent(body: "", appId: appID, runtime: "1", title: "Перетягування каната", aspect: "1:1",
                                              stateChannel: "matrix", sha256: String(repeating: "a", count: 64),
                                              url: "mxc://spiral.md/abc", fileJson: nil)
            return String(builder.buildAttributedString(for: .interactivePost(content: post), senderID: "@bob:spiral.md",
                                                        senderDisplayName: "Bob", isOutgoing: false).characters)
        }
        
        #expect(line(appID: "tpl-tug-of-war").hasSuffix("Tug of war"))
        #expect(line(appID: "a1b2c3").hasSuffix("Перетягування каната"), "an agent's own post keeps its stored title")
    }
}
