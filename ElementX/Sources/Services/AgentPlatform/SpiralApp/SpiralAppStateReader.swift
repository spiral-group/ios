//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): deciding whether a post's
// action set is complete enough to fold.
//
// `SpiralAppStateFold` answers "what is the state?". This file answers the
// question that has to come first — "do we have all the actions?" — because
// the relations read path can return a short set and raise nothing
// (design § 3.15): the event cache short-circuits the server as soon as it
// holds the post and one relation, a mid-pagination failure returns what it
// collected so far, and `try_decrypt_event` is a *try*, so an action whose
// key never arrived stays encrypted and is dropped by parsing.
//
// All three end in the same place: two clients fold different sets and one
// post shows two different numbers. That is a named kill criterion, so the
// correction belongs here rather than upstream — "best effort" is the right
// reading for pinned events and the wrong one for shared state.
//
// The schema already carries the detector. Every action has `seq`, so a hole
// is visible even though a short set is not. Design § 5.11 turns that into
// policy: loader while the set is still filling in, best-known state with a
// visible marker once it stops.
//

import Combine
import Foundation

/// Whether a set of actions can be trusted to be all of them.
enum SpiralAppCompleteness {
    enum Completeness: Equatable {
        case complete
        /// No action carried a `seq`, so there is nothing to check against.
        /// Trusted for want of anything better, but reported separately so a
        /// caller can tell a verdict from a shrug.
        case undeterminable
        /// Sequence numbers missing below the highest seen, ascending — the
        /// first `maxListedGaps` of them.
        case gaps([Int])
    }

    /// Look for holes in the sequence numbers the actions carry, below the
    /// highest.
    ///
    /// Duplicates are deliberately neither gaps nor errors: two clients
    /// computing from the same base legitimately emit the same `seq`, and the
    /// fold's timestamp/event-id tiebreak already resolves them. Only a hole
    /// means events are missing.
    ///
    /// - Parameter redacted: how many related actions were found redacted.
    ///   Redaction strips `content`, and `seq` lived there, so a redacted
    ///   action leaves a hole whose number can never be recovered. Each one
    ///   therefore accounts for exactly one gap — without this a single
    ///   deleted action would leave the post loading for ever, waiting on an
    ///   event that is provably gone.
    static func evaluate(_ actions: [SpiralAppAction], redacted: Int = 0) -> Completeness {
        guard !actions.isEmpty else { return .complete }

        // Nothing is required below 1, and parsing already refuses a `seq`
        // outside `1...SpiralAppActionLimits.maxSeq`.
        let numbers = Set(actions.compactMap(\.seq)).filter { $0 >= 1 }.sorted()
        guard !numbers.isEmpty else { return .undeterminable }

        // Walked from the numbers we HOLD, never from `1...highest`: a single
        // forged `seq` used to make every reader count up to it.
        var missingCount = 0
        var listed: [Int] = []
        var previous = 0
        for number in numbers {
            let hole = number - previous - 1
            if hole > 0 {
                missingCount += hole
                let room = maxListedGaps - listed.count
                if room > 0 {
                    listed.append(contentsOf: (previous + 1)..<(previous + 1 + min(hole, room)))
                }
            }
            previous = number
        }

        // Conservative on purpose: two holes and one redaction still reads as
        // incomplete, because only one of them is explained.
        guard missingCount > redacted else { return .complete }
        return .gaps(listed)
    }

    /// How many missing numbers a verdict names. The count behind it is
    /// exact; the list is what a person reads, and a hole a hundred thousand
    /// wide is not a hundred thousand facts.
    static let maxListedGaps = 64
}

/// One Interactive Post's state: read from the post's relations, folded, and
/// republished with a verdict on how much of it could be read.
final class SpiralAppStateReader {
    /// Loads the raw, decrypted JSON of the events related to a post.
    ///
    /// Injected rather than taken from a room proxy so the one piece that
    /// must not be wrong is testable with no Matrix machinery at all.
    typealias LoadRelations = @Sendable (String) async throws -> [String]

