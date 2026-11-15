//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: Unified Tool + Trigger models (Brief 0036 / ADR-0048).
//
// Pins the wire bridges the /tools UI + service rely on: ToolParams /
// TriggerKind / AudienceScope round-trip between the typed enums and the
// tagged JSON the `tool.arm` capability accepts, and the read-model parse
// back. A backend shape change fails loudly here long before it ships.

import Foundation
@testable import Spiral
import Testing

struct RoomToolsModelsTests {
    // MARK: - AudienceScope

    @Test
    func audienceScopeMemberlessWiresAsBareTag() {
        // owner_only / anyone / non_self_non_owner carry no members → bare tag string.
        #expect(AudienceScope.anyone.scopeWireValue as? String == "anyone")
        #expect(AudienceScope.ownerOnly.scopeWireValue as? String == "owner_only")
        #expect(AudienceScope.nonSelfNonOwner.scopeWireValue as? String == "non_self_non_owner")
    }

    @Test
    func audienceScopeMemberCarryingWiresAsSingleKeyObject() {
        let scope = AudienceScope.specificSenders(members: ["@bob:h", "@carol:h"])
        let obj = scope.scopeWireValue as? [String: Any]
        let inner = obj?["specific_senders"] as? [String: Any]
        #expect(inner?["members"] as? [String] == ["@bob:h", "@carol:h"])
    }

    @Test
    func audienceScopeRoundTripsThroughWire() {
        let cases: [AudienceScope] = [
            .anyone, .ownerOnly, .nonSelfNonOwner,
            .specificSenders(members: ["@bob:h"]),
            .everyoneExcept(members: ["@dan:h", "@eve:h"])
        ]
        for scope in cases {
            let rebuilt = AudienceScope(scopeWire: scope.scopeWireValue)
            #expect(rebuilt == scope, "round-trip mismatch for \(scope.tag)")
        }
    }

