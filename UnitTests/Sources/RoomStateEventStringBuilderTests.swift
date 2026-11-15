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
                                                            memberID: sender.id,
                                                            memberDisplayName: sender.disambiguatedDisplayName ?? sender.id,
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
        // The SDK only includes the display name when it changed, so it is nil for an avatar-only change.
        let sender = TimelineItemSender(id: senderID, displayName: senderName)
        let string = stringBuilder.buildProfileChangeString(displayName: nil,
                                                            previousDisplayName: nil,
                                                            avatarURLString: newAvatarURL,
                                                            previousAvatarURLString: oldAvatarURL,
                                                            memberID: sender.id,
                                                            memberDisplayName: sender.disambiguatedDisplayName ?? sender.id,
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

    // MARK: - AGENT-PLATFORM (question 357): com.spiral.tools rows read the event's `changes`
    
    private static let recording = #"{"tool_id":"t1","tool":"call_recording","trigger":"on_voice_call","enabled":true}"#
    private static let toUkrainian = #"{"tool_id":"t2","tool":"translate","trigger":"on_message","enabled":true,"target_language":"uk"}"#
    
    private static func change(_ action: String, tool: String = "call_recording", language: String? = nil, actor: String = "owner", previous: String? = nil) -> String {
        var fields = [#""action":"\#(action)""#, #""tool":"\#(tool)""#, #""trigger":"on_message""#, #""actor":"\#(actor)""#]
        if let language { fields.append(#""target_language":"\#(language)""#) }
        if let previous { fields.append(#""previous":{"tool":"\#(tool)","trigger":"on_message","target_language":"\#(previous)"}"#) }
        return "{\(fields.joined(separator: ","))}"
    }
    
    /// `changes` is the JSON after the key, or nil for an event without one.
    private static func spiralContent(by: String, tools: String, changes: String?) -> String {
        let list = changes.map { #","changes":\#($0)"# } ?? ""
        return #"{"version":1,"by":"\#(by)","at":1000,"tools":\#(tools)\#(list)}"#
    }
    
    private func spiralRow(agent: String = "@assistant-bob:matrix.org", by: String = "@bob:matrix.org",
                           tools: String = "[]", changes: [String]) -> String? {
        spiralRow(agent: agent, by: by, tools: tools, rawChanges: "[\(changes.joined(separator: ","))]")
    }
    
    private func spiralRow(agent: String = "@assistant-bob:matrix.org", by: String = "@bob:matrix.org",
                           tools: String = "[]", rawChanges: String?, unsigned: String = "{}") -> String? {
        let json = """
        {"type":"com.spiral.tools","state_key":"\(agent)","sender":"\(agent)",
         "content":\(Self.spiralContent(by: by, tools: tools, changes: rawChanges)),"unsigned":\(unsigned)}
        """
        return stringBuilder.buildString(for: .custom(eventType: "com.spiral.tools"),
                                         sender: TimelineItemSender(id: agent, displayName: "Bob · assistant"),
                                         isOutgoing: false,
                                         rawEventJSON: json)
    }
    
    private func spiralFallbackRow(agent: String = "@assistant-bob:matrix.org", by: String = "@bob:matrix.org",
                                   tools: String = "[]", rawChanges: String?) -> String? {
        let json = """
        {"type":"com.spiral.tools.changed","sender":"\(agent)",
         "content":\(Self.spiralContent(by: by, tools: tools, changes: rawChanges))}
        """
        return stringBuilder.buildSpiralToolsFallbackString(rawEventJSON: json,
                                                            sender: TimelineItemSender(id: agent, displayName: "Bob · assistant"))
    }
    
    private var recordCalls: String {
        UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
    }
    
    private func translate(_ language: String) -> String {
        UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
    }
    
    private func language(_ code: String) -> String {
        TranslationLanguageDisplayName.localizedName(for: code)
    }
    
    @Test
    func spiralToolArmedNamesTheTool() {
        #expect(spiralRow(changes: [Self.change("armed")]) == UntranslatedL10n.stateEventSpiralToolOn("Bob · assistant", recordCalls))
    }
    
    @Test
    func spiralToolDisabledNamesTheTool() {
        let row = spiralRow(changes: [Self.change("disabled", tool: "translate", language: "uk")])
        #expect(row == UntranslatedL10n.stateEventSpiralToolOff("Bob · assistant", translate("uk")))
    }
    
    @Test
    func spiralToolLanguageEditSaysFromAndTo() {
        let row = spiralRow(changes: [Self.change("edited", tool: "translate", language: "en", previous: "uk")])
        #expect(row == UntranslatedL10n.stateEventSpiralToolLanguageChanged("Bob · assistant", language("uk"), language("en")))
    }
    
    @Test
    func spiralToolEditOfSomethingPrivateNamesOnlyTheTool() {
        let row = spiralRow(changes: [Self.change("edited", tool: "translate", language: "uk", previous: "uk")])
        #expect(row == UntranslatedL10n.stateEventSpiralToolChanged("Bob · assistant", translate("uk")))
    }
    
    @Test
    func spiralToolsEachActionTakesItsOwnLineInOrder() {
        let row = spiralRow(changes: [Self.change("disabled", tool: "translate", language: "uk"), Self.change("armed")])
        let expected = [UntranslatedL10n.stateEventSpiralToolOff("Bob · assistant", translate("uk")),
                        UntranslatedL10n.stateEventSpiralToolOn("Bob · assistant", recordCalls)]
        #expect(row?.components(separatedBy: "\n") == expected)
    }
    
    @Test
    func spiralToolsEmptyListHasNoRow() {
        #expect(spiralRow(tools: "[\(Self.recording)]", changes: []) == nil)
    }
    
    @Test
    func spiralToolsOwnAgentSaysYou() {
        let agent = "@assistant-alice:matrix.org"
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("armed")])
            == UntranslatedL10n.stateEventSpiralToolOnByYou(recordCalls))
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("disabled")])
            == UntranslatedL10n.stateEventSpiralToolOffByYou(recordCalls))
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("edited", tool: "translate", language: "en", previous: "uk")])
            == UntranslatedL10n.stateEventSpiralToolLanguageChangedByYou(language("uk"), language("en")))
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("edited", tool: "translate", language: "uk", previous: "uk")])
            == UntranslatedL10n.stateEventSpiralToolChangedByYou(translate("uk")))
    }
    
    @Test
    func spiralToolsForgedOwnerNeverSaysYou() {
        // Anyone at the default level may send this state type once the room grants it.
        let row = spiralRow(agent: "@mallory:matrix.org", by: userID, changes: [Self.change("armed")])
        #expect(row == UntranslatedL10n.stateEventSpiralToolOn("Bob · assistant", recordCalls))
    }
    
    @Test
    func spiralToolsSystemNeverSaysYou() {
        let agent = "@assistant-alice:matrix.org"
        let turnedOff = UntranslatedL10n.stateEventSpiralToolOffBySystem(recordCalls, "Bob · assistant")
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("disabled", actor: "system")]) == turnedOff, "the owner's device")
        #expect(spiralRow(changes: [Self.change("disabled", actor: "system")]) == turnedOff, "anyone else's")
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("armed", actor: "system")])
            == UntranslatedL10n.stateEventSpiralToolOn("Bob · assistant", recordCalls))
        #expect(spiralRow(agent: agent, by: userID, changes: [Self.change("edited", tool: "translate", language: "en", actor: "system", previous: "uk")])
            == UntranslatedL10n.stateEventSpiralToolLanguageChanged("Bob · assistant", language("uk"), language("en")))
    }
    
    @Test
    func spiralToolsActorIsReadPerLine() {
        let row = spiralRow(agent: "@assistant-alice:matrix.org", by: userID,
                            changes: [Self.change("armed"), Self.change("disabled", tool: "translate", language: "uk", actor: "system")])
        let expected = [UntranslatedL10n.stateEventSpiralToolOnByYou(recordCalls),
                        UntranslatedL10n.stateEventSpiralToolOffBySystem(translate("uk"), "Bob · assistant")]
        #expect(row?.components(separatedBy: "\n") == expected)
    }
    
    @Test
    func spiralToolsWithoutChangesKeepTheSnapshot() {
        let tools = "[\(Self.recording),\(Self.toUkrainian)]"
        let snapshot = UntranslatedL10n.stateEventSpiralToolsActive("Bob · assistant", "\(recordCalls) · \(translate("uk"))")
        #expect(spiralRow(tools: tools, rawChanges: nil) == snapshot)
        #expect(spiralRow(tools: tools, rawChanges: nil, unsigned: #"{"replaces_state":"$old","prev_content":{"tools":[]}}"#) == snapshot,
                "the previous state is no longer compared")
    }
    
    @Test
    func spiralToolsUnknownActionOrActorKeepTheSnapshot() {
        let tools = "[\(Self.recording)]"
        let snapshot = UntranslatedL10n.stateEventSpiralToolsActive("Bob · assistant", recordCalls)
        #expect(spiralRow(tools: tools, changes: [Self.change("armed"), Self.change("paused")]) == snapshot)
        #expect(spiralRow(tools: tools, changes: [Self.change("armed", actor: "schedule")]) == snapshot)
        #expect(spiralRow(tools: tools, rawChanges: #""newer""#) == snapshot, "a shape this build can't read is not an empty list")
    }
    
    @Test
    func spiralToolsCallArtifactKindsAreLocalized() {
        // Regression: call_summary / call_recording aren't in ArmToolKind, so
        // the old fallback rendered the raw "Call_summary" tag.
        let row = spiralRow(tools: #"[{"tool":"call_recording","enabled":true},{"tool":"call_summary","enabled":true}]"#, rawChanges: nil)
        let expectedLine = "\(UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle) · \(UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle)"
        #expect(row == UntranslatedL10n.stateEventSpiralToolsActive("Bob · assistant", expectedLine))
        #expect(row?.contains("Call_summary") == false)
        #expect(row?.contains("Call_recording") == false)
        #expect(spiralRow(changes: [Self.change("armed", tool: "call_summary")])
            == UntranslatedL10n.stateEventSpiralToolOn("Bob · assistant", UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle))
    }
    
    @Test
    func spiralToolsEmptySnapshotShowsTurnedOff() {
        #expect(spiralRow(tools: "[]", rawChanges: nil) == UntranslatedL10n.stateEventSpiralToolsOff("Bob · assistant"))
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
        let changes = "[\(Self.change("armed")),\(Self.change("disabled", tool: "translate", language: "uk", actor: "system"))]"
        let row = spiralFallbackRow(rawChanges: changes)
        #expect(row != nil)
        #expect(row == spiralRow(rawChanges: changes))
    }
    
    @Test
    func spiralToolsFallbackSaysYouToTheOwner() {
        #expect(spiralFallbackRow(agent: "@assistant-alice:matrix.org", by: userID, rawChanges: "[\(Self.change("armed"))]")
            == UntranslatedL10n.stateEventSpiralToolOnByYou(recordCalls))
    }
    
    @Test
    func spiralToolsFallbackWithAnEmptyListHasNoRow() {
        #expect(spiralFallbackRow(tools: "[\(Self.recording)]", rawChanges: "[]") == nil)
    }
    
    @Test
    func spiralToolsFallbackWithoutChangesKeepsTheSnapshot() {
        #expect(spiralFallbackRow(tools: "[\(Self.recording)]", rawChanges: nil)
            == UntranslatedL10n.stateEventSpiralToolsActive("Bob · assistant", recordCalls))
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
