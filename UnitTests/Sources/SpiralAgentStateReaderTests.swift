//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Testing

/// Pins for the `spiral.agent.state` document contract (ADR-0071 D8,
/// doc v4) — the runtime writes it. nil = "no valid agent document" (fall
/// back to tracks); [] = "a real agent document with translation off".
struct SpiralAgentStateReaderTests {
    private func attributes(_ document: String) -> [String: String] {
        [SpiralAgentStateReader.attributeKey: document]
    }

    @Test
    func anActiveTranslationFunctionYieldsItsLanguagesDedupedAndSorted() {
        let doc = """
        {"v":4,"agent":true,"lifecycle":"live","functions":[
            {"kind":"translation","active":true,"target_languages":["uk","de","uk"],"style":"consecutive",
             "booths":[{"speaker_scope":"anyone","speaker_members":[],"target_languages":["uk"]}]},
            {"kind":"recording","active":true}
        ]}
        """
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(doc)) == ["de", "uk"])
    }

    @Test
    func aValidDocumentWithoutActiveTranslationIsOffNotUnknown() {
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[]}"#)) == [])
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#)) == [])
        // An inactive translation function counts as off too.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":false,"target_languages":["uk"]}]}"#)) == [])
    }

    /// Decision 97: every document carries `lifecycle` (the runtime
    /// republishes in the current shape on deploy). One without it is
    /// malformed, not live: no document at all.
    @Test
    func aDocumentWithoutLifecycleIsNoDocument() {
        let doc = #"{"v":4,"agent":true,"functions":[{"kind":"recording","active":true},{"kind":"translation","active":true,"target_languages":["uk"],"booths":[]}]}"#

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

    @Test
    func aLiveRecordingClaimIsReadFromAnyAgentDocument() {
        // The active claim, alone or beside translation.
        #expect(SpiralAgentStateReader.isRecordingActive(attributes: attributes(#"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"recording","active":true}]}"#)))
        let mixed = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"target_languages":["uk"]},{"kind":"recording","active":true}]}"#
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
        {"v":4,"agent":true,"lifecycle":"live","functions":[
            {"kind":"translation","active":true,"target_languages":["uk",7,null,"ru"]},
            {"active":true},
            "garbage"
        ]}
        """
        // Garbage entries are skipped per entry (EC parity), non-string
        // languages are dropped — the valid languages survive.
        #expect(SpiralAgentStateReader.translationLanguages(attributes: attributes(doc)) == ["ru", "uk"])
    }

    /// Brief 0066 — coverage arrives RESOLVED: three shapes, phrased
    /// without knowing the owner. Only `anyone` is open: an open booth ducks
    /// every remote human's original. A scope this build does not know (the
    /// raw tool scopes from before 0066 among them, decision 97) or a missing
    /// one covers nobody, as the engine reads it (it matches nothing), so
    /// originals stay at full level. `everyone_except` with no members
    /// excludes nobody: the engine translates everyone.
    @Test
    func boothCoverageReadsTheResolvedVocabularyOnly() throws {
        let doc = """
        {"v":3,"agent":true,"lifecycle":"live","functions":[
            {"kind":"translation","active":true,"target_languages":["uk","en"],"style":"simultaneous",
             "booths":[
               {"speaker_scope":"anyone","speaker_members":[],"target_languages":["uk"]},
               {"speaker_scope":"everyone_except","speaker_members":["@emmm:spiral.md"],"target_languages":["en"]},
               {"speaker_scope":"members","speaker_members":["@bob:spiral.md"],"target_languages":["uk"]},
               {"speaker_scope":"owner_only","speaker_members":["@emmm:spiral.md"],"target_languages":["en"]},
               {"speaker_scope":"non_self_non_owner","speaker_members":["@emmm:spiral.md"],"target_languages":["en"]},
               {"speaker_scope":"specific_senders","speaker_members":["@bob:spiral.md"],"target_languages":["en"]},
               {"speaker_scope":"non_self_non_owner","speaker_members":[],"target_languages":["en"]},
               {"speaker_scope":"members","speaker_members":[],"target_languages":["en"]},
               {"speaker_members":["@bob:spiral.md"],"target_languages":["en"]},
               {"speaker_scope":"everyone_except","speaker_members":[],"target_languages":["en"]}
             ]}
        ]}
        """
        let claim = try #require(SpiralAgentStateReader.agentClaim(attributes: attributes(doc)))
        let coverages = claim.translation.activeBooths.map(\.coverage)
        #expect(coverages == [.open,
                              .exceptMembers(["@emmm:spiral.md"]),
                              .members(["@bob:spiral.md"]),
                              // Unknown scopes cover nobody, never everyone.
                              .members([]),
                              .members([]),
                              .members([]),
                              .members([]),
                              // A phantom-owner booth covers NOBODY, never everyone.
                              .members([]),
                              // No scope at all is malformed: nobody.
                              .members([]),
                              .open])
        #expect(claim.translation.style == .simultaneous)

        #expect(SpiralAgentStateReader.BoothCoverage.open.covers("@x:h"))
        #expect(!SpiralAgentStateReader.BoothCoverage.exceptMembers(["@x:h"]).covers("@x:h"))
        #expect(SpiralAgentStateReader.BoothCoverage.exceptMembers(["@x:h"]).covers("@y:h"))
        #expect(SpiralAgentStateReader.BoothCoverage.members(["@x:h"]).covers("@x:h"))
        #expect(!SpiralAgentStateReader.BoothCoverage.members(["@x:h"]).covers("@y:h"))
    }

    /// The runtime publishes every translation function with its booths
    /// (decision 97: it republishes the document in this shape once on
    /// deploy). A function without them, the shape before 0066, is not read
    /// as an open booth any more: it covers nobody, so nobody's original is
    /// ducked for it.
    @Test
    func aTranslationWithoutBoothsCoversNobody() {
        let doc = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"target_languages":["en-US","de"]}]}"#
        let claim = SpiralAgentStateReader.agentClaim(attributes: attributes(doc))

        #expect(claim?.translation.activeBooths == [])
        #expect(claim?.translation.activeLanguages == ["de", "en"])
        // Nor does an explicit empty list.
        let empty = #"{"v":4,"agent":true,"lifecycle":"live","functions":[{"kind":"translation","active":true,"target_languages":["en"],"booths":[]}]}"#
        #expect(SpiralAgentStateReader.agentClaim(attributes: attributes(empty))?.translation.activeBooths == [])
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