    @Test
    func audienceScopeParsesBareTagAndObject() {
        #expect(AudienceScope(scopeWire: "owner_only") == .ownerOnly)
        #expect(AudienceScope(scopeWire: ["specific_senders": ["members": ["@x:h"]]])
            == .specificSenders(members: ["@x:h"]))
        // Unknown / malformed falls open to anyone.
        #expect(AudienceScope(scopeWire: 42) == .anyone)
    }

    @Test
    func audienceScopeRequiresMembersOnlyForMemberCarryingScopes() {
        #expect(AudienceScope.specificSenders(members: []).requiresMembers)
        #expect(AudienceScope.everyoneExcept(members: []).requiresMembers)
        #expect(!AudienceScope.anyone.requiresMembers)
        #expect(!AudienceScope.ownerOnly.requiresMembers)
    }

    // MARK: - ToolParams

    @Test
    func toolParamsTranslateWiresKindAndLanguage() {
        let wire = ToolParams.translate(targetLanguage: "en").wireObject.value
        #expect(wire["kind"] as? String == "translate")
        #expect(wire["target_language"] as? String == "en")
    }

    @Test
    func toolParamsParameterlessKindsWireOnlyKind() {
        for params in [ToolParams.simplify, .correct, .summarize] {
            let wire = params.wireObject.value
            #expect(wire["kind"] as? String == params.kind)
            #expect(wire.count == 1)
        }
    }

    @Test
    func toolParamsInstructionKindsWireInstruction() {
        let rephrase = ToolParams.rephrase(instruction: "more polite").wireObject.value
        #expect(rephrase["kind"] as? String == "rephrase")
        #expect(rephrase["instruction"] as? String == "more polite")

        let custom = ToolParams.custom(instruction: "make it a TL;DR").wireObject.value
        #expect(custom["instruction"] as? String == "make it a TL;DR")
    }

    /// ADR-0094 A.5: the personal Tool carries one language, the catalog's exact code, and nothing else.
    @Test
    func toolParamsLiveTranslateWiresOneLanguageOnly() {
        let wire = ToolParams.liveTranslate(language: "pt-BR").wireObject.value
        #expect(wire["kind"] as? String == "live_translate")
        #expect(wire["language"] as? String == "pt-BR")
        #expect(wire.count == 2)
    }

    @Test
    func toolParamsCallKindsWireOnlyKind() {
        #expect(ToolParams.callSummary.wireObject.value["kind"] as? String == "call_summary")
        #expect(ToolParams.callRecording.wireObject.value["kind"] as? String == "call_recording")
        #expect(ToolParams.callSummary.wireObject.value.count == 1)
        #expect(ToolParams.callRecording.wireObject.value.count == 1)
    }

    @Test
    func toolParamsRoundTripsThroughWire() {
        let cases: [ToolParams] = [
            .translate(targetLanguage: "uk"),
            .simplify, .correct, .summarize,
            .rephrase(instruction: "formal"),
            .custom(instruction: "emoji only"),
            .liveTranslate(language: "zh-Hans"),
            .callSummary, .callRecording
        ]
        for params in cases {
            let rebuilt = ToolParams(wire: params.wireObject.value as [String: Any])
            #expect(rebuilt == params, "round-trip mismatch for \(params.kind)")
        }
    }

    @Test
    func toolParamsUnknownKindDecodesForwardCompat() {
        let rebuilt = ToolParams(wire: ["kind": "translataurus"])
        #expect(rebuilt == .unknown(kind: "translataurus"))
    }

    // MARK: - TriggerKind

    @Test
    func triggerOnMessageWiresKindAndSenderScope() {
        let wire = TriggerKind.onMessage(senderScope: .anyone).wireObject.value
        #expect(wire["kind"] as? String == "on_message")
        #expect(wire["sender_scope"] as? String == "anyone")
    }

    @Test
    func triggerOnVoiceCallWiresKindAndSpeakerScope() {
        let wire = TriggerKind.onVoiceCall(speakerScope: .ownerOnly).wireObject.value
        #expect(wire["kind"] as? String == "on_voice_call")
        #expect(wire["speaker_scope"] as? String == "owner_only")
    }

    @Test
    func triggerRoundTripsThroughWire() {
        let cases: [TriggerKind] = [
            .onMessage(senderScope: .specificSenders(members: ["@bob:h"])),
            .onVoiceCall(speakerScope: .anyone)
        ]
        for trigger in cases {
            let rebuilt = TriggerKind(wire: trigger.wireObject.value as [String: Any])
            #expect(rebuilt == trigger, "round-trip mismatch for \(trigger.kind)")
        }
    }

    /// ADR-0088 removed the one-shot `manual` trigger; a row that still says
    /// it, or any kind a newer backend adds, decodes without crashing.
    @Test(arguments: ["manual", "on_schedule"])
    func anUnknownTriggerDecodesAsUnknown(kind: String) {
        #expect(TriggerKind(wire: ["kind": kind]) == .unknown(kind: kind))
    }

    // MARK: - ControlSetResultView

    @Test
    func controlSetStatusMapsWireStrings() {
        #expect(ControlSetResultView.Status(wire: "applied") == .applied)
        #expect(ControlSetResultView.Status(wire: "awaiting_consent") == .awaitingConsent)
        #expect(ControlSetResultView.Status(wire: "weird") == .unknown("weird"))
    }

    // MARK: - AnyHashableJSON (catalog schema value)

    @Test
    func anyHashableJSONWrapsPrimitivesAndNesting() {
        #expect(AnyHashableJSON("hi") == .string("hi"))
        #expect(AnyHashableJSON(true) == .bool(true))
        #expect(AnyHashableJSON(3) == .number(3))
        #expect(AnyHashableJSON(["a": 1]) == .object(["a": .number(1)]))
        #expect(AnyHashableJSON([1, 2]) == .array([.number(1), .number(2)]))
        #expect(AnyHashableJSON(nil) == .null)
    }
}
