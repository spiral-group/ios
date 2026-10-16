//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import MatrixRustSDK
import Testing

struct RoomStateEventStringBuilderTests {
    private let userID: String
    private let stringBuilder: RoomStateEventStringBuilder
    
    init() {
        userID = "@alice:matrix.org"
        stringBuilder = RoomStateEventStringBuilder(userID: userID)
    }
    
    // MARK: - User Profiles
    
    @Test
    func displayNameChanges() {
        // Changes by you.
        validateDisplayNameChange(senderID: userID, oldName: "Alice", newName: "Bob",
                                  expectedString: L10n.stateEventDisplayNameChangedFromByYou("Alice", "Bob"))
        validateDisplayNameChange(senderID: userID, oldName: "Alice", newName: nil,
                                  expectedString: L10n.stateEventDisplayNameRemovedByYou("Alice"))
        validateDisplayNameChange(senderID: userID, oldName: nil, newName: "Alice",
                                  expectedString: L10n.stateEventDisplayNameSetByYou("Alice"))
        
        // Changes by someone else.
        let senderID = "@bob:matrix.org"
        validateDisplayNameChange(senderID: senderID, oldName: "Bob", newName: "Alice",
                                  expectedString: L10n.stateEventDisplayNameChangedFrom(senderID, "Bob", "Alice"))
        validateDisplayNameChange(senderID: senderID, oldName: "Bob", newName: nil,
                                  expectedString: L10n.stateEventDisplayNameRemoved(senderID, "Bob"))
        validateDisplayNameChange(senderID: senderID, oldName: nil, newName: "Bob",
                                  expectedString: L10n.stateEventDisplayNameSet(senderID, "Bob"))
    }
    
    private func validateDisplayNameChange(senderID: String, oldName: String?, newName: String?, expectedString: String) {
        let sender = TimelineItemSender(id: senderID, displayName: newName)
        let string = stringBuilder.buildProfileChangeString(displayName: newName,
                                                            previousDisplayName: oldName,
                                                            avatarURLString: nil,
                                                            previousAvatarURLString: nil,
                                                            member: sender.id,
                                                            memberIsYou: sender.id == userID)
        #expect(string == expectedString)
    }
    
    @Test
    func avatarChanges() {
        // Changes by you.
        validateAvatarChange(senderID: userID, oldAvatarURL: "mxc://1", newAvatarURL: "mxc://2",
                             expectedString: L10n.stateEventAvatarUrlChangedByYou)
        validateAvatarChange(senderID: userID, oldAvatarURL: "mxc://1", newAvatarURL: nil,
                             expectedString: L10n.stateEventAvatarUrlChangedByYou)
        validateAvatarChange(senderID: userID, oldAvatarURL: nil, newAvatarURL: "mxc://1",
                             expectedString: L10n.stateEventAvatarUrlChangedByYou)
        
        // Changes by someone else.
        let senderID = "@bob:matrix.org"
        let senderName = "Bob"
        validateAvatarChange(senderID: senderID, senderName: senderName, oldAvatarURL: "mxc://1", newAvatarURL: "mxc://2",
                             expectedString: L10n.stateEventAvatarUrlChanged(senderName))
        validateAvatarChange(senderID: senderID, senderName: senderName, oldAvatarURL: "mxc://1", newAvatarURL: nil,
                             expectedString: L10n.stateEventAvatarUrlChanged(senderName))
        validateAvatarChange(senderID: senderID, senderName: senderName, oldAvatarURL: nil, newAvatarURL: "mxc://1",
                             expectedString: L10n.stateEventAvatarUrlChanged(senderName))
    }
    
    private func validateAvatarChange(senderID: String, senderName: String? = nil,
                                      oldAvatarURL: String?, newAvatarURL: String?,
                                      expectedString: String) {
        let sender = TimelineItemSender(id: senderID, displayName: senderName)
        let string = stringBuilder.buildProfileChangeString(displayName: senderName,
                                                            previousDisplayName: senderName,
                                                            avatarURLString: newAvatarURL,
                                                            previousAvatarURLString: oldAvatarURL,
                                                            member: sender.id,
                                                            memberIsYou: sender.id == userID)
        #expect(string == expectedString)
    }
    
    // MARK: - Room Info
    