    enum Readiness: Equatable {
        case loading
        case ready
        /// Folded from a set known to be short. `missing` is what the post
        /// should admit it could not read.
        case partial(missing: [Int])
        /// The read failed and nothing is known. Not an empty post: "no actions
        /// yet" and "could not read" must never look the same.
        case failed

        /// Whether this state may be shown to an app, or written on top of.
        var isVouched: Bool {
            switch self {
            case .ready, .partial: true
            case .loading, .failed: false
            }
        }
    }

    struct Snapshot: Equatable {
        let state: SpiralAppValue
        /// Highest `seq` seen, 0 when no action carried one.
        let seq: Int
        let readiness: Readiness
        let summary: SpiralAppSummary?
        /// Pinged and not answered — not pinged again (§ 5.74).
        var awaitingReply: Set<String> = []

        static let loading = Snapshot(state: .object([:]), seq: 0, readiness: .loading, summary: nil)
    }

    /// The most actions one post keeps (M4). Each may be 32 KB, and every
    /// one is folded again on every change, so the count is bounded too.
    /// Ten times a long game of chess; a post past it shows the first ones
    /// in room order — the same ones on every phone — and says it is partial.
    static let maxKnownActions = 2000

    /// Attempts one `refresh()` may spend. Bounds the pathological case where
    /// every attempt reads one more action and a gap survives all of them.
    private static let maxAttempts = 5

    private let postEventID: String
    private let load: LoadRelations
    /// Waits between attempts. Injected so tests do not sleep.
    private let retryDelay: @Sendable () async -> Void

    /// Every action this reader has seen, by event id.
    ///
    /// Accumulated rather than replaced on each read. Two sources feed it —
    /// the relations read and the live subscription — and either can hand
    /// over a subset, so forgetting what was already known would let a later,
    /// shorter read undo a complete picture.
    private var known: [String: SpiralAppAction] = [:]

    /// Event ids of actions found redacted. A set, because the same event is
    /// delivered more than once and counting it twice would forgive a gap
    /// that nothing explains.
    private var redacted: Set<String> = []

    /// Whether `known` was cut to `maxKnownActions`.
    private var isTruncated = false

    /// Who is waiting for the first verdict on this post.
    private var verdictWaiters: [CheckedContinuation<Void, Never>] = []

    /// Nobody is looking: actions are kept but not folded. A fold replays
    /// every action on the main actor, which a post off screen has no use for.
    private var isDormant = false
    /// Whether `known` has moved on from the last snapshot.
    private var hasUnpublishedActions = false

    #if DEBUG
    /// Step 6.14. Stamps from actions absorbed but not yet folded into a
    /// published snapshot, so the road can be priced in two halves: arrival,
    /// and the fold that follows it.
    private var freshStamps: [(sender: String, seq: Int, sentAtMS: Int)] = []
    #endif

    private let snapshotSubject = CurrentValueSubject<Snapshot, Never>(.loading)
    var snapshotPublisher: AnyPublisher<Snapshot, Never> {
        snapshotSubject.eraseToAnyPublisher()
    }

    var snapshot: Snapshot {
        snapshotSubject.value
    }

    /// The newest `origin_server_ts` among the actions seen, or 0. What the
    /// host's clock is clamped to when an app asks the time.
    var newestOriginServerTimestamp: UInt64 {
        known.values.map(\.originServerTimestamp).max() ?? 0
    }

    init(postEventID: String,
         load: @escaping LoadRelations,
         retryDelay: @escaping @Sendable () async -> Void = { try? await Task.sleep(for: .seconds(1)) }) {
        self.postEventID = postEventID
        self.load = load
        self.retryDelay = retryDelay
    }

