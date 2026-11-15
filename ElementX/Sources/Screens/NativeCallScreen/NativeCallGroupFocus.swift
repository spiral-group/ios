//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): who fills the stage of a group call (the operator's picks: Focus on video,
// the Spotlight on audio, the others in a strip). The stage follows the conversation, but only a sustained turn moves
// it: a cough, a "yes", a breath or two people talking over each other leave it where it is.

import Foundation

nonisolated struct NativeCallGroupFocus: Equatable {
    /// How long someone must speak, without a break, before the stage turns to them.
    static let sustainedTurn = 1.0
    /// How long the person on the stage must be quiet before it can turn: a breath is not the end of a turn.
    static let quietHold = 0.5
    /// A voice that never stops (a television by an open microphone) can't keep the stage for ever: after this long,
    /// someone who has spoken for `interruptingTurn` takes it even though the staged voice goes on.
    static let floorHeldTooLong = 8.0
    static let interruptingTurn = 1.5

    /// Who is on the stage now; nil before anyone could be.
    private(set) var focused: String?

    private var speakingSince: [String: Double] = [:]
    /// Since when the person on the stage has been quiet; nil while they speak.
    private var focusedQuietSince: Double?
    /// People the stage was taken from while they were still "speaking": their unbroken run can't take it back.
    private var outspoken: Set<String> = []

    /// Folds in who is in the call and who is speaking at `time` (seconds, monotonic). `candidates` are the people
    /// who can take the stage, in the call's order; the first one takes it when nobody has yet or the staged person
    /// left.
    mutating func update(at time: Double, candidates: [String], speaking: Set<String>) {
        speakingSince = speakingSince.filter { speaking.contains($0.key) && candidates.contains($0.key) }
        for id in candidates where speaking.contains(id) && speakingSince[id] == nil {
            speakingSince[id] = time
        }
        outspoken.formIntersection(speaking)

        guard let focused, candidates.contains(focused) else {
            stage(longestSpeaker(at: time, heldFor: 0) ?? candidates.first, at: time, speaking: speaking)
            return
        }
        if speaking.contains(focused) {
            focusedQuietSince = nil
        } else if focusedQuietSince == nil {
            focusedQuietSince = time
        }

        if let quietSince = focusedQuietSince {
            guard time - quietSince >= Self.quietHold, let next = longestSpeaker(at: time, heldFor: Self.sustainedTurn) else { return }
            stage(next, at: time, speaking: speaking)
        } else if let since = speakingSince[focused], time - since >= Self.floorHeldTooLong,
                  let next = longestSpeaker(at: time, heldFor: Self.interruptingTurn) {
            outspoken.insert(focused)
            stage(next, at: time, speaking: speaking)
        }
    }

    /// When an `update` would next change the stage, if nothing else changes. The caller re-runs `update` then.
    func nextDecision(after time: Double) -> Double? {
        guard let earliest = speakingSince.filter({ isEligible($0.key) }).map(\.value).min() else { return nil }
        let moment: Double
        if let quietSince = focusedQuietSince {
            moment = max(earliest + Self.sustainedTurn, quietSince + Self.quietHold)
        } else if let focused, let since = speakingSince[focused] {
            moment = max(earliest + Self.interruptingTurn, since + Self.floorHeldTooLong)
        } else {
            return nil
        }
        return moment > time ? moment : nil
    }

    private mutating func stage(_ id: String?, at time: Double, speaking: Set<String>) {
        focused = id
        focusedQuietSince = id.map { speaking.contains($0) } == false ? time : nil
    }

    private func isEligible(_ id: String) -> Bool {
        id != focused && !outspoken.contains(id)
    }

    private func longestSpeaker(at time: Double, heldFor duration: Double) -> String? {
        speakingSince
            .filter { isEligible($0.key) && time - $0.value >= duration }
            .min { ($0.value, $0.key) < ($1.value, $1.key) }?
            .key
    }
}