    @Test
    func topicChanges() {
        let you = TimelineItemSender(id: userID, displayName: "Alice")
        let other = TimelineItemSender(id: "@bob:matrix.org", displayName: "Bob")
        
        let newTopic = "New topic"
        var string = stringBuilder.buildString(for: .roomTopic(topic: newTopic), sender: you, isOutgoing: true)
        #expect(string == L10n.stateEventRoomTopicChangedByYou(newTopic))
        string = stringBuilder.buildString(for: .roomTopic(topic: newTopic), sender: other, isOutgoing: false)
        #expect(string == L10n.stateEventRoomTopicChanged(other.displayName ?? "", newTopic))
        
        let emptyTopic = ""
        string = stringBuilder.buildString(for: .roomTopic(topic: emptyTopic), sender: you, isOutgoing: true)
        #expect(string == L10n.stateEventRoomTopicRemovedByYou)
        string = stringBuilder.buildString(for: .roomTopic(topic: emptyTopic), sender: other, isOutgoing: false)
        #expect(string == L10n.stateEventRoomTopicRemoved(other.displayName ?? ""))
        
        string = stringBuilder.buildString(for: .roomTopic(topic: nil), sender: you, isOutgoing: true)
        #expect(string == L10n.stateEventRoomTopicRemovedByYou)
        string = stringBuilder.buildString(for: .roomTopic(topic: nil), sender: other, isOutgoing: false)
        #expect(string == L10n.stateEventRoomTopicRemoved(other.displayName ?? ""))
    }
    
    // MARK: - Room Membership
    
    @Test
    func kickMember() {
        let you = TimelineItemSender(id: userID, displayName: "Alice")
        let other = TimelineItemSender(id: "@bob:matrix.org", displayName: "Bob")
        let banned = TimelineItemSender(id: "@spam:matrix.org", displayName: "I like spam")
        
        let reason = "Spam"
        var string = stringBuilder.buildString(for: .kicked,
                                               reason: reason,
                                               memberUserID: banned.id,
                                               memberDisplayName: banned.displayName,
                                               sender: you,
                                               isOutgoing: true)
        #expect(string == L10n.stateEventRoomRemoveByYouWithReason(banned.displayName ?? banned.id, reason))
        string = stringBuilder.buildString(for: .kicked,
                                           reason: nil,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: you,
                                           isOutgoing: true)
        #expect(string == L10n.stateEventRoomRemoveByYou(banned.displayName ?? banned.id))
        string = stringBuilder.buildString(for: .kicked,
                                           reason: reason,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: other,
                                           isOutgoing: false)
        #expect(string == L10n.stateEventRoomRemoveWithReason(other.displayName ?? other.id, banned.displayName ?? banned.id, reason))
        string = stringBuilder.buildString(for: .kicked,
                                           reason: nil,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: other,
                                           isOutgoing: false)
        #expect(string == L10n.stateEventRoomRemove(other.displayName ?? other.id, banned.displayName ?? banned.id))
    }
    
    @Test
    func banMember() {
        let you = TimelineItemSender(id: userID, displayName: "Alice")
        let other = TimelineItemSender(id: "@bob:matrix.org", displayName: "Bob")
        let banned = TimelineItemSender(id: "@spam:matrix.org", displayName: "I like spam")
        
        let reason = "Spam"
        var string = stringBuilder.buildString(for: .banned,
                                               reason: reason,
                                               memberUserID: banned.id,
                                               memberDisplayName: banned.displayName,
                                               sender: you,
                                               isOutgoing: true)
        #expect(string == L10n.stateEventRoomBanByYouWithReason(banned.displayName ?? banned.id, reason))
        string = stringBuilder.buildString(for: .banned,
                                           reason: nil,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: you,
                                           isOutgoing: true)
        #expect(string == L10n.stateEventRoomBanByYou(banned.displayName ?? banned.id))
        string = stringBuilder.buildString(for: .banned,
                                           reason: reason,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: other,
                                           isOutgoing: false)
        #expect(string == L10n.stateEventRoomBanWithReason(other.displayName ?? other.id, banned.displayName ?? banned.id, reason))
        string = stringBuilder.buildString(for: .banned,
                                           reason: nil,
                                           memberUserID: banned.id,
                                           memberDisplayName: banned.displayName,
                                           sender: other,
                                           isOutgoing: false)
        #expect(string == L10n.stateEventRoomBan(other.displayName ?? other.id, banned.displayName ?? banned.id))
    }

    // MARK: - AGENT-PLATFORM (Brief 0044): detailed com.spiral.tools rows

    private static func spiralEvent(agent: String, tools: String) -> String {
        """
        {"type":"com.spiral.tools","state_key":"\(agent)","sender":"\(agent)",
         "content":{"version":1,"by":"@owner:host","at":1000,"tools":\(tools)}}
        """
    }

