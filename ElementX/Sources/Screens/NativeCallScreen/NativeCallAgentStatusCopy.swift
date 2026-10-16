//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 closeout): every WORD any surface says about
// an agent, mapped from `NativeCallAgentPresentation` in one place.
//
// Before: fifteen status-string sites and four language formatters across
// the block, the sheet head, three control rows and the foreign row —
// each free to phrase the same fact differently, and each a place where a
// REST value could sneak into a live sentence. The presentation is
// string-free (`NativeCallAgentEvent` carries roles, not words); this
// enum is the only translator.

import Foundation

enum NativeCallAgentStatusCopy {
    // MARK: - Languages

    /// `English` / `русский` — the user's LOCALE name for a code, so every
    /// surface names languages in the language the user reads. The
    /// tenant catalog's label (English on the wire) is only the fallback
    /// for a code the locale cannot name; the code itself is the last
    /// resort. (Operator, 2026-09-04: a Russian UI said "вас на Russian"
    /// because the catalog label won.)
    static func languageName(_ code: String, catalog: [VoiceControlsCatalogLanguage] = []) -> String {
        Locale.current.localizedString(forLanguageCode: code)
            ?? catalog.first { $0.code == code }?.label
            ?? code
    }

    /// `English, German` — the list form for prose.
    static func languageList(_ codes: [String], catalog: [VoiceControlsCatalogLanguage] = []) -> String {
        codes.map { languageName($0, catalog: catalog) }.joined(separator: ", ")
    }

    /// The block's list: the produced language spelled out, the trailing
    /// lanes as codes — three full names do not fit a phone width.
    static func blockLanguageLabel(_ code: String, isLeading: Bool) -> String {
        isLeading ? (Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()) : code.uppercased()
    }

    /// VoiceOver gets full names — the abbreviations are a space
    /// compromise, not the content.
    static func spokenLanguages(_ codes: [String]) -> String {
        codes.map { languageName($0) }.formatted(.list(type: .and))
    }

    /// `Live` / `Interpreter` — the style as a noun.
    static func styleName(_ style: SpiralAgentStateReader.TranslationStyle?) -> String {
        style == .consecutive
            ? UntranslatedL10n.screenNativeCallTranslationStyleInterpreter
            : UntranslatedL10n.screenNativeCallTranslationStyleLive
    }

    // MARK: - The block

    /// The block's word for an event that is not a language list; nil
    /// when the event renders languages instead.
    static func blockWord(_ event: NativeCallAgentEvent) -> String? {
        switch event {
        case .failure(.deliveryFailed): UntranslatedL10n.screenNativeCallAgentBlockNotDelivered
        case .airing(.translation): nil
        case .airing(.conversation): UntranslatedL10n.screenNativeCallAgentBlockSpeaking
        case .paused: UntranslatedL10n.screenNativeCallAgentBlockPaused
        case .original: UntranslatedL10n.screenNativeCallAgentBlockOriginal
        case .idle(let role, let languages):
            switch role {
            case .conversation: UntranslatedL10n.screenNativeCallAgentBlockTalking
            case .recording: UntranslatedL10n.screenNativeCallAgentBlockRecording
            case .summary: UntranslatedL10n.screenNativeCallAgentBlockSummary
            case .waiting: UntranslatedL10n.screenNativeCallAgentBlockWaiting
            case .waitingForPeople: UntranslatedL10n.screenNativeCallAgentBlockWaitingForPeople
            case nil: languages.isEmpty ? UntranslatedL10n.screenNativeCallAgentBlockIdle : nil
            }
        }
    }

    static func blockAccessibilityLabel(name: String, event: NativeCallAgentEvent) -> String {
        switch event {
        case .airing(.translation(let languages)):
            UntranslatedL10n.a11yNativeCallAgentBlockAiring(name, spokenLanguages(languages))
        case .idle(nil, let languages) where !languages.isEmpty:
            UntranslatedL10n.a11yNativeCallAgentBlockRole(name, spokenLanguages(languages))
        case .idle(nil, _):
            UntranslatedL10n.a11yNativeCallAgentBlockIdle(name)
        default:
            UntranslatedL10n.a11yNativeCallAgentBlockRole(name, blockWord(event) ?? "")
        }
    }

    /// `1 of 2 agents`.
    static func agentCountLine(_ ordinal: NativeCallAgentPresentation.Agent.Ordinal?) -> String? {
        ordinal.map { UntranslatedL10n.screenNativeCallAgentBlockCount($0.index, $0.count) }
    }

    // MARK: - The sheet

