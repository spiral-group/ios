//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Foundation
@testable import Spiral
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
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(NativeCallAgentStatusCopy.languageName("en")))
        #expect(head(agent(document: .make(languages: ["en"], conversation: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(NativeCallAgentStatusCopy.languageName("en")))
        #expect(head(agent(document: .make(recording: true, conversation: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterTalking)
        #expect(head(agent(document: .make(recording: true, summaryArmed: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterRecordingLive)
        #expect(head(agent(document: .make(summaryArmed: true)))
            == UntranslatedL10n.screenNativeCallAgentCenterSummaryOn)
        #expect(head(agent()) == UntranslatedL10n.screenNativeCallAgentBlockIdle)
    }

    /// The head phrases WHO its lanes carry — only your voice is
    /// "you into Russian", never "everyone" (operator, 2026-09-04).
    @Test
    func theHeadNamesWhoTheLanesCarry() {
        let me = agent(document: .make(languages: ["ru"], speakers: [ownMxid]))
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

    /// The speakers its lanes carry, by profile name, MXID rule as the fallback; a lane language at a time.
    @Test
    func theLanesPhraseNamesItsSpeakersPerLanguage() {
        let catalog: [VoiceControlsCatalogLanguage] = [.init(code: "en", label: "English")]
        let others = agent(document: .make(languages: ["en"], speakers: ["@marta:spiral.md"]))
        #expect(NativeCallAgentStatusCopy.lanesPhrase(others,
                                                      ownUserID: ownMxid,
                                                      profiles: ["@marta:spiral.md": .init(displayName: "Marta")],
                                                      catalog: catalog)
                == UntranslatedL10n.screenNativeCallAgentCenterBoothMembers("Marta", NativeCallAgentStatusCopy.languageName("en", catalog: catalog)))
        // Standing by, it airs nothing yet: its language alone.
        let standby = agent(document: .make(languages: ["en"]))
        #expect(NativeCallAgentStatusCopy.lanesPhrase(standby, ownUserID: ownMxid, profiles: [:], catalog: catalog)
            == NativeCallAgentStatusCopy.languageName("en", catalog: catalog))
    }
}
