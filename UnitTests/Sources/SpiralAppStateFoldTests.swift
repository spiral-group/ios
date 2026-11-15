//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.7): the fold is the contract.
//
// Every client must compute the SAME state from the same events, or two
// people see different things in one post and the feature is worthless. So
// these tests care less about any individual operation than about
// convergence: same events in any order, same result.
//

import Foundation
@testable import Spiral
import Testing

struct SpiralAppStateFoldTests {
    // MARK: - Helpers

    private static func action(_ eventID: String,
                               ts: UInt64,
                               sender: String = "@a:spiral.md",
                               seq: Int? = nil,
                               op: SpiralAppOperation? = nil,
                               state: SpiralAppValue? = nil) -> SpiralAppAction {
        SpiralAppAction(eventID: eventID,
                        sender: sender,
                        originServerTimestamp: ts,
                        seq: seq,
                        operation: op,
                        state: state,
                        summary: nil)
    }

    // MARK: - Who was pinged and has not answered (§ 5.74)

    @Test
    func aPingIsAnsweredByAnyActionOfThePersonPinged() {
        let pinged = { (id: String, ts: UInt64, sender: String, mentions: [String]) -> SpiralAppAction in
            var action = Self.action(id, ts: ts, sender: sender, op: .increment(path: ["n"], by: 1))
            action.mentions = mentions
            return action
        }
        let game = [pinged("$1", 100, "@a:spiral.md", ["@b:spiral.md"]),
                    pinged("$2", 200, "@b:spiral.md", ["@a:spiral.md"]),
                    pinged("$3", 300, "@a:spiral.md", ["@b:spiral.md", "@c:spiral.md"])]

        #expect(SpiralAppStateFold.fold(game).awaitingReply == ["@b:spiral.md", "@c:spiral.md"])
        #expect(SpiralAppStateFold.fold(game.reversed()).awaitingReply == ["@b:spiral.md", "@c:spiral.md"], "room order, not arrival order")
        #expect(SpiralAppStateFold.fold(Array(game.prefix(2))).awaitingReply == ["@a:spiral.md"], "b answered by moving")
        #expect(SpiralAppStateFold.fold([pinged("$1", 1, "@a:spiral.md", ["@a:spiral.md"])]).awaitingReply.isEmpty, "never oneself")
    }

    // MARK: - Ordering and convergence

