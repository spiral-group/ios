//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, § 5.73): «your move», as the NSE shows it.
//
// A move is a `com.spiral.app.action`. When the app names the next player,
// the action carries `m.mentions`, and the mention rule pushes it to that
// person alone. The SDK has no content type for a custom event, so the NSE
// reads the event's own JSON — the notification item carries it, decrypted —
// through this. Compiled into the app as well, for its tests.
//

import Foundation

nonisolated struct SpiralActionNotification: Equatable {
    static let eventType = "com.spiral.app.action"

    /// Why the app pinged — `summary.notify_kind` (§ 5.74). What the push
    /// says before the line; a post that names no kind is a game from before
    /// kinds existed, and «your move» is what it meant.
    enum Kind: String, Equatable {
        case turn, challenge, record, result, mention
    }

    let kind: Kind

    /// The action's `summary.line` by language; a plain string is kept under
    /// the empty key, since it is shown as written (§ 5.68).
    let lines: [String: String]

    /// The post the move was made in — its `m.reference`. A tap opens the room
    /// on it (§ 5.82): the move itself is hidden, the post is what to answer.
    let postEventID: String?

    /// Nil unless `rawEvent` is an action that mentions `receiverID`: an
    /// action naming someone else is nobody's notification on this phone.
    init?(rawEvent: String, receiverID: String) {
        guard let event = try? JSONSerialization.jsonObject(with: Data(rawEvent.utf8)) as? [String: Any],
              event["type"] as? String == Self.eventType,
              let content = event["content"] as? [String: Any],
              let mentioned = (content["m.mentions"] as? [String: Any])?["user_ids"] as? [String],
              mentioned.contains(receiverID) else {
            return nil
        }
        let relatesTo = content["m.relates_to"] as? [String: Any]
        postEventID = relatesTo?["rel_type"] as? String == "m.reference" ? relatesTo?["event_id"] as? String : nil
        let summary = content["summary"] as? [String: Any]
        kind = (summary?["notify_kind"] as? String).flatMap(Kind.init) ?? .turn
        // Any member's words, so a push carries a line, not a page (L1).
        let line = summary?["line"]
        if let text = line as? String {
            lines = ["": SpiralAppActionLimits.cappedLine(text)]
        } else {
            lines = (line as? [String: String] ?? [:]).mapValues(SpiralAppActionLimits.cappedLine)
        }
    }

    /// «Your move · emm2 placed O»; the kind alone when the move wrote no
    /// line; a plain mention is its line — the title already says who.
    func body(language: String = Self.readerLanguage) -> String {
        let line = line(in: language)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = line?.isEmpty == false ? line : nil
        guard let prefix = kind.prefix else {
            return written ?? UntranslatedL10n.notificationInteractivePostMention
        }
        return written.map { "\(prefix) · \($0)" } ?? prefix
    }

    /// The reader's language, then English, then whichever the move wrote.
    func line(in language: String) -> String? {
        lines[""] ?? lines[language] ?? lines["en"] ?? lines.sorted { $0.key < $1.key }.first?.value
    }

    /// The first of the app's own languages as a primary subtag — the one
    /// `UntranslatedL10n` answers in, so the two halves of the body agree.
    static var readerLanguage: String {
        let preferred = Bundle.overrideLocalizations?.first ?? Bundle.app.preferredLocalizations.first ?? "en"
        return preferred.split(separator: "-").first.map { $0.lowercased() } ?? "en"
    }
}

private nonisolated extension SpiralActionNotification.Kind {
    var prefix: String? {
        switch self {
        case .turn: UntranslatedL10n.notificationInteractivePostYourMove
        case .challenge: UntranslatedL10n.notificationInteractivePostChallenge
        case .record: UntranslatedL10n.notificationInteractivePostRecord
        case .result: UntranslatedL10n.notificationInteractivePostResult
        case .mention: nil
        }
    }
}
