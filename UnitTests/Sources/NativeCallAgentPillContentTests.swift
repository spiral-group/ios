//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

/// The agent pill's contents, variant B of the pill audit (question 383): who at rest, what it does when it does
/// something, never what the screen already says.
struct NativeCallAgentPillContentTests {
    private let own = "Alex Sample · assistant"
    private let foreign = "Mira Testova · assistant"

    @Test
    func atRestThePillSaysOnlyWhoseAgentIsHere() {
        let mine = content(event: .idle(role: nil, languages: []), isOwn: true)
        #expect(mine.line == UntranslatedL10n.screenNativeCallAgentPillYourAssistant)
        #expect(mine.chip == nil)
        #expect(mine.slot == .avatar(isDimmed: false))
        #expect(mine.accessibilityLabel == UntranslatedL10n.a11yNativeCallAgentPillInCall(UntranslatedL10n.screenNativeCallAgentPillYourAssistant))

        let theirs = content(name: foreign, event: .idle(role: nil, languages: []))
        #expect(theirs.line == "Mira Testova", "the owner's name, without the role word")
    }

    /// Speaking is the Halo's, recording the header's REC, connecting or on hold the header's status (audit bugs 1, 2).
    @Test
    func whatTheScreenAlreadySaysIsNotRepeated() {
        for event: NativeCallAgentEvent in [.airing(.conversation),
                                            .idle(role: .recording, languages: []),
                                            .idle(role: .waiting, languages: []),
                                            .idle(role: .waitingForPeople, languages: [])] {
            let pill = content(event: event, isOwn: true)
            #expect(pill.line == UntranslatedL10n.screenNativeCallAgentPillYourAssistant, "\(event)")
            #expect(pill.chip == nil, "\(event)")
        }
    }

    /// A silent agent in a conversation listens (audit bug 8: it said "Talking").
    @Test
    func aSilentConversationListens() {
        let pill = content(event: .idle(role: .conversation, languages: []), isOwn: true)
        #expect(pill.line == UntranslatedL10n.screenNativeCallAgentPillListening)
        #expect(pill.chip == .listening)
        #expect(pill.accessibilityLabel == UntranslatedL10n.a11yNativeCallAgentBlockRole(UntranslatedL10n.screenNativeCallAgentPillYourAssistant,
                                                                                         UntranslatedL10n.screenNativeCallAgentPillListening))
    }

    /// Translating, airing or not, shows two codes and a count; VoiceOver names every language with the verb (bug 3).
    @Test
    func translationShowsCodesAndSaysTheLanguages() {
        for event: NativeCallAgentEvent in [.airing(.translation(languages: ["en", "de", "uk"])), .idle(role: nil, languages: ["en", "de", "uk"])] {
            let pill = content(event: event, isOwn: true)
            #expect(pill.line == UntranslatedL10n.screenNativeCallAgentPillTranslating)
            #expect(pill.chip == .translation(codes: ["EN", "DE"], more: 1))
            #expect(pill.accessibilityLabel == UntranslatedL10n.a11yNativeCallAgentBlockAiring(UntranslatedL10n.screenNativeCallAgentPillYourAssistant,
                                                                                               NativeCallAgentStatusCopy.spokenLanguages(["en", "de", "uk"])))
        }
    }

    /// Audit bug 5: `UK` reads as the United Kingdom.
    @Test
    func ukrainianReadsAsUkrainian() {
        #expect(NativeCallAgentPillContent.code("uk") == "UA")
        #expect(NativeCallAgentPillContent.code("pt-BR") == "PT")
        #expect(content(event: .idle(role: nil, languages: ["uk"]), isOwn: true).chip == .translation(codes: ["UA"], more: 0))
    }

    @Test
    func aPauseAndTheOriginalVoiceSayWhatTheyMean() {
        let paused = content(event: .paused, isOwn: true)
        #expect(paused.slot == .paused)
        #expect(paused.line == UntranslatedL10n.screenNativeCallAgentPillTranslationPaused)

        let original = content(event: .original, isOwn: true)
        #expect(original.line == UntranslatedL10n.screenNativeCallAgentPillOriginalVoice)
        #expect(original.chip == .originalVoice)
    }

    /// Notes have no other mark on screen, so they show even under a recording.
    @Test
    func notesShowEvenUnderARecording() {
        let pill = content(event: .idle(role: .recording, languages: []), isOwn: true, isTakingNotes: true)
        #expect(pill.line == UntranslatedL10n.screenNativeCallAgentPillTakingNotes)
        #expect(pill.chip == .notes)
    }

    @Test
    func aFailureNamesWhatWasNotDelivered() {
        let summary = content(event: .failure(.deliveryFailed), isOwn: true, failedDelivery: .summary)
        #expect(summary.slot == .failure)
        #expect(summary.isCritical)
        #expect(summary.line == UntranslatedL10n.screenNativeCallAgentPillSummaryNotSent)

        let recording = content(event: .failure(.deliveryFailed), isOwn: true, failedDelivery: .recording)
        #expect(recording.line == UntranslatedL10n.screenNativeCallAgentPillRecordingNotSaved)
    }

    /// Audit bug 12: a leaving agent said whatever it last did.
    @Test
    func aLeavingAgentSaysSoWhateverItWasDoing() {
        let pill = content(event: .airing(.translation(languages: ["en"])), isOwn: true, isLeaving: true)
        #expect(pill.slot == .avatar(isDimmed: true))
        #expect(pill.line == UntranslatedL10n.screenNativeCallAgentCenterLeaving)
        #expect(pill.chip == nil)
    }

    @Test
    func otherAgentsAreCountedOutLoud() {
        let pill = content(event: .idle(role: nil, languages: []), isOwn: true, otherAgentUserIDs: ["@b:x", "@c:x"])
        let spoken = UntranslatedL10n.a11yNativeCallAgentPillInCall(UntranslatedL10n.screenNativeCallAgentPillYourAssistant)
        #expect(pill.accessibilityLabel == UntranslatedL10n.a11yNativeCallAgentPillOtherAgents(spoken, 2))
    }

    // MARK: - Helpers

    private func content(name: String? = nil,
                         event: NativeCallAgentEvent,
                         isOwn: Bool = false,
                         isLeaving: Bool = false,
                         isTakingNotes: Bool = false,
                         failedDelivery: NativeCallAgentBlockState.Delivery? = nil,
                         otherAgentUserIDs: [String] = []) -> NativeCallAgentPillContent {
        NativeCallAgentPillContent(NativeCallAgentBlockState(name: name ?? own,
                                                             event: event,
                                                             agentUserID: "@assistant-alex:example.org",
                                                             isOwn: isOwn,
                                                             isLeaving: isLeaving,
                                                             isTakingNotes: isTakingNotes,
                                                             failedDelivery: failedDelivery,
                                                             otherAgentUserIDs: otherAgentUserIDs))
    }
}
