//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): completeness before
// correctness.
//
// The fold's tests prove two clients compute the same state from the same
// events. These prove the step before it — that the reader notices when it
// does NOT have the same events, because the relations read path can hand it
// a short set and raise nothing (design § 3.15).
//
// The two that matter most are the last pair: a gap that closes must end in
// the app, and a gap that never closes must end somewhere, rather than
// spinning on a key that is never going to arrive.
//

import Combine
@testable import ElementX
import Foundation
import Synchronization
import Testing

struct SpiralAppStateReaderTests {
    // MARK: - Helpers

    private static func action(_ eventID: String, ts: UInt64 = 100, seq: Int?) -> SpiralAppAction {
        SpiralAppAction(eventID: eventID,
                        sender: "@a:spiral.md",
                        originServerTimestamp: ts,
                        seq: seq,
                        operation: nil,
                        state: nil,
                        summary: nil)
    }

    /// One raw action as the relations FFI delivers it, setting `n` so a fold
    /// of several is checkable.
    private static func rawAction(_ eventID: String, ts: UInt64, seq: Int?, n: Int) -> String {
        let sequence = seq.map { "\"seq\":\($0)," } ?? ""
        return """
        {"type":"com.spiral.app.action","event_id":"\(eventID)","sender":"@a:spiral.md",
         "origin_server_ts":\(ts),
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    \(sequence)"op":{"set":{"path":"n","value":\(n)}}}}
        """
    }

    /// A batch of raw actions whose `seq` values are `sequences`, each setting
    /// `n` to its own `seq` so the folded state names the winner.
    private static func batch(_ sequences: [Int]) -> [String] {
        sequences.map { rawAction("$e\($0)", ts: UInt64(100 * $0), seq: $0, n: $0) }
    }

    /// A relations loader that replays a script: attempt *n* gets batch *n*,
    /// and the last batch repeats — which is exactly what a gap that never
    /// closes looks like from this side. Counts its reads so a policy that
    /// must terminate can be shown to terminate.
    private final nonisolated class Relations: Sendable {
        private let batches: [[String]]
        private let reads = Mutex(0)

        init(_ batches: [[String]]) {
            self.batches = batches
        }

        var readCount: Int {
            reads.withLock { $0 }
        }

        var load: SpiralAppStateReader.LoadRelations {
            { [self] _ in
                let index = reads.withLock { value in
                    value += 1
                    return value - 1
                }
                return batches[min(index, batches.count - 1)]
            }
        }
    }

    /// Retries run back to back, so a bounded policy can be proved without
    /// the tests waiting for it.
    private static let noDelay: @Sendable () async -> Void = { }

    private static func reader(_ relations: Relations) -> SpiralAppStateReader {
        SpiralAppStateReader(postEventID: "$post", load: relations.load, retryDelay: noDelay)
    }

    // MARK: - Completeness

    @Test
    func aContiguousSetIsComplete() {
        let actions = [Self.action("$1", seq: 1), Self.action("$2", seq: 2), Self.action("$3", seq: 3)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .complete)
    }

    @Test
    func aMissingSequenceNumberIsAGap() {
        // The whole point: holding 1, 2, 3 and 5 means 4 exists somewhere and
        // this client cannot see it.
        let actions = [Self.action("$1", seq: 1), Self.action("$2", seq: 2),
                       Self.action("$3", seq: 3), Self.action("$5", seq: 5)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .gaps([4]))
    }

    @Test
    func duplicateSequenceNumbersAreNotAGap() {
        // Two clients computing from the same base legitimately emit the same
        // `seq`. Treating that as incomplete would show a loader for a set
        // that is in fact whole.
        let actions = [Self.action("$1", seq: 1), Self.action("$1b", seq: 1), Self.action("$2", seq: 2)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .complete)
    }

    @Test
    func aSetStartingAboveOneIsMissingEverythingBelowIt() {
        // The event cache short-circuit (§ 3.15 H1) looks like this: the tail
        // of the conversation with the beginning of it missing.
        let actions = [Self.action("$3", seq: 3), Self.action("$4", seq: 4)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .gaps([1, 2]))
    }

    @Test
    func gapsAreReportedInAscendingOrder() {
        let actions = [Self.action("$5", seq: 5), Self.action("$2", seq: 2)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .gaps([1, 3, 4]))
    }

    @Test
    func actionsWithoutSequenceNumbersCannotBeChecked() {
        let actions = [Self.action("$1", seq: nil), Self.action("$2", seq: nil)]
        #expect(SpiralAppCompleteness.evaluate(actions) == .undeterminable)
    }

    @Test
    func anEmptyActionSetIsComplete() {
        // A post nobody has touched yet is not a post with missing events.
        #expect(SpiralAppCompleteness.evaluate([]) == .complete)
    }

    // MARK: - Reading