    /// The head's one line: leaving outranks everything, then what the
    /// agent produces — WHO into WHAT from the booths, never a fixed
    /// "everyone" (operator, 2026-09-04: an owner-only booth read
    /// "Переводит всех") — then whether it talks, then its role, then
    /// "Ready".
    static func headStatus(_ agent: NativeCallAgentPresentation.Agent,
                           ownUserID: String?,
                           profiles: [String: NativeCallMemberProfile],
                           catalog: [VoiceControlsCatalogLanguage]) -> String {
        if agent.shown.presence == .leaving {
            return UntranslatedL10n.screenNativeCallAgentCenterLeaving
        }
        if agent.shown.isTranslating {
            return UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(boothsPhrase(agent, ownUserID: ownUserID, profiles: profiles, catalog: catalog))
        }
        if agent.shown.isConversationActive {
            return UntranslatedL10n.screenNativeCallAgentCenterTalking
        }
        if agent.shown.isRecording {
            return UntranslatedL10n.screenNativeCallAgentCenterRecordingLive
        }
        if agent.shown.isSummaryArmed {
            return UntranslatedL10n.screenNativeCallAgentCenterSummaryOn
        }
        return UntranslatedL10n.screenNativeCallAgentBlockIdle
    }

    /// `Live · everyone into Ukrainian` / `Interpreter · Bohdan into
    /// English`: the STYLE as the prefix (running is implied — a stalled
    /// engine says `Paused`), WHO into WHAT from the booths the engine
    /// actually runs (the document's, resolved; "you" when a booth's
    /// members are just us). The owner's CAS override is never phrased
    /// here: after a refused or displaced write it would name a
    /// configuration nobody hears.
    static func translationRow(_ agent: NativeCallAgentPresentation.Agent,
                               ownUserID: String?,
                               profiles: [String: NativeCallMemberProfile],
                               catalog: [VoiceControlsCatalogLanguage]) -> String {
        guard agent.shown.isTranslating else {
            return UntranslatedL10n.screenNativeCallAgentCenterTranslationOff
        }
        let phrase = boothsPhrase(agent, ownUserID: ownUserID, profiles: profiles, catalog: catalog)
        return agent.shown.isPaused
            ? UntranslatedL10n.screenNativeCallAgentCenterTranslationPaused(phrase)
            : UntranslatedL10n.screenNativeCallAgentCenterTranslationRunning(styleName(agent.shown.style), phrase)
    }

    /// The booth list as one line; the shown languages when the document
    /// has no booths (a pre-v2 runtime).
    static func boothsPhrase(_ agent: NativeCallAgentPresentation.Agent,
                             ownUserID: String?,
                             profiles: [String: NativeCallMemberProfile],
                             catalog: [VoiceControlsCatalogLanguage]) -> String {
        // A booth covering nobody (`members []` — a phantom owner) is not
        // phrased: "nobody into English" is noise, not information.
        let booths = agent.live.booths
            .filter { if case .members(let members) = $0.coverage { !members.isEmpty } else { true } }
            .map { booth in
                boothPhrase(coverage: booth.coverage,
                            languages: booth.targetLanguages,
                            ownUserID: ownUserID,
                            profiles: profiles,
                            catalog: catalog)
            }
        return booths.isEmpty ? languageList(agent.shown.languages, catalog: catalog) : booths.joined(separator: " · ")
    }

    /// A resolved booth: `everyone into X` / `you into X` / `Bohdan, Marta
    /// into X` / `everyone except Alice into X`.
    static func boothPhrase(coverage: SpiralAgentStateReader.BoothCoverage,
                            languages: [String],
                            ownUserID: String?,
                            profiles: [String: NativeCallMemberProfile],
                            catalog: [VoiceControlsCatalogLanguage]) -> String {
        let names = languageList(languages, catalog: catalog)
        switch coverage {
        case .open:
            return UntranslatedL10n.screenNativeCallAgentCenterBoothEveryone(names)
        case .members(let members) where ownUserID.map { members == [$0] } == true:
            return UntranslatedL10n.screenNativeCallAgentCenterBoothYou(names)
        case .members(let members):
            return UntranslatedL10n.screenNativeCallAgentCenterBoothMembers(memberNames(members, profiles: profiles), names)
        case .exceptMembers(let members):
            return UntranslatedL10n.screenNativeCallAgentCenterBoothEveryoneExcept(memberNames(members, profiles: profiles), names)
        }
    }

    private static func memberNames(_ members: Set<String>, profiles: [String: NativeCallMemberProfile]) -> String {
        members.sorted()
            .map { profiles[$0]?.displayName ?? NativeCallFallbackName.make(mxid: $0) }
            .joined(separator: ", ")
    }

    /// The recording row: the SHOWN live truth first (the same fact the
    /// capsule and the header show), then the artifact's delivery truth —
    /// a stopped artifact must never read as simply "on", and an armed
    /// one the document does not confirm is not "Stopped" either.
    static func recordingRow(_ agent: NativeCallAgentPresentation.Agent) -> String {
        if agent.shown.isRecording {
            return UntranslatedL10n.screenNativeCallAgentCenterRecordingLive
        }
        guard let artifact = agent.control?.recording, artifact.isEnabled else {
            return UntranslatedL10n.screenNativeCallAgentCenterRecordingOff
        }
        return artifactDelivery(artifact, isRecording: true)
            ?? UntranslatedL10n.screenNativeCallAgentCenterRecordingOff
    }

