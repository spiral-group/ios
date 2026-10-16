//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import ElementX
import Foundation
import Testing

// AGENT-PLATFORM (Brief 0063 closeout): the one wording layer over the
// presentation. Pins the ORDER of the sheet head, and that every row
// phrases the SHOWN register — never REST's.

struct NativeCallAgentStatusCopyTests {
    private let agentMxid = "@assistant-alice:spiral.md"
    private let ownMxid = "@alice:spiral.md"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func participant(_ mxid: String, role: NativeCallParticipant.Role, isLocal: Bool = false) -> NativeCallParticipant {
        NativeCallParticipant(id: "\(mxid):DEVICE",
                              userID: mxid,
                              role: role,
                              mediaState: .connected,
                              isSpeaking: false,
                              isAudioEnabled: true,
                              isLocal: isLocal)
    }

    private func agent(document: SpiralAgentStateReader.AgentClaim? = nil,
                       speaking: Bool = false,
                       session: NativeAgentCenterSession? = nil,
                       pendingWrites: [NativeAgentCenterPendingWrite] = []) -> NativeCallAgentPresentation.Agent {
        var claims = NativeCallAgentClaims()
        if let document { claims.documents[agentMxid] = document }
        if speaking { claims.speaking = [agentMxid] }
        var rest = NativeAgentCenterSnapshot(isAvailable: true, isLoading: false, sessions: session.map { [$0] } ?? [])
        rest.pendingOwnerWrites = pendingWrites.isEmpty ? [:] : [agentMxid: pendingWrites]
        let presentation = NativeCallAgentPresentation.derive(live: .init(participants: [participant(ownMxid, role: .human, isLocal: true),
                                                                                         participant(agentMxid, role: .agent)],
                                                                          claims: claims,
                                                                          ownUserID: ownMxid),
                                                              rest: rest,
                                                              now: now)
        return presentation.agents[0]
    }

    private func session(recording: Bool = false,
                         recordingStopped: Bool = false,
                         recordingDelivery: NativeAgentCenterArtifact.Delivery = .notArmed,
                         summary: Bool = false,
                         isEnding: Bool = false) -> NativeAgentCenterSession {
        NativeAgentCenterSession(sessionID: "session-1",
                                 agentMxid: agentMxid,
                                 canControl: true,
                                 isEnding: isEnding,
                                 recording: .init(isEnabled: recording, revision: 1, delivery: recordingDelivery, isStopped: recordingStopped),
                                 summary: .init(isEnabled: summary, revision: 1, delivery: .notArmed, isStopped: false),
                                 translation: .unknown,
                                 conversation: .unknown)
    }

    // MARK: - Head

    private func head(_ agent: NativeCallAgentPresentation.Agent) -> String {
        NativeCallAgentStatusCopy.headStatus(agent, ownUserID: ownMxid, profiles: [:], catalog: [])
    }