    /// Re-read the post's actions and republish its state.
    ///
    /// Every attempt publishes what it found, so nothing has to wait for the
    /// retries: a hole costs a post `.partial` from the first attempt, and the
    /// later ones improve on it. Returns once they are over.
    func refresh() async {
        var previousCount = known.count

        if snapshot.readiness == .failed {
            publish(readiness: .loading)
        }

        for attempt in 1...Self.maxAttempts {
            guard await readRelations() else {
                // The read failed, which leaves what was already known
                // standing. Only an EMPTY set changes verdict: "no actions
                // yet" and "could not read" look identical, and calling that
                // `.ready` is exactly the silent partial this type exists to
                // catch.
                publish(readiness: known.isEmpty ? .failed : verdict())
                return
            }

            guard case .gaps(let missing) = completeness() else {
                publish(readiness: .ready)
                return
            }

            // A gap left by an action that never decrypted may never close,
            // so "incomplete → keep loading" on its own would spin forever.
            // Progress — strictly more actions than the last attempt — is
            // what buys another attempt.
            let madeProgress = known.count > previousCount
            previousCount = known.count

            publish(readiness: .partial(missing: missing))

            guard madeProgress, attempt < Self.maxAttempts else { return }

            await retryDelay()
        }
    }

    /// Wait for a verdict on the state, and say whether it may be shown.
    /// Bounded: a read that never answers is a read that failed.
    func verdict(within deadline: Duration) async -> Bool {
        if snapshot.readiness == .loading {
            await withCheckedContinuation { continuation in
                verdictWaiters.append(continuation)
                Task { [weak self] in
                    try? await Task.sleep(for: deadline)
                    self?.releaseVerdictWaiters()
                }
            }
        }
        return snapshot.readiness.isVouched
    }