    @Test
    func aCompleteSetIsReadyAndFolded() async {
        let reader = Self.reader(Relations([Self.batch([1, 2, 3])]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.state.value(at: ["n"]) == .number(3))
        #expect(reader.snapshot.seq == 3)
    }

    @Test
    func anEmptyPostIsReady() async {
        let reader = Self.reader(Relations([[]]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.state == .object([:]))
        #expect(reader.snapshot.seq == 0)
    }

    @Test
    func aSetWithoutSequenceNumbersIsStillRendered() async {
        // Nothing can be checked, and refusing to render would make every
        // pre-`seq` post permanently a spinner.
        let reader = Self.reader(Relations([[Self.rawAction("$e1", ts: 100, seq: nil, n: 7)]]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.state.value(at: ["n"]) == .number(7))
        #expect(reader.snapshot.seq == 0)
    }

    // MARK: - The loader policy

    @Test
    func aGapThatClosesOnARefetchEndsReady() async {
        // The common case: the cache handed over a short set, the server has
        // the rest.
        let relations = Relations([Self.batch([1, 3]), Self.batch([1, 2, 3])])
        let reader = Self.reader(relations)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.state.value(at: ["n"]) == .number(3))
        #expect(relations.readCount == 2)
    }

    @Test
    func aGapThatClosesShowsTheLoaderBeforeTheApp() async {
        // § 5.11: the one place the runtime prefers a spinner to a render.
        // The intermediate `.loading` is what the post shows instead of a
        // number that disagrees with the same post on another phone.
        let reader = Self.reader(Relations([Self.batch([1, 3]), Self.batch([1, 2, 3])]))
        let readiness = Mutex<[SpiralAppStateReader.Readiness]>([])
        let cancellable = reader.snapshotPublisher.sink { snapshot in
            readiness.withLock { $0.append(snapshot.readiness) }
        }

        await reader.refresh()
        cancellable.cancel()

        #expect(readiness.withLock { $0 } == [.loading, .loading, .ready])
    }

    @Test
    func aGapThatNeverClosesEndsPartial() async {
        // § 3.15 H3: an action whose key never arrives. The gap is permanent,
        // so the reader must settle rather than wait for it.
        let relations = Relations([Self.batch([1, 3])])
        let reader = Self.reader(relations)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [2]))
        // Two reads: one that found the gap, one that proved it was not
        // filling in. Bounded by progress, not by patience.
        #expect(relations.readCount == 2)
    }

    @Test
    func aPermanentGapStillPublishesTheBestKnownState() async {
        // Partial is a marker on a render, not a refusal to render: the app
        // still gets the best state this client can compute.
        let reader = Self.reader(Relations([Self.batch([1, 3])]))

        await reader.refresh()

        #expect(reader.snapshot.state.value(at: ["n"]) == .number(3))
        #expect(reader.snapshot.seq == 3)
    }