    static func summaryRow(_ agent: NativeCallAgentPresentation.Agent) -> String {
        agent.shown.isSummaryArmed
            ? UntranslatedL10n.screenNativeCallAgentCenterSummaryOn
            : UntranslatedL10n.screenNativeCallAgentCenterSummaryOff
    }

    /// Brief 0080 — what the switch means, in the SHOWN register: the owner's
    /// tap reads at once, a refused one falls back with the document.
    static func conversationRow(_ agent: NativeCallAgentPresentation.Agent) -> String {
        agent.shown.isConversationActive
            ? UntranslatedL10n.screenNativeCallAgentCenterConversationOn
            : UntranslatedL10n.screenNativeCallAgentCenterConversationOff
    }

    /// Delivery as the backend sees it.
    static func artifactDelivery(_ artifact: NativeAgentCenterArtifact, isRecording: Bool) -> String? {
        switch artifact.delivery {
        case .pending:
            UntranslatedL10n.screenNativeCallAgentCenterDeliveryPending
        case .failed:
            UntranslatedL10n.screenNativeCallAgentCenterDeliveryFailed
        case .delivered(let target):
            target == "owner_dm"
                ? UntranslatedL10n.screenNativeCallAgentCenterDeliveredToOwnerDm
                : UntranslatedL10n.screenNativeCallAgentCenterDeliveredToRoom
        case .notArmed:
            isRecording && artifact.isStopped ? UntranslatedL10n.screenNativeCallAgentCenterRecordingStopped : nil
        }
    }

    /// The foreign row's status line — the same voice as the owner's head:
    /// leaving, then what it translates (style · booths), then whether it
    /// talks, then its role, then "Ready". `appendsRecording` asks the row
    /// to add the critical "Recording…" beside a translating or talking
    /// status, so a capture is never hidden behind either.
    struct ForeignStatus: Equatable {
        enum Hue: Equatable {
            case secondary, accent, critical
        }

        let text: String
        let hue: Hue
        let appendsRecording: Bool
    }

    static func foreignStatus(_ agent: NativeCallAgentPresentation.Agent,
                              ownUserID: String?,
                              profiles: [String: NativeCallMemberProfile],
                              catalog: [VoiceControlsCatalogLanguage]) -> ForeignStatus {
        if agent.shown.presence == .leaving {
            return .init(text: UntranslatedL10n.screenNativeCallAgentCenterLeaving, hue: .secondary, appendsRecording: false)
        }
        if agent.shown.isTranslating {
            return .init(text: translationRow(agent, ownUserID: ownUserID, profiles: profiles, catalog: catalog),
                         hue: agent.shown.isAiring ? .accent : .secondary,
                         appendsRecording: agent.shown.isRecording)
        }
        if agent.shown.isConversationActive {
            return .init(text: UntranslatedL10n.screenNativeCallAgentCenterTalking,
                         hue: agent.shown.isAiring ? .accent : .secondary,
                         appendsRecording: agent.shown.isRecording)
        }
        if agent.shown.isRecording {
            return .init(text: UntranslatedL10n.screenNativeCallAgentCenterRecordingLive, hue: .critical, appendsRecording: false)
        }
        if agent.shown.isSummaryArmed {
            return .init(text: UntranslatedL10n.screenNativeCallAgentCenterSummaryOn, hue: .secondary, appendsRecording: false)
        }
        return .init(text: UntranslatedL10n.screenNativeCallAgentBlockIdle, hue: .secondary, appendsRecording: false)
    }

    /// `Translates you into English — others hear it, you don't`: what a
    /// foreign agent's booth means for MY ears. Nil when none covers me.
    static func coversMeLine(_ agent: NativeCallAgentPresentation.Agent, catalog: [VoiceControlsCatalogLanguage]) -> String? {
        guard agent.shown.isTranslating, !agent.shown.isPaused else { return nil }
        switch agent.live.coversMe {
        case .live(let languages):
            return UntranslatedL10n.screenNativeCallAgentCenterCoversYouLive(languageList(languages, catalog: catalog))
        case .interpreter(let languages):
            return UntranslatedL10n.screenNativeCallAgentCenterCoversYouInterpreter(languageList(languages, catalog: catalog))
        case nil:
            return nil
        }
    }

    /// The remove card: the receipt of a tap that is under way.
    static func removeButton(_ agent: NativeCallAgentPresentation.Agent) -> String {
        agent.shown.presence == .leaving
            ? UntranslatedL10n.screenNativeCallAgentCenterLeaving
            : UntranslatedL10n.screenNativeCallAgentCenterRemove
    }
}