    private func releaseVerdictWaiters() {
        let waiting = verdictWaiters
        verdictWaiters.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Keep what arrives without folding it, until `wake`.
    func sleep() {
        isDormant = true
    }

    /// Publish whatever arrived while nobody was looking.
    func wake() async {
        isDormant = false
        guard hasUnpublishedActions else { return }
        hasUnpublishedActions = false
        await settle()
    }

    /// Take actions delivered by the live subscription.
    ///
    /// The fast path: an action that arrives this way needs no refetch. The
    /// exception is an action whose `seq` opens a gap — that means history is
    /// missing, not that this event is wrong, so the authoritative read runs
    /// to fill it in.
    ///
    /// Deliveries repeat. The same event id arrives again after a lag reset,
    /// and again when a late room key lets it decrypt at last, so this is an
    /// upsert rather than an append.
    func ingest(rawEventJSONs: [String]) async {
        guard absorb(rawEventJSONs) else { return }

        guard !isDormant else {
            hasUnpublishedActions = true
            return
        }
        await settle()
    }

    private func settle() async {
        if case .gaps = completeness() {
            await refresh()
        } else {
            publish(readiness: .ready)
        }
    }

    /// Other people's actions newer, in room order, than `userID`'s own
    /// newest one in this post — what a write from `userID` now answers.
    func actions(after userID: String) -> [SpiralAppAction] {
        let ordered = known.values.sorted { lhs, rhs in
            lhs.originServerTimestamp != rhs.originServerTimestamp
                ? lhs.originServerTimestamp < rhs.originServerTimestamp
                : lhs.eventID < rhs.eventID
        }
        let start = ordered.lastIndex { $0.sender == userID }.map { $0 + 1 } ?? 0
        return ordered[start...].filter { $0.sender != userID }
    }

    /// The `seq` the next locally-originated action should carry.
    func nextSeq() -> Int {
        snapshot.seq + 1
    }

    // MARK: - Private

    /// Read the relations into `known`. `false` when the read itself failed,
    /// which is not the same as reading no actions.
    private func readRelations() async -> Bool {
        do {
            _ = try await absorb(load(postEventID))
            return true
        } catch {
            MXLog.error("[SpiralApp] could not read relations for \(postEventID): \(error)")
            return false
        }
    }

    /// Take a batch of raw events into what this reader knows.
    ///
    /// Actions upsert by event id. A REDACTED action does two things: it is
    /// counted, so the hole its unreadable `seq` leaves is understood as
    /// deleted rather than missing, and it is dropped from the fold if we had
    /// already read it. The second is what gives redaction any meaning — the
    /// newest action is the fold's base, so deleting it reverts it, while
    /// deleting an older one changes nothing because later actions already
    /// snapshotted over it.
    ///
    /// Returns whether anything changed, so a repeated delivery does not
    /// republish an identical snapshot.
    private func absorb(_ rawEventJSONs: [String]) -> Bool {
        var changed = false

        for json in rawEventJSONs {
            if let action = SpiralAppAction.parse(rawEventJSON: json, relatedTo: postEventID) {
                if known[action.eventID] != action {
                    known[action.eventID] = action
                    changed = true

                    #if DEBUG
                    // Only what just happened. The authoritative read pulls
                    // the whole history back, and an hour-old action priced
                    // as if it were in flight would poison every percentile.
                    if let sentAtMS = Self.debugStamp(of: json) {
                        let ms = Int(Date().timeIntervalSince1970 * 1000) - sentAtMS
                        if ms > 0, ms < 60000 {
                            MXLog.info("[spiral-lat] arrive sender=\(action.sender) seq=\(action.seq ?? -1) ms=\(ms)")
                            freshStamps.append((action.sender, action.seq ?? -1, sentAtMS))
                        }
                    }
                    #endif
                }
            } else if SpiralAppAction.isRedacted(rawEventJSON: json),
                      let eventID = Self.eventID(of: json) {
                if redacted.insert(eventID).inserted { changed = true }
                if known.removeValue(forKey: eventID) != nil { changed = true }
            }
        }

        if known.count > Self.maxKnownActions {
            let kept = known.values.sorted { lhs, rhs in
                lhs.originServerTimestamp != rhs.originServerTimestamp
                    ? lhs.originServerTimestamp < rhs.originServerTimestamp
                    : lhs.eventID < rhs.eventID
            }.prefix(Self.maxKnownActions)
            known = Dictionary(uniqueKeysWithValues: kept.map { ($0.eventID, $0) })
            isTruncated = true
        }

        return changed
    }

    private static func eventID(of rawEventJSON: String) -> String? {
        guard let data = rawEventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return root["event_id"] as? String
    }

    private func completeness() -> SpiralAppCompleteness.Completeness {
        SpiralAppCompleteness.evaluate(Array(known.values), redacted: redacted.count)
    }

    private func verdict() -> Readiness {
        if case .gaps(let missing) = completeness() { .partial(missing: missing) } else { .ready }
    }

    private func publish(readiness: Readiness) {
        let actions = Array(known.values)
        let outcome = SpiralAppStateFold.fold(actions)
        // Everything was read, but not everything could be shown.
        let readiness = readiness == .ready && (isTruncated || outcome.isOverBudget) ? .partial(missing: []) : readiness
        snapshotSubject.send(Snapshot(state: outcome.state,
                                      seq: actions.compactMap(\.seq).max() ?? 0,
                                      readiness: readiness,
                                      summary: outcome.summary,
                                      awaitingReply: outcome.awaitingReply))
        if readiness != .loading {
            releaseVerdictWaiters()
        }

        #if DEBUG
        // The snapshot is out. Everything past this line — the push into the
        // frame and React's render — is measured by the app, not here.
        let now = Int(Date().timeIntervalSince1970 * 1000)
        for stamp in freshStamps {
            MXLog.info("[spiral-lat] fold sender=\(stamp.sender) seq=\(stamp.seq) ms=\(now - stamp.sentAtMS)")
        }
        freshStamps.removeAll()
        #endif
    }

    #if DEBUG
    /// The moment an action left its author, when it was built by a debug
    /// build that stamps one. Read straight off the raw event so the
    /// production type stays exactly as it is.
    private static func debugStamp(of rawEventJSON: String) -> Int? {
        guard let data = rawEventJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? [String: Any],
              let dbg = content["dbg"] as? [String: Any] else {
            return nil
        }
        return dbg["t"] as? Int
    }
    #endif
}
