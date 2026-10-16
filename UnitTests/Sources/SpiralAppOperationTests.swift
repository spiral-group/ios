//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.2): an operation must survive the
// trip to Matrix and back.
//
// Every action carries the operation that produced it, and every client folds
// that operation to reach the same state. A client that could not read back
// what it wrote would compute a different state from its OWN action than
// everyone else computes from it — the divergence the fold exists to prevent,
// caused by the encoder rather than by the network.
//

@testable import ElementX
import Foundation
import Testing

struct SpiralAppOperationTests {
    private static func roundTrip(_ operation: SpiralAppOperation) -> SpiralAppOperation? {
        SpiralAppOperation(json: operation.jsonObject)
    }

    @Test
    func everyOperationSurvivesEncodingAndDecoding() {
        let operations: [SpiralAppOperation] = [
            .set(path: ["a", "b"], value: .string("x")),
            .setIfAbsent(path: ["winner"], value: .string("@a:spiral.md")),
            .delete(path: ["items", "one"]),
            .increment(path: ["count"], by: 2),
            .listAppend(path: ["items"], item: .object(["id": .string("1")])),
            .listRemove(path: ["items"], id: "1")
        ]

        for operation in operations {
            #expect(Self.roundTrip(operation) == operation)
        }
    }

    @Test
    func encodingIsWhatTheWireFormatSays() {
        // Pinned against the design's own example rather than against the
        // decoder, so the two cannot drift together into a private dialect
        // no other client reads.
        let encoded = SpiralAppOperation.increment(path: ["count"], by: 1).jsonObject

        #expect(encoded.keys.first == "incr")
        let arguments = encoded["incr"] as? [String: Any]
        #expect(arguments?["path"] as? String == "count")
        #expect(arguments?["by"] as? Double == 1)
    }

    @Test
    func aNestedPathIsWrittenDotted() {
        let encoded = SpiralAppOperation.set(path: ["votes", "yes"], value: .number(3)).jsonObject
        let arguments = encoded["set"] as? [String: Any]

        #expect(arguments?["path"] as? String == "votes.yes")
    }

    @Test
    func aPathThroughAUserIDSurvives() {
        // Every Matrix user ID contains a dot, and keying state by user is
        // the first thing a poll or a checklist wants. Written dotted it
        // would read back as three components and address a slot nobody
        // meant — which is exactly what the design's own example did.
        let path = ["votes", "@bohdan:spiral.md"]
        let operation = SpiralAppOperation.set(path: path, value: .string("carpathians"))

        #expect(Self.roundTrip(operation) == operation)

        let written = operation.applied(to: .object([:]))
        #expect(written.value(at: path) == .string("carpathians"))
    }

    @Test
    func aPathContainingADotIsWrittenAsAnArray() {
        // The only form that can be read back. Plain paths stay dotted, so
        // the common event is still legible.
        let encoded = SpiralAppOperation.delete(path: ["votes", "@a:spiral.md"]).jsonObject
        let arguments = encoded["del"] as? [String: Any]

        #expect(arguments?["path"] as? [String] == ["votes", "@a:spiral.md"])
    }

    @Test
    func anArrayPathIsAlsoAccepted() {
        let decoded = SpiralAppOperation(json: ["incr": ["path": ["a", "b"], "by": 1.0]])
        #expect(decoded == .increment(path: ["a", "b"], by: 1))
    }

    @Test
    func aPathWithAnEmptyComponentIsRefused() {
        // It would address a key no writer can name.
        #expect(SpiralAppOperation(json: ["del": ["path": ["a", ""]]]) == nil)
        #expect(SpiralAppOperation(json: ["del": ["path": [] as [String]]]) == nil)
    }

    @Test
    func anEncodedOperationIsValidJSON() {
        // It is embedded in an event body, so a value that cannot serialise
        // would fail at send time rather than here.
        let operation = SpiralAppOperation.listAppend(path: ["items"],
                                                      item: .object(["id": .string("1"),
                                                                     "done": .bool(false),
                                                                     "note": .null]))

        #expect(JSONSerialization.isValidJSONObject(operation.jsonObject))
    }

    // MARK: - Batch

    @Test
    func aBatchSurvivesTheWireAndAppliesItsMembersInOrder() {
        let batch = SpiralAppOperation.batch([
            .set(path: ["a"], value: .number(1)),
            .increment(path: ["a"], by: 2),
            .listAppend(path: ["l"], item: .string("x"))
        ])

        let decoded = SpiralAppOperation(json: batch.jsonObject)
        #expect(decoded == batch)

        let state = batch.applied(to: .object([:]))
        #expect(state.value(at: ["a"]) == .number(3))
        #expect(state.value(at: ["l"]) == .array([.string("x")]))
        #expect(batch.members.count == 3)
    }

    @Test
    func aBatchIsRefusedWholeWhenAnyMemberIsUnknown() {
        // Half a batch is a state no other client computes.
        let json: [String: Any] = ["batch": ["ops": [
            ["set": ["path": "a", "value": 1]],
            ["multiply": ["path": "a", "by": 2]]
        ]]]
        #expect(SpiralAppOperation(json: json) == nil)
    }

    @Test
    func aBatchCannotNestAndCannotBeEmptyOrOversized() {
        #expect(SpiralAppOperation(json: ["batch": ["ops": [["batch": ["ops": [["del": ["path": "a"]]]]]]]]) == nil)
        #expect(SpiralAppOperation(json: ["batch": ["ops": [] as [Any]]]) == nil)
        let tooMany = Array(repeating: ["incr": ["path": "n", "by": 1.0]] as [String: Any],
                            count: SpiralAppOperation.maxBatchSize + 1)
        #expect(SpiralAppOperation(json: ["batch": ["ops": tooMany]]) == nil)
        let justEnough = Array(tooMany.prefix(SpiralAppOperation.maxBatchSize))
        #expect(SpiralAppOperation(json: ["batch": ["ops": justEnough]]) != nil)
    }
}
