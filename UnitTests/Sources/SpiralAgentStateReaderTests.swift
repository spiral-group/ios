//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

/// Pins for the `spiral.agent.state` document contract (ADR-0071 D8,
/// doc v6 of ADR-0094 A.6) — the runtime writes it. nil = "no valid agent document" (fall
/// back to tracks); [] = "a real agent document with translation off".
struct SpiralAgentStateReaderTests {
    private func attributes(_ document: String) -> [String: String] {
        [SpiralAgentStateReader.attributeKey: document]
    }

    /// ADR-0094 A.6: the producing example, read whole.
    @Test
    func aV6TranslationFunctionIsReadWhole() throws {
        let doc = """
        {"v":6,"agent":true,"lifecycle":"live","leaving_reason":null,"call":"live","mode_epoch":7,"functions":[
            {"kind":"translation","active":true,"style":"simultaneous","source":"room_tool","for_language":"zh-Hans","pocket":null,
             "owner":"@bohdan:spiral.md",
             "lanes":[{"speaker":"@john:spiral.md","input":"voice","language":"zh-Hans"},
                      {"speaker":"@mira:spiral.md","input":"voice","language":"zh-Hans"}],
             "stopped":null},
            {"kind":"recording","active":true}
        ]}
        """
        let claim = try #require(SpiralAgentStateReader.agentClaim(attributes: attributes(doc)))

        #expect(claim.modeEpoch == 7)
        #expect(claim.leavingReason == nil)
        #expect(claim.isRecording)
        #expect(claim.translation == .init(isActive: true,
                                           style: .simultaneous,
                                           source: .roomTool,
                                           forLanguage: "zh-Hans",
                                           pocket: nil,
                                           owner: "@bohdan:spiral.md",
                                           lanes: [.init(speaker: "@john:spiral.md", language: "zh-Hans"),
                                                   .init(speaker: "@mira:spiral.md", language: "zh-Hans")],
                                           stoppedReason: nil))
        // The catalog's exact code, never lowered or cut to its base.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(doc)) == ["zh-Hans"])
    }

    /// D12: a lane with an input this build doesn't know is left out; the others stay.
    @Test
    func aLaneWithAnUnknownInputIsLeftOut() {
        let doc = """
        {"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"for_language":"uk","owner":"@a:x",
          "lanes":[{"speaker":"@a:x","input":"device","language":"uk"},{"speaker":"@b:x","input":"voice","language":"uk"},
                   {"speaker":"@c:x","language":"uk"},{"speaker":7,"input":"voice","language":"uk"}]}]}
        """
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(doc))?.translation.lanes == [.init(speaker: "@b:x", language: "uk")])
    }

    /// A.6: standing by is `active: false, lanes: [], stopped: null`; it asks for its language and airs nothing.
    @Test
    func aStandbyAsksForItsLanguageAndAirsNothing() throws {
        let doc = #"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":false,"for_language":"uk","lanes":[],"stopped":null}]}"#
        let translation = try #require(SpiralAgentStateReader.agentClaim(attributes: attributes(doc))?.translation)

        #expect(translation.isStandby)
        #expect(translation.languages == ["uk"])
        #expect(translation.producedLanguages.isEmpty)
    }

    /// D6: every stop reason, and one newer than this build, which reads as `ended` — never "the owner stopped".
    @Test(arguments: [("owner_stopped", VoiceTranslationStopReason.ownerStopped), ("owner_left", .ownerLeft), ("ai_limit", .aiLimit),
                      ("translation_paused", .translationPaused), ("call_cap", .callCap), ("ended", .ended), ("moderator_said_so", .ended)])
    func aStopReasonIsReadAndAnUnknownOneIsEnded(wire: String, reason: VoiceTranslationStopReason) throws {
        let stopped = #"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":false,"for_language":"uk","lanes":[],"stopped":{"reason":"\#(wire)"}}]}"#
        let translation = try #require(SpiralAgentStateReader.agentClaim(attributes: attributes(stopped))?.translation)
        #expect(translation.stoppedReason == reason)
        #expect(translation.languages.isEmpty)
        #expect(!translation.isStandby)

        let leaving = #"{"v":6,"agent":true,"lifecycle":"leaving","leaving_reason":"\#(wire)","functions":[]}"#
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(leaving))?.leavingReason == reason)
    }

    @Test
    func thePocketInterpreterAsksForBothLanguages() {
        let doc = #"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"style":"consecutive","for_language":null,"pocket":["uk","en"],"owner":"@a:x","lanes":[{"speaker":"@a:x","input":"voice","language":"uk"},{"speaker":"@a:x","input":"voice","language":"en"}]}]}"#
        let translation = SpiralAgentStateReader.agentClaim(attributes: attributes(doc))?.translation
        #expect(translation?.pocket == ["uk", "en"])
        #expect(translation?.languages == ["uk", "en"])
        #expect(translation?.style == .consecutive)
    }

    @Test
    func aValidDocumentWithoutActiveTranslationIsOffNotUnknown() {
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[]}"#)) == [])
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#)) == [])
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[]}"#))?.translation == SpiralAgentStateReader.TranslationClaim.none)
    }

    /// Decision 97: every document carries `lifecycle` (the runtime
    /// republishes in the current shape on deploy). One without it is
    /// malformed, not live: no document at all.
    @Test
    func aDocumentWithoutLifecycleIsNoDocument() {
        let doc = #"{"v":6,"agent":true,"functions":[{"kind":"recording","active":true},{"kind":"translation","active":true,"for_language":"uk","lanes":[]}]}"#

        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(doc)) == nil)
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(doc)) == nil)
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: attributes(doc)))
        #expect(SpiralAgentStateReader.agentDocument(attributes: attributes(doc)) == nil)
    }

    @Test
    func anythingThatIsNotAValidAgentDocumentIsUnknown() {
        // No attribute at all (a human participant).
        #expect(SpiralAgentStateReader.translationLanguages(attributes: [:]) == nil)
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes("")) == nil)
        // Malformed JSON.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes("not json")) == nil)
        // Valid JSON that is not an agent document.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":2,"agent":false,"functions":[]}"#)) == nil)
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"agent":true,"functions":[]}"#)) == nil)
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"[1,2,3]"#)) == nil)
        // An unrelated attribute key changes nothing.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: ["other.key": #"{"v":2,"agent":true}"#]) == nil)
    }

    /// Doc v5 (decision 182): the runtime's call gate. Anything this build
    /// does not know, or its absence, is no claim — never "waiting".
    @Test
    func theCallGateIsReadFromTheDocumentAndUnknownIsNoClaim() {
        func gate(_ call: String) -> SpiralAgentStateReader.CallGate? {
            SpiralAgentStateReader.agentClaim(attributes: attributes(#"{"v":5,"agent":true,"lifecycle":"live",\#(call)"functions":[]}"#))?.callGate
        }
        #expect(gate(#""call":"waiting","#) == .waiting)
        #expect(gate(#""call":"live","#) == .live)
        #expect(gate(#""call":"ringing","#) == nil)
        #expect(gate(#""call":5,"#) == nil)
        #expect(gate("") == nil)
    }

    /// Question 404: an armed recording (`active: false`) still holds the call's one recording; only a recording
    /// function gone lets it go.
    @Test
    func anArmedRecordingHoldsTheCall() throws {
        let armed = try #require(SpiralAgentStateReader.agentClaim(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":false}]}"#)))
        #expect(armed.holdsRecording)
        #expect(!armed.isRecording)
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#))?.holdsRecording == true)
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(#"{"v":6,"agent":true,"lifecycle":"live","functions":[]}"#))?.holdsRecording == false)
    }

    @Test
    func aLiveRecordingClaimIsReadFromAnyAgentDocument() {
        // The active claim, alone or beside translation.
        #expect(SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#)))
        let mixed = #"{"v":6,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"for_language":"uk","lanes":[]},{"kind":"recording","active":true}]}"#
        #expect(SpiralAgentStateReader.isRecordingActive(attributes: attributes(mixed)))
        // Absent, inactive, or malformed claims read as not recording.
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[]}"#)))
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":false}]}"#)))
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording"}]}"#)))
        // Not an agent document at all.
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: [:]))
        #expect(!SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"agent":true}"#)))
    }

    @Test
    func malformedFunctionEntriesFailSoftInsideAValidDocument() {
        let doc = """
        {"v":6,"agent":true,"lifecycle":"live","functions":[
            {"kind":"translation","active":true,"for_language":"uk","lanes":[{"speaker":"@a:x","input":"voice","language":"uk"},7,null]},
            {"active":true},
            "garbage"
        ]}
        """
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(doc)) == ["uk"])
    }

    /// v4 (Brief 0080): a `conversation` function says the agent talks;
    /// its absence says it is silent. Unknown fields and kinds beside it
    /// change nothing, and an inactive or malformed entry is silent.
    @Test
    func theConversationFunctionSaysTheAgentTalks() {
        let talking = #"{"v":4,"agent":true,"lifecycle":"live","future":{"x":1},"functions":[{"kind":"recording","active":true},{"kind":"conversation","active":true,"since":"2026-10-10"},{"kind":"telepathy","active":true}]}"#
        let claim = SpiralAgentStateReader.agentClaim(attributes: attributes(talking))
        #expect(claim?.isConversationActive == true)
        #expect(claim?.isRecording == true)

        let silent = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(silent))?.isConversationActive == false)
        let inactive = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"conversation","active":false}]}"#
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(inactive))?.isConversationActive == false)
        let malformed = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"conversation","active":"yes"},{"kind":"conversation"}]}"#
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(malformed))?.isConversationActive == false)
    }
}
