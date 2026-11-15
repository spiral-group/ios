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

    /// VoiceOver gets full names — the abbreviations are a space
    /// compromise, not the content.
    static func spokenLanguages(_ codes: [String]) -> String {
        codes.map { languageName($0) }.formatted(.list(type: .and))
    }

    // MARK: - The sheet

    /// The head's one line: leaving outranks everything, then what the
    /// agent produces — WHO into WHAT from its lanes, never a fixed
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
        if agent.shown.isStandby {
            return UntranslatedL10n.screenNativeCallAssistantsStatusStandby
        }
        if agent.shown.isTranslating {
            return UntranslatedL10n.screenNativeCallAgentCenterTranslationOn(lanesPhrase(agent, ownUserID: ownUserID, profiles: profiles, catalog: catalog))
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

    /// The lanes as one line, a language at a time: `you into X` / `Bohdan, Marta into X`; the intent's languages
    /// while it holds no lane (standing by, starting).
    static func lanesPhrase(_ agent: NativeCallAgentPresentation.Agent,
                            ownUserID: String?,
                            profiles: [String: NativeCallMemberProfile],
                            catalog: [VoiceControlsCatalogLanguage]) -> String {
        let byLanguage = Dictionary(grouping: agent.live.lanes, by: \.language)
        guard !byLanguage.isEmpty else { return languageList(agent.shown.languages, catalog: catalog) }
        return byLanguage.keys.sorted().map { language in
            let speakers = Set(byLanguage[language, default: []].map(\.speaker))
            let name = languageName(language, catalog: catalog)
            if let ownUserID, speakers == [ownUserID] {
                return UntranslatedL10n.screenNativeCallAgentCenterBoothYou(name)
            }
            return UntranslatedL10n.screenNativeCallAgentCenterBoothMembers(memberNames(speakers, profiles: profiles), name)
        }
        .joined(separator: " · ")
    }

    private static func memberNames(_ members: Set<String>, profiles: [String: NativeCallMemberProfile]) -> String {
        members.sorted()
            .map { profiles[$0]?.displayName ?? NativeCallFallbackName.make(mxid: $0) }
            .joined(separator: ", ")
    }
}
