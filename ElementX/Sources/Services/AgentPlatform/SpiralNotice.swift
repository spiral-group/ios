//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: client-rendered notices (Brief 0073).
//
// The server knows what happened; this client knows the reader's
// language. A notice is an `m.room.message` with `msgtype`
// `com.spiral.notice`, a plain English `body` for clients that do not
// know the type, and the facts under the `com.spiral.notice` key:
// `{"kind": "referral_joined", "joined_user_id": "@x:spiral.md"}`.
// The Rust SDK fork hands it over as `.other(msgtype, body, data)` with
// `data` the extra keys as JSON; the words are chosen here.
//

import Foundation

nonisolated struct SpiralNotice: Equatable {
    static let msgtype = "com.spiral.notice"
    private static let key = "com.spiral.notice"
    
    enum Kind: Equatable {
        /// Someone registered through the reader's invite link; their name as
        /// the server saw it at notice time (older notices carry none).
        case referralJoined(joinedUserID: String, joinedDisplayName: String?)
        /// The assistant greets its owner once they accepted the DM.
        case welcome(ownerDisplayName: String, agentDisplayName: String, behavior: String)
        /// The account phrase was replaced from a signed-in device (Brief 0075);
        /// the device's name when the server could read it.
        case phraseChanged(deviceName: String?)
        /// The agent could not answer the last message (ADR-0086).
        case replyFailed
        /// The automatic content check held the agent's reply back (coverage walk
        /// F7); resending meets the same check, so the card doesn't ask for it.
        case replyWithheld
        /// The agent spent today's AI budget; it answers again at `resetsAt`
        /// (Brief 0079). Posted once a day in the owner's DM.
        case aiBudgetReached(resetsAt: Date)
        /// To a first-contact visitor: their message went to the agent's owner.
        /// `greeting` only when the owner wrote one (Brief 0079 B1).
        case messagePassedToOwner(ownerDisplayName: String, greeting: String?)
        /// The assistant suggests meeting another agent's person (Brief 0004);
        /// the model's words as data, the labels ours.
        case introSuggestion(candidateAgentID: String, summary: String, suggestedOpener: String)
        /// The call room refused the summary / recording; it follows here.
        case summaryMovedToDM(roomID: String)
        case recordingMovedToDM(roomID: String)
        /// In the owner DM: a note the assistant brings from another conversation
        /// (`messenger.dm_owner`, decision 38) — the model's words, whose message
        /// it was answering and where.
        case relayedToOwner(note: String, fromUserID: String, roomID: String)
        /// To a person who has not allowed third-party AI and wrote to an
        /// assistant (decision 150): nothing they write reaches it until they do.
        case aiConsentNeeded(agentDisplayName: String)
        
        /// The wire name of the kind, for the card's accessibility identifier.
        var wireName: String {
            switch self {
            case .referralJoined: "referral_joined"
            case .welcome: "welcome"
            case .phraseChanged: "phrase_changed"
            case .replyFailed: "reply_failed"
            case .replyWithheld: "reply_withheld"
            case .aiBudgetReached: "ai_budget_reached"
            case .messagePassedToOwner: "message_passed_to_owner"
            case .introSuggestion: "intro_suggestion"
            case .summaryMovedToDM: "summary_moved_to_dm"
            case .recordingMovedToDM: "recording_moved_to_dm"
            case .relayedToOwner: "relayed_to_owner"
            case .aiConsentNeeded: "ai_consent_needed"
            }
        }
    }
    
    let kind: Kind
    
    /// Parses the SDK's `data` JSON for a `com.spiral.notice` message.
    /// Returns nil for another msgtype, a kind this build does not know,
    /// or a kind missing its variables — the caller then shows `body`.
    init?(msgtype: String, data: String) {
        guard msgtype == Self.msgtype,
              let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let facts = object[Self.key] as? [String: Any],
              let kind = facts["kind"] as? String else {
            return nil
        }
        
        switch kind {
        case "referral_joined":
            guard let joinedUserID = facts["joined_user_id"] as? String, joinedUserID.hasPrefix("@") else { return nil }
            let joinedDisplayName = (facts["joined_display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.kind = .referralJoined(joinedUserID: joinedUserID,
                                        joinedDisplayName: joinedDisplayName.flatMap { $0.isEmpty ? nil : $0 })
        case "welcome":
            guard let owner = facts["owner_display_name"] as? String, !owner.isEmpty,
                  let agent = facts["agent_display_name"] as? String, !agent.isEmpty else { return nil }
            self.kind = .welcome(ownerDisplayName: owner,
                                 agentDisplayName: agent,
                                 behavior: facts["behavior"] as? String ?? "")
        case "phrase_changed":
            let deviceName = (facts["device_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.kind = .phraseChanged(deviceName: deviceName?.isEmpty == false ? deviceName : nil)
        case "reply_failed":
            self.kind = .replyFailed
        case "reply_withheld":
            self.kind = .replyWithheld
        case "ai_budget_reached":
            guard let raw = facts["resets_at"] as? String,
                  let resetsAt = try? Date(raw, strategy: .iso8601) else { return nil }
            self.kind = .aiBudgetReached(resetsAt: resetsAt)
        case "message_passed_to_owner":
            guard let owner = Self.nonBlank(facts["owner_display_name"]) else { return nil }
            self.kind = .messagePassedToOwner(ownerDisplayName: owner, greeting: Self.nonBlank(facts["greeting"]))
        case "intro_suggestion":
            guard let candidate = facts["candidate_agent_mxid"] as? String, candidate.hasPrefix("@"),
                  let summary = Self.nonBlank(facts["summary"]),
                  let opener = Self.nonBlank(facts["suggested_opener"]) else { return nil }
            self.kind = .introSuggestion(candidateAgentID: candidate, summary: summary, suggestedOpener: opener)
        case "summary_moved_to_dm", "recording_moved_to_dm":
            guard let roomID = facts["room_id"] as? String, roomID.hasPrefix("!") else { return nil }
            self.kind = kind == "summary_moved_to_dm" ? .summaryMovedToDM(roomID: roomID) : .recordingMovedToDM(roomID: roomID)
        case "relayed_to_owner":
            guard let note = Self.nonBlank(facts["note"]),
                  let fromUserID = facts["from_user_id"] as? String, fromUserID.hasPrefix("@"),
                  let roomID = facts["room_id"] as? String, roomID.hasPrefix("!") else { return nil }
            self.kind = .relayedToOwner(note: note, fromUserID: fromUserID, roomID: roomID)
        case "ai_consent_needed":
            guard let agent = Self.nonBlank(facts["agent_display_name"]) else { return nil }
            self.kind = .aiConsentNeeded(agentDisplayName: agent)
        default:
            return nil
        }
    }
    
    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    
    /// The notice as one line, for the room-list preview and a reply quote.
    /// The timeline draws it as a card (`SpiralNoticeRoomTimelineView`).
    var plainText: String {
        switch kind {
        case .referralJoined(let joinedUserID, let joinedDisplayName):
            UntranslatedL10n.noticeReferralJoined(joinedDisplayName ?? joinedUserID)
        case .welcome(let ownerDisplayName, _, _):
            UntranslatedL10n.noticeWelcomeTitle(ownerDisplayName)
        case .phraseChanged:
            UntranslatedL10n.noticePhraseChangedTitle
        case .replyFailed:
            UntranslatedL10n.noticeReplyFailedTitle
        case .replyWithheld:
            UntranslatedL10n.noticeReplyWithheldTitle
        case .aiBudgetReached:
            UntranslatedL10n.noticeAiBudgetReachedTitle
        case .messagePassedToOwner:
            UntranslatedL10n.noticeMessagePassedTitle
        case .introSuggestion:
            UntranslatedL10n.noticeIntroSuggestionTitle
        case .summaryMovedToDM:
            UntranslatedL10n.noticeSummaryMovedTitle
        case .recordingMovedToDM:
            UntranslatedL10n.noticeRecordingMovedTitle
        // The note itself: who and where are on the card.
        case .relayedToOwner(let note, _, _):
            note
        case .aiConsentNeeded:
            UntranslatedL10n.noticeAiConsentNeededTitle
        }
    }
}
