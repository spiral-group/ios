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
    static let key = "com.spiral.notice"
    
    enum Kind: Equatable {
        /// Someone registered through the reader's invite link; their name as
        /// the server saw it at notice time (older notices carry none).
        case referralJoined(joinedUserID: String, joinedDisplayName: String?)
        /// The assistant greets its owner once they accepted the DM.
        case welcome(ownerDisplayName: String, agentDisplayName: String, behavior: String)
        /// The account phrase was replaced from a signed-in device (Brief 0075);
        /// the device's name when the server could read it.
        case phraseChanged(deviceName: String?)
        /// Sign in with Apple was added to the account (1.0.3). It names no device, even if one is
        /// sent: a stolen token would name the owner's own phone and look reassuring.
        case appleLinked
        /// The agent could not answer the last message (ADR-0086).
        case replyFailed
        /// The automatic content check held the agent's reply back (coverage walk
        /// F7); resending meets the same check, so the card doesn't ask for it.
        case replyWithheld
        /// The agent spent its AI limit; it answers again at `resetsAt`, the end
        /// of the limit's window (Brief 0079, question 394). Posted once per window in the owner's DM.
        case aiBudgetReached(resetsAt: Date)
        /// One category's cap paused it (question 395): the owner's card in the assistant's DM (the push), and the
        /// one reply in a chat where an action was refused. `pauseUntil` nil: off until changed (a $0 cap).
        case aiCategoryPaused(category: AILimitCategory, pauseUntil: Date?)
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
        
        /// A notice that something went wrong, which reads red (question 359).
        var isFailure: Bool {
            self == .replyFailed
        }
        
        /// The wire name of the kind, for the card's accessibility identifier.
        var wireName: String {
            switch self {
            case .referralJoined: "referral_joined"
            case .welcome: "welcome"
            case .phraseChanged: "phrase_changed"
            case .appleLinked: "apple_linked"
            case .replyFailed: "reply_failed"
            case .replyWithheld: "reply_withheld"
            case .aiBudgetReached: "ai_budget_reached"
            case .aiCategoryPaused: "ai_category_paused"
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
        case "apple_linked":
            self.kind = .appleLinked
        case "reply_failed":
            self.kind = .replyFailed
        case "reply_withheld":
            self.kind = .replyWithheld
        case "ai_budget_reached":
            guard let raw = facts["resets_at"] as? String,
                  let resetsAt = try? Date(raw, strategy: .iso8601) else { return nil }
            self.kind = .aiBudgetReached(resetsAt: resetsAt)
        case "ai_category_paused":
            // A newer category reads as other (decision 96); a date that does not parse is no card.
            guard let category = facts["category"] as? String else { return nil }
            let pauseUntil: Date?
            switch facts["pause_until"] {
            case nil, is NSNull: pauseUntil = nil
            case let raw as String:
                guard let date = try? Date(raw, strategy: .iso8601) else { return nil }
                pauseUntil = date
            default: return nil
            }
            self.kind = .aiCategoryPaused(category: .init(serverValue: category), pauseUntil: pauseUntil)
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
    
    /// AGENT-PLATFORM (1.0.3 A3): the first word of a person's name, for the welcome's «Hi, Anna!». A name without spaces is
    /// used whole.
    static func firstName(of displayName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? name
    }
    
    /// AGENT-PLATFORM (1.0.3 A3): the person's own assistant's welcome, the one that offers starters.
    var isPersonalWelcome: Bool {
        if case .welcome(_, _, let behavior) = kind { behavior == "personal_assistant" } else { false }
    }
    
    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    
    /// «Перевод звонков на паузе до понедельника, 3:00»: the Limit page row's words after the category's name. Once the
    /// pause has passed it names the date, so the card stays true in the timeline.
    static func categoryPausedTitle(_ category: AILimitCategory, pauseUntil: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        AgentLimitWording.categoryPauseLine(category, pauseUntil.map(AILimitPause.until) ?? .untilChanged, now: now, calendar: calendar)
    }

    /// The notice as one line, for the room-list preview and a reply quote.
    /// The timeline draws it as a card (`SpiralNoticeRoomTimelineView`).
    var plainText: String {
        switch kind {
        case .referralJoined(let joinedUserID, let joinedDisplayName):
            UntranslatedL10n.noticeReferralJoined(joinedDisplayName ?? joinedUserID)
        case .welcome(let ownerDisplayName, _, _):
            UntranslatedL10n.noticeWelcomeTitle(Self.firstName(of: ownerDisplayName))
        case .phraseChanged:
            UntranslatedL10n.noticePhraseChangedTitle
        case .appleLinked:
            UntranslatedL10n.noticeAppleLinkedTitle
        case .replyFailed:
            UntranslatedL10n.noticeReplyFailedTitle
        case .replyWithheld:
            UntranslatedL10n.noticeReplyWithheldTitle
        case .aiBudgetReached:
            UntranslatedL10n.noticeAiBudgetReachedTitle
        case .aiCategoryPaused(let category, let pauseUntil):
            Self.categoryPausedTitle(category, pauseUntil: pauseUntil)
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