    @Test
    func spiralToolsSingleTranslateShowsLanguage() {
        let sender = TimelineItemSender(id: "@assistant-bob:host", displayName: "Bob's Assistant")
        let json = Self.spiralEvent(agent: "@assistant-bob:host",
                                    tools: #"[{"tool":"translate","enabled":true,"target_language":"English"}]"#)
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: json)
        #expect(string == UntranslatedL10n.stateEventSpiralToolsActive("Bob's Assistant",
                                                                       UntranslatedL10n.screenAgentToolsListTitleTranslate("English")))
    }

    @Test
    func spiralToolsSingleNonTranslateShowsKindName() {
        let sender = TimelineItemSender(id: "@assistant-bob:host", displayName: "Bob's Assistant")
        let json = Self.spiralEvent(agent: "@assistant-bob:host",
                                    tools: #"[{"tool":"summarize","enabled":true}]"#)
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: json)
        #expect(string == UntranslatedL10n.stateEventSpiralToolsActive("Bob's Assistant", ToolDisplayName.name(forKind: "summarize")))
    }

    @Test
    func spiralToolsCallArtifactKindsAreLocalized() {
        // Regression: call_summary / call_recording aren't in ArmToolKind, so
        // the old fallback rendered the raw "Call_summary" tag. They must now
        // show their localized capability titles.
        let sender = TimelineItemSender(id: "@assistant-red:host", displayName: "Red's Assistant")
        let json = Self.spiralEvent(agent: "@assistant-red:host",
                                    tools: #"[{"tool":"call_recording","enabled":true},{"tool":"call_summary","enabled":true}]"#)
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: json)
        let expectedLine = "\(UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle) · \(UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle)"
        #expect(string == UntranslatedL10n.stateEventSpiralToolsActive("Red's Assistant", expectedLine))
        // And never the raw kind tag.
        #expect(string?.contains("Call_summary") == false)
        #expect(string?.contains("Call_recording") == false)
    }

    @Test
    func spiralToolsMultipleListsEveryTool() {
        // The event is a full snapshot, so the row must list ALL current tools
        // (no "+N" hiding the rest) so the user sees exactly what's active.
        let sender = TimelineItemSender(id: "@assistant-bob:host", displayName: "Bob's Assistant")
        let json = Self.spiralEvent(agent: "@assistant-bob:host",
                                    tools: #"[{"tool":"translate","enabled":true,"target_language":"English"},{"tool":"summarize","enabled":true}]"#)
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: json)
        let translateText = UntranslatedL10n.screenAgentToolsListTitleTranslate("English")
        let expectedLine = "\(translateText) · \(ToolDisplayName.name(forKind: "summarize"))"
        #expect(string == UntranslatedL10n.stateEventSpiralToolsActive("Bob's Assistant", expectedLine))
    }

    @Test
    func spiralToolsEmptyShowsTurnedOff() {
        let sender = TimelineItemSender(id: "@assistant-bob:host", displayName: "Bob's Assistant")
        let json = Self.spiralEvent(agent: "@assistant-bob:host", tools: "[]")
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: json)
        #expect(string == UntranslatedL10n.stateEventSpiralToolsOff("Bob's Assistant"))
    }

    @Test
    func spiralToolsWithoutJSONFallsBackToGeneric() {
        let sender = TimelineItemSender(id: "@assistant-bob:host", displayName: "Bob's Assistant")
        let string = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                               sender: sender, isOutgoing: false, rawEventJSON: nil)
        #expect(string == UntranslatedL10n.stateEventSpiralToolsUpdated("Bob's Assistant"))
    }

    // MARK: - AGENT-PLATFORM (Brief 0066 § 5.89): the fallback reads as the state row

    @Test
    func spiralToolsFallbackReadsLikeTheStateRow() {
        let agent = "@assistant-bob:matrix.org"
        let sender = TimelineItemSender(id: agent, displayName: "Bob's Assistant")
        let tools = #"[{"tool":"translate","enabled":true,"target_language":"English"}]"#
        let fallback = """
        {"type":"com.spiral.tools.changed","sender":"\(agent)",
         "content":{"version":1,"by":"@bob:matrix.org","at":1000,"tools":\(tools),"fallback":true}}
        """

        let row = stringBuilder.buildSpiralToolsFallbackString(rawEventJSON: fallback, sender: sender)
        let stateRow = stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                                 sender: sender, isOutgoing: false,
                                                 rawEventJSON: Self.spiralEvent(agent: agent, tools: tools))

        #expect(row != nil)
        #expect(row == stateRow)
    }

    @Test
    func spiralToolsFallbackFromAPersonHasNoRow() {
        let person = "@mallory:matrix.org"
        let fallback = """
        {"type":"com.spiral.tools.changed","sender":"\(person)",
         "content":{"version":1,"by":"\(person)","at":1000,"tools":[{"tool":"translate","enabled":true}],"fallback":true}}
        """
        #expect(stringBuilder.buildSpiralToolsFallbackString(rawEventJSON: fallback,
                                                             sender: TimelineItemSender(id: person)) == nil)
    }
}