    @Test
    func foldIsIndependentOfArrivalOrder() {
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["a"], value: .number(1))),
            Self.action("$2", ts: 200, op: .set(path: ["b"], value: .number(2))),
            Self.action("$3", ts: 300, op: .set(path: ["a"], value: .number(3)))
        ]

        let forward = SpiralAppStateFold.fold(actions).state
        let reversed = SpiralAppStateFold.fold(actions.reversed()).state
        let shuffled = SpiralAppStateFold.fold([actions[1], actions[2], actions[0]]).state

        #expect(forward == reversed)
        #expect(forward == shuffled)
        #expect(forward.value(at: ["a"]) == .number(3))
    }

    @Test
    func equalTimestampsAreBrokenByEventID() {
        // Two clients acting in the same millisecond must still agree, and
        // the only thing both of them can see is the event id.
        let first = Self.action("$aaa", ts: 100, op: .set(path: ["winner"], value: .string("a")))
        let second = Self.action("$bbb", ts: 100, op: .set(path: ["winner"], value: .string("b")))

        let one = SpiralAppStateFold.fold([first, second]).state
        let other = SpiralAppStateFold.fold([second, first]).state

        #expect(one == other)
        // `$bbb` sorts last, so it is applied last and wins.
        #expect(one.value(at: ["winner"]) == .string("b"))
    }

    @Test
    func emptyActionListFoldsToAnEmptyObject() {
        #expect(SpiralAppStateFold.fold([]).state == .object([:]))
    }

    // MARK: - The snapshot rule

    @Test
    func foldStartsFromTheNewestActionCarryingState() {
        // v1: every action carries state, so the newest one IS the answer
        // and nothing needs replaying.
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["n"], value: .number(1)),
                        state: .object(["n": .number(1)])),
            Self.action("$2", ts: 200, op: .set(path: ["n"], value: .number(2)),
                        state: .object(["n": .number(2)]))
        ]

        #expect(SpiralAppStateFold.fold(actions).state == .object(["n": .number(2)]))
    }

    @Test
    func opOnlyActionsAfterASnapshotAreReplayed() {
        // The v2 shape: a snapshot followed by op-only actions. The reader is
        // unchanged, which is the point of making `state` optional now.
        let actions = [
            Self.action("$1", ts: 100, state: .object(["n": .number(1)])),
            Self.action("$2", ts: 200, op: .increment(path: ["n"], by: 5)),
            Self.action("$3", ts: 300, op: .increment(path: ["n"], by: 2))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["n"]) == .number(8))
    }

    @Test
    func actionsBeforeTheNewestSnapshotAreNotReplayed() {
        let actions = [
            Self.action("$1", ts: 100, op: .increment(path: ["n"], by: 99)),
            Self.action("$2", ts: 200, state: .object(["n": .number(10)])),
            Self.action("$3", ts: 300, op: .increment(path: ["n"], by: 1))
        ]

        // 99 must not appear: it is already folded into the checkpoint. And
        // a checkpoint is a state WITHOUT an op — $2 has none.
        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["n"]) == .number(11))
    }

    @Test
    func aBlobBesideAnOperationIsNotABase() {
        // The action after a checkpoint carries a stale blob (computed
        // before it saw $2). Only its op counts.
        let actions = [
            Self.action("$1", ts: 100, state: .object(["n": .number(10)])),
            Self.action("$2", ts: 200, op: .increment(path: ["n"], by: 1), state: .object(["n": .number(11)])),
            Self.action("$3", ts: 300, op: .increment(path: ["n"], by: 1), state: .object(["n": .number(11)]))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["n"]) == .number(12))
    }

    // MARK: - Operations

    @Test
    func perUserPathsNeverCollide() {
        // The poll's design: one path per voter, so two votes in flight at
        // once cannot conflict at all.
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["votes", "@bohdan"], value: .string("carpathians"))),
            Self.action("$2", ts: 100, op: .set(path: ["votes", "@olena"], value: .string("lviv")))
        ]

        let state = SpiralAppStateFold.fold(actions).state
        #expect(state.value(at: ["votes", "@bohdan"]) == .string("carpathians"))
        #expect(state.value(at: ["votes", "@olena"]) == .string("lviv"))
    }

    @Test
    func concurrentWritesWithSnapshotsAsTheHostWritesThemBothSurvive() {
        // What two phones ACTUALLY put in the room: every action carries the
        // op AND the full state the sender computed from its own base. Two
        // taps inside one round trip each computed from the same base, so
        // neither blob contains the other's op. Rock-paper-scissors,
        // 2026-09-18: two people took the two seats at once and one seat was
        // gone. The fold is over operations; a blob beside an op is ignored.
        let actions = [
            Self.action("$1", ts: 100, sender: "@a:spiral.md", seq: 1,
                        op: .setIfAbsent(path: ["p1"], value: .string("@a")),
                        state: .object(["p1": .string("@a")])),
            Self.action("$2", ts: 101, sender: "@b:spiral.md", seq: 1,
                        op: .setIfAbsent(path: ["p2"], value: .string("@b")),
                        state: .object(["p2": .string("@b")]))
        ]

        let state = SpiralAppStateFold.fold(actions).state
        #expect(state.value(at: ["p1"]) == .string("@a"))
        #expect(state.value(at: ["p2"]) == .string("@b"))
    }

    @Test
    func setIfAbsentLetsTheFirstWriterWin() {
        // The randomiser: whoever lands first keeps the result, and no lock
        // is needed anywhere.
        let actions = [
            Self.action("$1", ts: 100, op: .setIfAbsent(path: ["winner"], value: .string("first"))),
            Self.action("$2", ts: 200, op: .setIfAbsent(path: ["winner"], value: .string("second")))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["winner"]) == .string("first"))
    }

    @Test
    func setIfAbsentTreatsNullAsAbsent() {
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["slot"], value: .null)),
            Self.action("$2", ts: 200, op: .setIfAbsent(path: ["slot"], value: .string("taken")))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["slot"]) == .string("taken"))
    }

    @Test
    func incrementCreatesTheCounterWhenAbsent() {
        let actions = [Self.action("$1", ts: 100, op: .increment(path: ["count"], by: 3))]
        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["count"]) == .number(3))
    }

    @Test
    func concurrentIncrementsBothCount() {
        // The reason `incr` exists rather than read-modify-write with `set`:
        // two people adding at once must not lose one of the additions.
        let actions = [
            Self.action("$1", ts: 100, op: .increment(path: ["count"], by: 1)),
            Self.action("$2", ts: 100, op: .increment(path: ["count"], by: 1))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["count"]) == .number(2))
    }

    @Test
    func listAppendsFromTwoPeopleBothSurvive() {
        // The shopping list: appends never collide.
        let actions = [
            Self.action("$1", ts: 100, op: .listAppend(path: ["items"],
                                                       item: .object(["id": .string("a")]))),
            Self.action("$2", ts: 200, op: .listAppend(path: ["items"],
                                                       item: .object(["id": .string("b")])))
        ]

        guard case .array(let items)? = SpiralAppStateFold.fold(actions).state.value(at: ["items"]) else {
            Issue.record("items is not an array")
            return
        }
        #expect(items.count == 2)
    }

    @Test
    func listRemoveTakesOutTheMatchingIDOnly() {
        let actions = [
            Self.action("$1", ts: 100, op: .listAppend(path: ["items"],
                                                       item: .object(["id": .string("a")]))),
            Self.action("$2", ts: 200, op: .listAppend(path: ["items"],
                                                       item: .object(["id": .string("b")]))),
            Self.action("$3", ts: 300, op: .listRemove(path: ["items"], id: "a"))
        ]

        guard case .array(let items)? = SpiralAppStateFold.fold(actions).state.value(at: ["items"]) else {
            Issue.record("items is not an array")
            return
        }
        #expect(items == [.object(["id": .string("b")])])
    }

    @Test
    func deletingTwiceIsIdempotent() {
        // Two people can both tick "remove" before either sees the other.
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["x"], value: .number(1))),
            Self.action("$2", ts: 200, op: .delete(path: ["x"])),
            Self.action("$3", ts: 300, op: .delete(path: ["x"]))
        ]

        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["x"]) == nil)
    }

    // MARK: - Forward compatibility

    @Test
    func anUnknownOperationIsSkippedAndReported() {
        // A newer client writing a seventh operation must not make this one
        // compute a plausible-but-wrong state. It is counted, not guessed at.
        let actions = [
            Self.action("$1", ts: 100, op: .set(path: ["n"], value: .number(1))),
            Self.action("$2", ts: 200, op: nil),
            Self.action("$3", ts: 300, op: .increment(path: ["n"], by: 1))
        ]

        let outcome = SpiralAppStateFold.fold(actions)
        #expect(outcome.skipped == ["$2"])
        #expect(outcome.state.value(at: ["n"]) == .number(2))
    }

    @Test
    func repeatedSequenceNumbersAreReportedAsAConflict() {
        let actions = [
            Self.action("$1", ts: 100, seq: 7, op: .set(path: ["a"], value: .number(1))),
            Self.action("$2", ts: 200, seq: 7, op: .set(path: ["b"], value: .number(2)))
        ]

        #expect(SpiralAppStateFold.fold(actions).sawConflict)
    }

    // MARK: - Event parsing

    @Test
    func parsesAnActionRelatedToThePost() {
        let json = """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "op":{"set":{"path":"votes.@a","value":"lviv"}},
                    "seq":3,
                    "summary":{"line":"1 of 5"}}}
        """

        let action = SpiralAppAction.parse(rawEventJSON: json, relatedTo: "$post")

        #expect(action?.eventID == "$act")
        #expect(action?.seq == 3)
        #expect(action?.operation == .set(path: ["votes", "@a"], value: .string("lviv")))
        #expect(action?.summary?.line == "1 of 5")
        #expect(action?.summary?.writer == "@a:spiral.md", "a card must be able to say whose line it is")
    }

    /// L1: a card names the writer of its line when that is not the author.
    @Test
    func aCardLineFromSomeoneElseIsAttributed() {
        let author = "@author:spiral.md"
        #expect(InteractivePostRoomTimelineView.lineAttribution(writer: (author, "Author"), author: author) == nil)
        #expect(InteractivePostRoomTimelineView.lineAttribution(writer: nil, author: author) == nil)
        #expect(InteractivePostRoomTimelineView.lineAttribution(writer: ("@mallory:spiral.md", "Mallory"), author: author)
            == UntranslatedL10n.spiralAppCardLineBy("Mallory"))
    }

    /// The SDK writes a countdown with `toISOString()` — milliseconds and
    /// all — and a bare ISO 8601 reader refused every one (§ 5.79).
    @Test
    func aCountdownIsReadAsTheSDKWritesIt() {
        let newYear2027 = Date(timeIntervalSince1970: 1_798_761_600)

        #expect(SpiralAppSummary(json: ["countdown_to": "2027-01-01T00:00:00.000Z"])?.countdownTo == newYear2027)
        #expect(SpiralAppSummary(json: ["countdown_to": "2027-01-01T00:00:00Z"])?.countdownTo == newYear2027)
        #expect(SpiralAppSummary(json: ["countdown_to": "the first of January"])?.countdownTo == nil)
    }

    /// A line written once per language shows in the reader's; a plain
    /// string shows as written (§ 5.68).
    @Test
    func aLineByLanguageIsReadInTheAppsLanguage() {
        defer { Bundle.overrideLocalizations = nil }
        let byLanguage: [String: Any] = ["uk": "Колесо обрало: Аня", "ru": "Колесо выбрало: Аня", "en": "The wheel picked Anya"]

        Bundle.overrideLocalizations = ["ru"]
        #expect(SpiralAppSummary.line(from: byLanguage) == "Колесо выбрало: Аня")
        Bundle.overrideLocalizations = ["de"]
        #expect(SpiralAppSummary.line(from: byLanguage) == "The wheel picked Anya", "English for any other")
        #expect(SpiralAppSummary.line(from: ["uk": "лише українська"]) == "лише українська", "the one there is")
        #expect(SpiralAppSummary.line(from: "as written") == "as written")
        #expect(SpiralAppSummary.line(from: 7) == nil)
    }

    @Test
    func ignoresAnActionRelatedToADifferentPost() {
        // Two posts in one room must not fold each other's actions.
        let json = """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$other"},
                    "op":{"set":{"path":"x","value":1}}}}
        """

        #expect(SpiralAppAction.parse(rawEventJSON: json, relatedTo: "$post") == nil)
    }

    @Test
    func ignoresANonReferenceRelation() {
        // A reaction or an edit relates to the post too, and must not be
        // mistaken for an action.
        let json = """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.annotation","event_id":"$post"},
                    "op":{"set":{"path":"x","value":1}}}}
        """

        #expect(SpiralAppAction.parse(rawEventJSON: json, relatedTo: "$post") == nil)
    }

    @Test
    func parsesAnActionWithAnUnknownOperationAsSkippable() {
        let json = """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "seq":1,"op":{"mergeDeep":{"path":"x","value":1}}}}
        """

        let action = SpiralAppAction.parse(rawEventJSON: json, relatedTo: "$post")
        #expect(action != nil)
        #expect(action?.operation == nil)
    }

    // MARK: - Bounds (security pass 2, H1)

    private static func rawAction(seq: String) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "op":{"set":{"path":"x","value":1}},
                    "seq":\(seq)}}
        """
    }

    /// One hand-written action with a huge `seq` used to hang or trap every
    /// reader of its post. It is not an action of ours, so it is not one.
    @Test(arguments: ["\(Int.max)", "100001", "0", "-1", "-9223372036854775808", "1.5", "1e30", "true", "\"7\"", "null"])
    func aSeqOutsideTheBoundIsRefusedWhole(seq: String) {
        #expect(SpiralAppAction.parse(rawEventJSON: Self.rawAction(seq: seq), relatedTo: "$post") == nil)
    }

    @Test(arguments: [1, 42, SpiralAppActionLimits.maxSeq])
    func aSeqInsideTheBoundIsRead(seq: Int) {
        #expect(SpiralAppAction.parse(rawEventJSON: Self.rawAction(seq: "\(seq)"), relatedTo: "$post")?.seq == seq)
    }

    /// The homeserver refuses an action with no `seq`; so does a reader, so
    /// the two never disagree about which actions a post has.
    @Test
    func anActionWithoutASeqIsRefused() {
        let json = """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "op":{"set":{"path":"x","value":1}}}}
        """
        #expect(SpiralAppAction.parse(rawEventJSON: json, relatedTo: "$post") == nil)
    }

    private static func rawAction(value: String) -> String {
        """
        {"type":"com.spiral.app.action","event_id":"$act","sender":"@a:spiral.md",
         "origin_server_ts":1700000000000,
         "content":{"m.relates_to":{"rel_type":"m.reference","event_id":"$post"},
                    "seq":1,"op":{"set":{"path":"x","value":"\(value)"}}}}
        """
    }

    /// M4: one action past 32 KB of content is not folded at all.
    @Test
    func anActionPastTheContentBoundIsRefused() {
        let envelope = SpiralAppActionLimits.contentBytes(["m.relates_to": ["rel_type": "m.reference", "event_id": "$post"],
                                                           "seq": 1,
                                                           "op": ["set": ["path": "x", "value": ""]]]) ?? 0
        let fits = String(repeating: "a", count: SpiralAppActionLimits.maxContentBytes - envelope)

        #expect(SpiralAppAction.parse(rawEventJSON: Self.rawAction(value: fits), relatedTo: "$post") != nil)
        #expect(SpiralAppAction.parse(rawEventJSON: Self.rawAction(value: fits + "a"), relatedTo: "$post") == nil)
    }

    /// L1: a card, a viewer and a push read this line, whoever wrote it.
    @Test
    func aLongSummaryLineIsCutToTheBoundInCodePoints() throws {
        let flag = "🇺🇦" // two code points, one character
        let long = String(repeating: flag, count: 150)

        let line = try #require(SpiralAppSummary.line(from: long))
        #expect(line.unicodeScalars.count <= SpiralAppActionLimits.maxSummaryLineScalars)
        #expect(line == String(repeating: flag, count: 99) + "…", "cut between characters, never inside a flag")

        let short = String(repeating: "x", count: SpiralAppActionLimits.maxSummaryLineScalars)
        #expect(SpiralAppSummary.line(from: short) == short)
        #expect(SpiralAppSummary.line(from: ["en": long])?.unicodeScalars.count ?? .max <= SpiralAppActionLimits.maxSummaryLineScalars)
    }

    /// F4: a line is one line of plain text — no fake second line, no
    /// reversed or hidden characters, no `@room` — and emoji and the
    /// joiners and marks a script needs stay whole.
    @Test
    func aSummaryLineLosesControlAndFormatCharacters() {
        let cases: [(String, String)] = [
            ("Bob\nAlice: send me the code", "Bob Alice: send me the code"),
            ("a\r\nb\u{2028}c\td", "a  b c d"),
            ("Alice: \u{202E}kcilc\u{202C} x", "Alice: kcilc x"),
            ("pay\u{200B}pal\u{2066}x\u{2069}\u{FEFF}", "paypalx"),
            ("a\u{0000}b", "ab"),
            ("@room please look, @ROOM", "room please look, ROOM"),
            ("👨‍👩‍👧 1️⃣ 🏴󠁧󠁢󠁳󠁣󠁴󠁿 🇺🇦", "👨‍👩‍👧 1️⃣ 🏴󠁧󠁢󠁳󠁣󠁴󠁿 🇺🇦"),
            // Persian needs its zero-width non-joiner: «می‌خواهم», "I want".
            ("می\u{200C}خواهم", "می\u{200C}خواهم"),
            // A mixed line keeps the marks that set its direction.
            ("\u{200F}שלום Alice\u{200E} 2\u{200D}", "\u{200F}שלום Alice\u{200E} 2\u{200D}"),
            ("x\u{061C}y", "xy"),
            // `@room` spelled with invisibles inside: the `@` goes, the rest stays.
            ("@ro\u{200C}om @\u{2060}ROOM @r\u{00AD}o\u{E0041}om", "ro\u{200C}om \u{2060}ROOM r\u{00AD}o\u{E0041}om"),
            ("@roommate", "roommate"), ("@rooster", "@rooster"),
            ("@rob", "@rob")
        ]
        for (written, shown) in cases {
            #expect(SpiralAppActionLimits.cappedLine(written) == shown)
        }
    }

    // MARK: - The budget (M4)

    @Test
    func theFoldStopsWhereTheStateWouldPassTheBudget() {
        // Other people's actions arrive unchecked: seventy 1 KB appends make
        // a 70 KB state no host would ever have written.
        let item = SpiralAppValue.string(String(repeating: "x", count: 1024))
        var actions = (1...70).map { Self.action("$\($0)", ts: UInt64($0), seq: $0, op: .listAppend(path: ["items"], item: item)) }
        // A delete after the stop does not bring the rest back: it is past
        // the stop, and so is everything else.
        actions.append(Self.action("$del", ts: 71, seq: 71, op: .delete(path: ["items"])))

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(outcome.isOverBudget)
        #expect((outcome.state.encoded()?.count ?? .max) <= SpiralAppPostSession.maxStateBytes)
        guard case .array(let items) = outcome.state.value(at: ["items"]) ?? .null else {
            Issue.record("the stop dropped what fitted")
            return
        }
        #expect(items.count == 15, "the last append that fits, and none after it")
    }

    @Test
    func aLongPostUnderTheBudgetIsNotOverIt() {
        let actions = (1...500).map { Self.action("$\($0)", ts: UInt64($0), seq: $0, op: .increment(path: ["n"], by: 1)) }

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(!outcome.isOverBudget)
        #expect(outcome.state.value(at: ["n"]) == .number(500))
    }

    // MARK: - Values

    @Test
    func boolsSurviveAJSONRoundTrip() {
        // `NSNumber` does not distinguish Bool by type, so a checklist's
        // toggles turn into 0/1 if this is got wrong.
        let original = SpiralAppValue.object(["done": .bool(true), "count": .number(1)])
        guard let data = original.encoded(), let decoded = SpiralAppValue.decode(from: data) else {
            Issue.record("round trip failed")
            return
        }
        #expect(decoded == original)
        #expect(decoded.value(at: ["done"]) == .bool(true))
    }

    @Test
    func stateSizeIsMeasurable() {
        // The 16 KiB ceiling needs something to measure against.
        let state = SpiralAppValue.object(["items": .array((0..<100).map { .number(Double($0)) })])
        #expect(state.encodedByteCount > 0)
        #expect(state.encodedByteCount < 16 * 1024)
    }

    // MARK: - Owned paths: `by.<userId>` is folded from that user alone

    @Test
    func anOwnedPathIsNeverTakenFromAnotherSendersStateBlob() {
        // @b's action carries a full `state` in which @a has voted "B" and
        // @c — who never acted at all — has voted "B" too. The shared half
        // of that blob is the base, as always; the owned half is not, so
        // @a's vote stays what @a wrote and @c has no vote.
        let actions = [
            Self.action("$1", ts: 100, sender: "@a:spiral.md",
                        op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("A")),
                        state: .object(["by": .object(["@a:spiral.md": .object(["vote": .string("A")])])])),
            Self.action("$2", ts: 200, sender: "@b:spiral.md",
                        op: .set(path: ["title"], value: .string("Lunch?")),
                        state: .object(["title": .string("Lunch?"),
                                        "by": .object(["@a:spiral.md": .object(["vote": .string("B")]),
                                                       "@c:spiral.md": .object(["vote": .string("B")])])]))
        ]

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(outcome.state.value(at: ["title"]) == .string("Lunch?"))
        #expect(outcome.state.value(at: ["by", "@a:spiral.md", "vote"]) == .string("A"))
        #expect(outcome.state.value(at: ["by", "@c:spiral.md"]) == nil, "a vote was invented for someone who never voted")
        #expect(outcome.refused.isEmpty)
    }

    @Test
    func anOperationOnSomeoneElsesNamespaceIsRefusedAndReported() {
        let actions = [
            Self.action("$1", ts: 100, sender: "@a:spiral.md",
                        op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("A"))),
            Self.action("$2", ts: 200, sender: "@b:spiral.md",
                        op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("B")))
        ]

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(outcome.state.value(at: ["by", "@a:spiral.md", "vote"]) == .string("A"))
        #expect(outcome.refused == ["$2"])
    }

    @Test
    func ownedPathsSurviveASharedBaseWrittenLater() {
        // Owned operations are replayed from the beginning, not from the base,
        // so a base written after them does not erase them.
        let actions = [
            Self.action("$1", ts: 100, sender: "@a:spiral.md",
                        op: .increment(path: ["by", "@a:spiral.md", "score"], by: 3)),
            Self.action("$2", ts: 200, sender: "@b:spiral.md",
                        op: .set(path: ["round"], value: .number(2)),
                        state: .object(["round": .number(2)]))
        ]

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(outcome.state.value(at: ["round"]) == .number(2))
        #expect(outcome.state.value(at: ["by", "@a:spiral.md", "score"]) == .number(3))
    }

    @Test
    func ownedPathsFoldInRoomOrderWhateverTheArrivalOrder() {
        let actions = [
            Self.action("$1", ts: 100, sender: "@a:spiral.md", op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("A"))),
            Self.action("$2", ts: 200, sender: "@a:spiral.md", op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("C")))
        ]

        #expect(SpiralAppStateFold.fold(actions).state == SpiralAppStateFold.fold(actions.reversed()).state)
        #expect(SpiralAppStateFold.fold(actions).state.value(at: ["by", "@a:spiral.md", "vote"]) == .string("C"))
    }

    @Test
    func aForgedMemberInABatchLosesOnlyItself() {
        // @b batches a shared write, a write into its own namespace and a
        // write into @a's. The first two apply; the third is refused.
        let actions = [
            Self.action("$1", ts: 100, sender: "@b:spiral.md", op: .batch([
                .set(path: ["title"], value: .string("Lunch?")),
                .set(path: ["by", "@b:spiral.md", "vote"], value: .string("B")),
                .set(path: ["by", "@a:spiral.md", "vote"], value: .string("B"))
            ]))
        ]

        let outcome = SpiralAppStateFold.fold(actions)

        #expect(outcome.state.value(at: ["title"]) == .string("Lunch?"))
        #expect(outcome.state.value(at: ["by", "@b:spiral.md", "vote"]) == .string("B"))
        #expect(outcome.state.value(at: ["by", "@a:spiral.md"]) == nil)
        #expect(outcome.refused == ["$1"])
    }

    /// The bare `by` is every member's namespace at once (corpus F2): a write
    /// there is nobody's, so it forges no one's vote and is reported.
    @Test
    func aWriteAtTheBareOwnedNamespaceIsNobodys() {
        let forgeries: [SpiralAppOperation] = [
            .set(path: ["by"], value: .object(["@a:spiral.md": .object(["vote": .string("forged")])])),
            .setIfAbsent(path: ["by"], value: .object(["@a:spiral.md": .object(["seat": .number(7)])])),
            .listAppend(path: ["by"], item: .object(["@a:spiral.md": .number(1)])),
            .delete(path: ["by"])
        ]
        for forged in forgeries {
            let actions = [
                Self.action("$1", ts: 100, sender: "@a:spiral.md", op: .set(path: ["by", "@a:spiral.md", "vote"], value: .string("A"))),
                Self.action("$2", ts: 200, sender: "@b:spiral.md", op: forged)
            ]

            let outcome = SpiralAppStateFold.fold(actions)

            #expect(forged.owner == "")
            #expect(outcome.state.value(at: ["by", "@a:spiral.md"]) == .object(["vote": .string("A")]), "\(forged.shortDescription)")
            #expect(outcome.refused == ["$2"])
        }
    }
}