    @Test
    func aSetThatKeepsGrowingWithoutClosingIsCappedByAttempts() async {
        // Progress alone would let this run forever — every attempt reads one
        // more action and the hole at 1 survives all of them.
        let relations = Relations([Self.batch([2]), Self.batch([2, 3]), Self.batch([2, 3, 4]),
                                   Self.batch([2, 3, 4, 5]), Self.batch([2, 3, 4, 5, 6]),
                                   Self.batch([2, 3, 4, 5, 6, 7])])
        let reader = Self.reader(relations)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [1]))
        #expect(relations.readCount == 5)
    }

    @Test
    func aFailedReadDoesNotClaimAnEmptyPostIsReady() async {
        // The failure mode this type exists to prevent: an unread set and a
        // rendered zero are indistinguishable unless the reader says so.
        struct LoadFailure: Error { }
        let reader = SpiralAppStateReader(postEventID: "$post",
                                          load: { _ in throw LoadFailure() },
                                          retryDelay: Self.noDelay)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .loading)
    }

    @Test
    func aReadThatFailsAfterFindingAGapKeepsWhatItFound() async {
        struct LoadFailure: Error { }
        let calls = Mutex(0)
        let batch = Self.batch([1, 3])
        let reader = SpiralAppStateReader(postEventID: "$post",
                                          load: { _ in
                                              let index = calls.withLock { value in
                                                  value += 1
                                                  return value - 1
                                              }
                                              guard index == 0 else { throw LoadFailure() }
                                              return batch
                                          },
                                          retryDelay: Self.noDelay)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [2]))
        #expect(reader.snapshot.state.value(at: ["n"]) == .number(3))
    }

    // MARK: - Writing

    @Test
    func nextSeqStartsAtOneOnAnUntouchedPost() async {
        let reader = Self.reader(Relations([[]]))

        await reader.refresh()

        #expect(reader.nextSeq() == 1)
    }

    @Test
    func nextSeqFollowsTheHighestSeen() async {
        let reader = Self.reader(Relations([Self.batch([1, 2, 3])]))

        await reader.refresh()

        #expect(reader.nextSeq() == 4)
    }

    @Test
    func nextSeqCountsFromTheHighestSeenNotTheCount() async {
        // After a permanent gap the next action must not reuse a number that
        // an unread action already holds, so it follows the highest `seq`
        // rather than how many actions were read.
        let reader = Self.reader(Relations([Self.batch([1, 3])]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [2]))
        #expect(reader.nextSeq() == 4)
    }

    @Test
    func nextSeqIsOneBeforeAnythingIsRead() {
        let reader = Self.reader(Relations([Self.batch([1, 2])]))
        #expect(reader.nextSeq() == 1)
    }

    // MARK: - Live ingestion

    @Test
    func aLiveActionIsFoldedWithoutARefetch() async {
        let relations = Relations([Self.batch([1, 2])])
        let reader = Self.reader(relations)
        await reader.refresh()

        await reader.ingest(rawEventJSONs: Self.batch([3]))

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.seq == 3)
        // Still one read: the subscription carried the action itself, so
        // there was nothing to go and fetch.
        #expect(relations.readCount == 1)
    }

    @Test
    func aRepeatedDeliveryDoesNotRepublish() async {
        // Deliveries repeat — after a lag reset, and when a late key lets an
        // event decrypt. Republishing an identical snapshot would redraw the
        // app for no reason.
        let reader = Self.reader(Relations([Self.batch([1])]))
        await reader.refresh()

        var published = 0
        let cancellable = reader.snapshotPublisher.dropFirst().sink { _ in published += 1 }
        defer { cancellable.cancel() }

        await reader.ingest(rawEventJSONs: Self.batch([1]))

        #expect(published == 0)
    }

    @Test
    func aLiveActionThatOpensAGapTriggersTheAuthoritativeRead() async {
        // Receiving seq 4 while holding only 1 does not mean 4 is wrong — it
        // means 2 and 3 exist and were never read. Folding without them would
        // publish a state built on a hole.
        let relations = Relations([Self.batch([1]), Self.batch([1, 2, 3, 4])])
        let reader = Self.reader(relations)
        await reader.refresh()
        #expect(relations.readCount == 1)

        await reader.ingest(rawEventJSONs: Self.batch([4]))

        #expect(relations.readCount == 2)
        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.seq == 4)
    }

    // MARK: - Redaction

    /// One action as the relations FFI delivers it AFTER redaction: the type
    /// survives, the content — and with it `seq` and the relation — does not.
    private static func redactedAction(_ eventID: String) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"\(eventID)","sender":"@a:spiral.md",
         "origin_server_ts":100,"content":{},
         "unsigned":{"redacted_because":{"type":"m.room.redaction","sender":"@a:spiral.md"}}}
        """
    }

    @Test
    func aRedactedActionExplainsTheHoleItLeaves() async {
        // Redaction strips the content, and `seq` lived there. Without
        // counting it the post would load for ever, waiting on an event that
        // is provably gone.
        let batch = Self.batch([1, 3]) + [Self.redactedAction("$gone")]
        let reader = Self.reader(Relations([batch]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
    }

    @Test
    func oneRedactionDoesNotExplainTwoHoles() async {
        let batch = Self.batch([1, 4]) + [Self.redactedAction("$gone")]
        let reader = Self.reader(Relations([batch]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [2, 3]))
    }

    @Test
    func thesameRedactionDeliveredTwiceCountsOnce() async {
        // Deliveries repeat. Counting a redaction twice would forgive a hole
        // that nothing explains.
        let redaction = Self.redactedAction("$gone")
        let reader = Self.reader(Relations([Self.batch([1, 4]) + [redaction, redaction]]))

        await reader.refresh()

        #expect(reader.snapshot.readiness == .partial(missing: [2, 3]))
    }

    @Test
    func redactingTheNewestActionRevertsIt() async {
        // The newest action is the fold's base, so honouring its redaction is
        // what makes "delete my action" mean anything.
        let reader = Self.reader(Relations([Self.batch([1, 2])]))
        await reader.refresh()
        #expect(reader.snapshot.state == .object(["n": .number(2)]))

        await reader.ingest(rawEventJSONs: [Self.redactedAction("$e2")])

        #expect(reader.snapshot.state == .object(["n": .number(1)]))
    }

    @Test
    func redactingAnOlderActionChangesNothing() async {
        // Later actions already carry a state that includes its effect, so
        // there is nothing left to undo.
        let reader = Self.reader(Relations([Self.batch([1, 2])]))
        await reader.refresh()

        await reader.ingest(rawEventJSONs: [Self.redactedAction("$e1")])

        #expect(reader.snapshot.state == .object(["n": .number(2)]))
    }

    @Test
    func aLaterShortReadDoesNotUndoACompletePicture() async {
        // The cache can answer a second read from a subset (design § 3.15).
        // Knowledge accumulates so that a short answer cannot walk a complete
        // post backwards into a gap.
        let relations = Relations([Self.batch([1, 2, 3]), Self.batch([1])])
        let reader = Self.reader(relations)
        await reader.refresh()
        #expect(reader.snapshot.readiness == .ready)

        await reader.refresh()

        #expect(reader.snapshot.readiness == .ready)
        #expect(reader.snapshot.seq == 3)
    }
}