    @Test
    func theHeadOrdersLeavingOverTranslationOverTalkingOverRecordingOverSummaryOverReady() {
        #expect(head(agent(document: .make(languages: ["en"], recording: true, lifecycle: .leaving)))
            == UntranslatedL10n.screenNativeCallAgentCenterLeaving)
        #expect(head(agent(document: .make(languages: ["en"], recording: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone(NativeCallAgentStatusCopy.languageName("en"))))
        #expect(head(agent(document: .make(languages: ["en"], conversation: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone(NativeCallAgentStatusCopy.languageName("en"))))
        #expect(head(agent(document: .make(recording: true, conversation: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterTalking)
        #expect(head(agent(document: .make(recording: true, summaryArmed: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterRecordingLive)
        #expect(head(agent(document: .make(summaryArmed: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterSummaryOn)
        #expect(head(agent()) == UntranslatedL10n.screenNativeCallAgentBlockIdle)
    }

    /// The head phrases WHO the booths cover — an owner-only booth is
    /// "you into Russian", never "everyone" (operator, 2026-09-04).
    @Test
    func theHeadNamesWhoTheBoothsCover() {
        let me = agent(document: .make(languages: ["ru"], booths: [.init(coverage: .members([ownMxid]), targetLanguages: ["ru"])]))
        #expect(head(me) == UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(UntranslatedL10n.screenNativeCallAgentCenterBoothYou(NativeCallAgentStatusCopy.languageName("ru"))))
    }

    /// The user's locale names the language; the tenant catalog's English
    /// label is only the fallback ("вас на Russian" in a Russian UI).
    @Test
    func languagesAreNamedByTheLocaleNotTheCatalog() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "ru", label: "Russian"), .init(code: "zz", label: "Zed")]
        #expect(NativeCallAgentStatusCopy.languageName("ru", catalog: catalog) == Locale.current.localizedString(forLanguageCode: "ru"))
        #expect(NativeCallAgentStatusCopy.languageName("zz", catalog: catalog) == (Locale.current.localizedString(forLanguageCode: "zz") ?? "Zed"))
    }

    /// REST's flags alone word nothing on the head — the split-screen bug.
    @Test
    func theHeadIgnoresRestFlagsWithoutADocumentOrAWrite() {
        #expect(head(agent(session: session(recording: true, summary: true))) == UntranslatedL10n.screenNativeCallAgentBlockIdle)
        #expect(head(agent(session: session(isEnding: true))) == UntranslatedL10n.screenNativeCallAgentBlockIdle)
    }

    // MARK: - Rows

    @Test
    func theTranslationRowPhrasesTheDocumentsBooths() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "uk", label: "Ukrainian")]
        let open = agent(document: .make(languages: ["uk"]))
        #expect(NativeCallAgentStatusCopy.translationRow(open, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(UntranslatedL10n.screenNativeCallTranslationStyleLive, UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("Ukrainian")))

        let me = agent(document: .make(languages: ["uk"], booths: [.init(coverage: .members([ownMxid]), targetLanguages: ["uk"])]))
        #expect(NativeCallAgentStatusCopy.translationRow(me, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(UntranslatedL10n.screenNativeCallTranslationStyleLive, UntranslatedL10n.screenNativeCallAgentCenterBoothYou("Ukrainian")))

        let bohdan = agent(document: .make(languages: ["uk"], booths: [.init(coverage: .members(["@bob:spiral.md"]), targetLanguages: ["uk"])]))
        #expect(NativeCallAgentStatusCopy.translationRow(bohdan,
                                                         ownUserID: ownMxid,
                                                         profiles: ["@bob:spiral.md": .init(displayName: "Bohdan")],
                                                         catalog: catalog)
                == UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(UntranslatedL10n.screenNativeCallTranslationStyleLive, UntranslatedL10n.screenNativeCallAgentCenterBoothMembers("Bohdan", "Ukrainian")))

        let interpreter = agent(document: .make(languages: ["uk"], style: .consecutive))
        #expect(NativeCallAgentStatusCopy.translationRow(interpreter, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(UntranslatedL10n.screenNativeCallTranslationStyleInterpreter, UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("Ukrainian")))

        // A phantom-owner booth (`members []`) is not phrased.
        let phantom = agent(document: .make(languages: ["uk"], booths: [.init(coverage: .members([]), targetLanguages: ["uk"]),
                                                                        .init(coverage: .open, targetLanguages: ["uk"])]))
        #expect(NativeCallAgentStatusCopy.boothsPhrase(phantom, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("Ukrainian"))

        let paused = agent(document: .make(languages: ["uk"], paused: true))
        #expect(NativeCallAgentStatusCopy.translationRow(paused, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationPaused(UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("Ukrainian")))

        #expect(NativeCallAgentStatusCopy.translationRow(agent(), ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationOff)
    }

    /// Live wins; then the artifact's delivery; an armed artifact the
    /// document does not confirm is "Not recording", never "Stopped".
    @Test
    func theRecordingRowNeverInventsAStop() {
        #expect(NativeCallAgentStatusCopy.recordingRow(agent(document: .make(recording: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterRecordingLive)
        #expect(NativeCallAgentStatusCopy.recordingRow(agent(session: session(recording: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterRecordingOff)
        #expect(NativeCallAgentStatusCopy.recordingRow(agent(session: session(recording: true, recordingStopped: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterRecordingStopped)
        #expect(NativeCallAgentStatusCopy.recordingRow(agent(session: session(recording: true, recordingStopped: true, recordingDelivery: .pending)))
            == UntranslatedL10n.screenNativeCallAgentCenterDeliveryPending)
        #expect(NativeCallAgentStatusCopy.recordingRow(agent(session: session(recording: true, recordingDelivery: .failed)))
            == UntranslatedL10n.screenNativeCallAgentCenterDeliveryFailed)
        #expect(NativeCallAgentStatusCopy.recordingRow(agent()) == UntranslatedL10n.screenNativeCallAgentCenterRecordingOff)
    }

    @Test
    func theSummaryRowReadsTheShownRegister() {
        #expect(NativeCallAgentStatusCopy.summaryRow(agent(session: session(summary: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterSummaryOff)
        #expect(NativeCallAgentStatusCopy.summaryRow(agent(session: session(summary: true),
                                                           pendingWrites: [.init(fact: .summary(true), expiresAt: now.addingTimeInterval(10))]))
                == UntranslatedL10n.screenNativeCallAgentCenterSummaryOn)
    }

    /// Brief 0066 — the foreign row speaks in the owner-head's voice:
    /// leaving, then style · booths (+ a critical "Recording…" appended
    /// when it also captures), then the role, then "Ready".
    @Test
    func theForeignStatusIsTheOwnersVoiceWithTheCaptureAppended() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English")]
        func status(_ agent: NativeCallAgentPresentation.Agent) -> NativeCallAgentStatusCopy.ForeignStatus {
            NativeCallAgentStatusCopy.foreignStatus(agent, ownUserID: ownMxid, profiles: [:], catalog: catalog)
        }

        #expect(status(agent(document: .make(languages: ["en"], recording: true, lifecycle: .leaving)))
            == .init(text: UntranslatedL10n.screenNativeCallAgentCenterLeaving, hue: .secondary, appendsRecording: false))

        let live = status(agent(document: .make(languages: ["en"], recording: true, style: .simultaneous)))
        #expect(live.text == UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(UntranslatedL10n.screenNativeCallTranslationStyleLive,
                                                                                            UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("English")))
        #expect(live.appendsRecording)

        let interpreter = status(agent(document: .make(languages: ["en"], style: .consecutive)))
        #expect(interpreter.text.hasPrefix(UntranslatedL10n.screenNativeCallTranslationStyleInterpreter))
        #expect(!interpreter.appendsRecording)

        #expect(status(agent(document: .make(languages: ["en"], paused: true))).text
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationPaused(UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone("English")))
        #expect(status(agent(document: .make(recording: true)))
            == .init(text: UntranslatedL10n.screenNativeCallAgentCenterRecordingLive, hue: .critical, appendsRecording: false))
        // Brief 0080 — a talking agent says so, and a capture beside it is
        // never hidden behind the words.
        #expect(status(agent(document: .make(recording: true, conversation: true)))
            == .init(text: UntranslatedL10n.screenNativeCallAgentCenterTalking, hue: .secondary, appendsRecording: true))
        #expect(status(agent(document: .make(conversation: true))).appendsRecording == false)
        // While it answers, the line turns accent — as a translation's does.
        #expect(status(agent(document: .make(conversation: true), speaking: true)).hue == .accent)
        #expect(status(agent(document: .make(languages: ["en"]), speaking: true)).hue == .accent)
        #expect(status(agent(document: .make(summaryArmed: true))).text == UntranslatedL10n.screenNativeCallAgentCenterSummaryOn)
        #expect(status(agent()).text == UntranslatedL10n.screenNativeCallAgentBlockIdle)
    }

    /// `everyone except Alice into English` — the resolved exclusion
    /// scope, by profile name, MXID rule as the fallback.
    @Test
    func theBoothPhraseNamesExclusions() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English")]
        let except = agent(document: .make(languages: ["en"], booths: [.init(coverage: .exceptMembers(["@alice:spiral.md"]), targetLanguages: ["en"])]))
        #expect(NativeCallAgentStatusCopy.boothsPhrase(except,
                                                       ownUserID: ownMxid,
                                                       profiles: ["@alice:spiral.md": .init(displayName: "Alice")],
                                                       catalog: catalog)
                == UntranslatedL10n.screenNativeCallAgentCenterBoothEveryoneExcept("Alice", "English"))
        #expect(NativeCallAgentStatusCopy.boothsPhrase(except, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterBoothEveryoneExcept("Alice", "English"))
    }

    /// What a foreign booth means for MY ears, by style — and nothing
    /// when no booth covers me or the engine is paused.
    @Test
    func theCoversMeLineFollowsTheStyle() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English")]
        let live = agent(document: .make(languages: ["en"], style: .simultaneous))
        #expect(NativeCallAgentStatusCopy.coversMeLine(live, catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterCoversYouLive("English"))

        let interpreter = agent(document: .make(languages: ["en"], style: .consecutive))
        #expect(NativeCallAgentStatusCopy.coversMeLine(interpreter, catalog: catalog)
            == UntranslatedL10n.screenNativeCallAgentCenterCoversYouInterpreter("English"))

        let notMe = agent(document: .make(languages: ["en"], booths: [.init(coverage: .members(["@bob:spiral.md"]), targetLanguages: ["en"])]))
        #expect(NativeCallAgentStatusCopy.coversMeLine(notMe, catalog: catalog) == nil)

        let exceptMe = agent(document: .make(languages: ["en"], booths: [.init(coverage: .exceptMembers([ownMxid]), targetLanguages: ["en"])]))
        #expect(NativeCallAgentStatusCopy.coversMeLine(exceptMe, catalog: catalog) == nil)

        let paused = agent(document: .make(languages: ["en"], paused: true))
        #expect(NativeCallAgentStatusCopy.coversMeLine(paused, catalog: catalog) == nil)
    }

    /// Brief 0080 — the switch's row says what it does, from the shown
    /// register: the owner's tap reads at once.
    @Test
    func theConversationRowSaysWhatTheSwitchDoes() {
        #expect(NativeCallAgentStatusCopy.conversationRow(agent(document: .make(conversation: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterConversationOn)
        #expect(NativeCallAgentStatusCopy.conversationRow(agent(document: .make(recording: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterConversationOff)
        #expect(NativeCallAgentStatusCopy.conversationRow(agent(document: .make(),
                                                                pendingWrites: [.init(fact: .conversation(true), expiresAt: now.addingTimeInterval(10))]))
                == UntranslatedL10n.screenNativeCallAgentCenterConversationOn)
    }

    @Test
    func theBlockWordsEveryNonLanguageEvent() {
        #expect(NativeCallAgentStatusCopy.blockWord(.failure(.deliveryFailed)) == UntranslatedL10n.screenNativeCallAgentBlockNotDelivered)
        #expect(NativeCallAgentStatusCopy.blockWord(.paused) == UntranslatedL10n.screenNativeCallAgentBlockPaused)
        #expect(NativeCallAgentStatusCopy.blockWord(.original) == UntranslatedL10n.screenNativeCallAgentBlockOriginal)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: .conversation, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockTalking)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: .recording, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockRecording)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: .summary, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockSummary)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: .waiting, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockWaiting)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: .waitingForPeople, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockWaitingForPeople)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: nil, languages: [])) == UntranslatedL10n.screenNativeCallAgentBlockIdle)
        #expect(NativeCallAgentStatusCopy.blockWord(.idle(role: nil, languages: ["en"])) == nil)
        #expect(NativeCallAgentStatusCopy.blockWord(.airing(.translation(languages: ["en"]))) == nil)
        #expect(NativeCallAgentStatusCopy.blockWord(.airing(.conversation)) == UntranslatedL10n.screenNativeCallAgentBlockSpeaking)
    }

    /// VoiceOver says the assistant is answering, not translating.
    @Test
    func theBlockSaysOutLoudThatTheAssistantSpeaks() {
        #expect(NativeCallAgentStatusCopy.blockAccessibilityLabel(name: "Alice's Assistant", event: .airing(.conversation))
            == UntranslatedL10n.a11yNativeCallAgentBlockRole("Alice's Assistant", UntranslatedL10n.screenNativeCallAgentBlockSpeaking))
        #expect(NativeCallAgentStatusCopy.blockAccessibilityLabel(name: "Alice's Assistant", event: .airing(.translation(languages: ["en"])))
            == UntranslatedL10n.a11yNativeCallAgentBlockAiring("Alice's Assistant", NativeCallAgentStatusCopy.spokenLanguages(["en"])))
    }
}
