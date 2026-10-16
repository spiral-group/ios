//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): turning a post's related
// events into its current state.
//
// An Interactive Post keeps no state of its own. Its state is a fold over
// the `com.spiral.app.action` events related to it — the same shape MSC3381
// polls use, which is why it inherits E2EE, history, redaction and offline
// for free and needs no service of ours.
//
// The rule is two sentences. SHARED state: **apply the `op` of every action,
// in room order, from empty.** OWNED state — everything under `by.<userId>`
// — the same, from that user's own operations alone. A `state` blob is one
// sender's word for everyone's data and is never the fold's base while the
// action also carries an `op`.
//
// It used to be "the newest blob is the base; replay only what came after
// it". That loses every operation CONCURRENT with the newest one: two
// people took the two seats of a rock-paper-scissors duel inside one round
// trip, each blob was computed without the other's `set`, the second blob
// became the base and the first seat was gone — on every phone, forever
// (2026-09-18, two devices). An operation is what the sender meant; a blob
// is what the sender happened to see. Folding from operations is what
// makes two clients that see the same events compute the same state, which
// is the only property that matters here.
//
// A blob is a CHECKPOINT only when an action carries `state` and no `op` —
// the shape a large app will write when it stops sending every operation.
// Everything before a checkpoint is folded into it; everything after is
// replayed. In v1 no action is a checkpoint.
//
// Ordering is the room's, not the sender's: `origin_server_ts` with the
// event id as a tiebreak. Two clients that see the same events therefore
// compute the same state, which is the only property that matters here.
//

import Foundation

/// One parsed `com.spiral.app.action`.
struct SpiralAppAction: Equatable {
    let eventID: String
    let sender: String
    let originServerTimestamp: UInt64
    /// Sender's view of the sequence. Used to spot divergence, not to order.
    let seq: Int?
    let operation: SpiralAppOperation?
    /// Full state as the sender computed it. Absent in an op-only action.
    let state: SpiralAppValue?
    /// What a native card shows without running any code.
    let summary: SpiralAppSummary?
    /// Whom this action pinged: its `m.mentions` (§ 5.73). What decides whom
    /// the next action may ping again (§ 5.74).
    var mentions: [String] = []
}

/// The part of an action the timeline can render on its own.
struct SpiralAppSummary: Equatable {
    let line: String?
    /// Rendered as a live countdown natively, so a snapshot does not freeze.
    let countdownTo: Date?
    /// `none` · `badge` · `ping`. The app suggests; the client decides.
    let notify: String?
    let notifyUsers: [String]

    init?(json: Any?) {
        guard let object = json as? [String: Any] else { return nil }
        line = Self.line(from: object["line"])
        notify = object["notify"] as? String
        notifyUsers = object["notify_users"] as? [String] ?? []

        countdownTo = (object["countdown_to"] as? String).flatMap(Self.date(iso:))
    }

    /// The SDK writes `toISOString()` — with milliseconds, which a bare ISO
    /// 8601 reader refuses: every countdown an app ever wrote came out nil
    /// here (§ 5.79). Both shapes are read.
    static func date(iso text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

extension SpiralAppSummary {
    /// The line in the READER's language (§ 5.68). A post's words follow
    /// whoever looks at it (§ 5.60), and the line an action writes to the
    /// card is the post's words too — so an app may write it once per
    /// language, `{uk, ru, en}`, and each phone shows its own; a plain
    /// string is shown as written, as every line before was.
    static func line(from value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let byLanguage = value as? [String: String], !byLanguage.isEmpty else { return nil }
        let wanted = SpiralAppMount.appLanguage
        return byLanguage[wanted] ?? byLanguage["en"] ?? byLanguage.sorted { $0.key < $1.key }.first?.value
    }
}

enum SpiralAppStateFold {
    /// Result of folding, with the diagnostics a caller needs to decide
    /// whether to trust it.
    struct Outcome: Equatable {
        let state: SpiralAppValue
        /// Actions that could not be parsed — an unknown operation, or
        /// malformed content. Non-empty means this client computed state
        /// from fewer events than a newer client would.
        let skipped: [String]
        /// True when two actions claimed the same `seq`. Not an error: the
        /// tiebreak resolves it deterministically. Surfaced because a burst
        /// of these means an app is writing the same path from two places.
        let sawConflict: Bool
        /// The newest action's summary, for the timeline card.
        let summary: SpiralAppSummary?
        /// Actions that wrote into somebody else's `by.<userId>` namespace and
        /// were ignored. A host refuses these at write time, so one arriving
        /// means a client that is not ours — worth a line in a log, never a
        /// change in state.
        let refused: [String]
        /// People an action has pinged who have done nothing in the post
        /// since. Not pinged again until they do (§ 5.74).
        var awaitingReply: Set<String> = []
    }

    /// Fold actions into the post's current state.
    ///
    /// - Parameter actions: every action related to the post, in any order.
    static func fold(_ actions: [SpiralAppAction]) -> Outcome {
        // Room order, not arrival order and not sender order.
        let ordered = actions.sorted { lhs, rhs in
            if lhs.originServerTimestamp != rhs.originServerTimestamp {
                return lhs.originServerTimestamp < rhs.originServerTimestamp
            }
            return lhs.eventID < rhs.eventID
        }

        guard !ordered.isEmpty else {
            return Outcome(state: .object([:]), skipped: [], sawConflict: false, summary: nil, refused: [])
        }

        // SHARED: the newest CHECKPOINT (a state with no operation) is the
        // base; every operation after it is replayed. Whatever a checkpoint
        // says under the owned namespace is dropped — that half is rebuilt
        // below from the only source allowed to say it.
        let baseIndex = ordered.lastIndex { $0.state != nil && $0.operation == nil }
        var state = (baseIndex.flatMap { ordered[$0].state } ?? .object([:]))
            .removing([SpiralAppOperation.ownedNamespace])

        var skipped: [String] = []
        var refused: [String] = []
        let replayFrom = baseIndex.map { $0 + 1 } ?? 0

        for action in ordered[replayFrom...] {
            guard let operation = action.operation else {
                skipped.append(action.eventID)
                continue
            }
            for member in operation.members where member.owner == nil {
                state = member.applied(to: state)
            }
        }

        // OWNED: every action, from the beginning, and only the sender's own
        // namespace. A `state` blob is never consulted here. Judged per
        // member, so one forged member in a batch loses only itself.
        for action in ordered {
            guard let operation = action.operation else { continue }
            for member in operation.members {
                guard let owner = member.owner else { continue }
                guard owner == action.sender else {
                    if !refused.contains(action.eventID) { refused.append(action.eventID) }
                    continue
                }
                state = member.applied(to: state)
            }
        }

        return Outcome(state: state,
                       skipped: skipped,
                       sawConflict: hasSeqConflict(ordered),
                       summary: ordered.last?.summary,
                       refused: refused,
                       awaitingReply: awaitingReply(ordered))
    }

    /// Who was pinged and has not answered: walk the post in room order; a
    /// person's own action — any action — clears them, a mention adds them.
    ///
    /// «Answered» is any action because the host cannot tell a move from a
    /// seat from a tap, and does not need to: whoever touched the post since
    /// the ping has seen it. Read from the room, so every phone agrees and
    /// a restart forgets nothing — it was a one-minute timer per session
    /// (§ 5.73), which swallowed every reply in a quick game of chess.
    static func awaitingReply(_ ordered: [SpiralAppAction]) -> Set<String> {
        var waiting = Set<String>()
        for action in ordered {
            waiting.remove(action.sender)
            waiting.formUnion(action.mentions.filter { $0 != action.sender })
        }
        return waiting
    }

    /// Two actions claiming the same sequence number mean they were computed
    /// from the same base — a genuine concurrent edit.
    private static func hasSeqConflict(_ ordered: [SpiralAppAction]) -> Bool {
        var seen = Set<Int>()
        for action in ordered {
            guard let seq = action.seq else { continue }
            if !seen.insert(seq).inserted { return true }
        }
        return false
    }
}

// MARK: - Parsing

extension SpiralAppAction {
    /// The event type actions use. Deliberately not let through the timeline
    /// filter: actions are read via relations, never rendered as rows.
    static let eventType = "com.spiral.app.action"

    /// Whether this event is an action of ours that has been redacted.
    ///
    /// Redaction keeps `type` and strips `content`, so a redacted action can
    /// no longer be read — including its `seq`, which lived in the content.
    /// The caller counts these so that the hole one leaves is understood as
    /// deleted rather than missing.
    ///
    /// It cannot be attributed to a post: the relation was in the content too.
    /// A post therefore counts every redacted action in the room, which can
    /// only ever make the completeness check MORE forgiving, never less
    /// truthful about events it does hold.
    static func isRedacted(rawEventJSON: String) -> Bool {
        guard let data = rawEventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == eventType,
              let unsigned = root["unsigned"] as? [String: Any] else {
            return false
        }
        return unsigned["redacted_because"] != nil
    }

    /// Parse one raw, decrypted event as delivered by the relations FFI.
    ///
    /// Returns `nil` when this is not an action for `postEventID`. Content
    /// that is an action but malformed still parses, with `operation` nil,
    /// so the fold can count it as skipped rather than pretend it was absent.
    static func parse(rawEventJSON: String, relatedTo postEventID: String) -> SpiralAppAction? {
        guard let data = rawEventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == eventType,
              let content = root["content"] as? [String: Any] else {
            return nil
        }

        guard let relatesTo = content["m.relates_to"] as? [String: Any],
              relatesTo["rel_type"] as? String == "m.reference",
              relatesTo["event_id"] as? String == postEventID else {
            return nil
        }

        guard let eventID = root["event_id"] as? String,
              let sender = root["sender"] as? String,
              let timestamp = root["origin_server_ts"] as? UInt64 else {
            return nil
        }

        return SpiralAppAction(eventID: eventID,
                               sender: sender,
                               originServerTimestamp: timestamp,
                               seq: content["seq"] as? Int,
                               operation: content["op"].flatMap { SpiralAppOperation(json: $0) },
                               state: content["state"].flatMap { SpiralAppValue(json: $0) },
                               summary: SpiralAppSummary(json: content["summary"]),
                               mentions: (content["m.mentions"] as? [String: Any])?["user_ids"] as? [String] ?? [])
    }
}
