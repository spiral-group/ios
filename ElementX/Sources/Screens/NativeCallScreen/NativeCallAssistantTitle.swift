//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the title of a call with one's own assistant. The platform names an
// assistant after its owner with the role after a middle dot ("Alex Sample · assistant", in the owner's language),
// and the call's header set that whole string in heavy type on two lines. The page shows the name on one line and the
// role quietly under it.

import Foundation

nonisolated struct NativeCallAssistantTitle: Equatable {
    let name: String
    /// Nil when the display name carries no role.
    let role: String?

    init(displayName: String) {
        let whole = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // The last dot: a name may hold one of its own.
        if let dot = whole.range(of: "·", options: .backwards) {
            let name = whole[..<dot.lowerBound].trimmingCharacters(in: .whitespaces)
            let role = whole[dot.upperBound...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !role.isEmpty {
                self.name = name
                self.role = role
                return
            }
        }
        name = whole
        role = nil
    }
}

extension NativeCallAgentStatusCopy {
    /// The one line under the assistant's page title, only for what its Aura can't show and the person must know: an
    /// error, a recording. Speaking, listening, waiting and the like are the ring's (operator, 2026-11-08), so nothing
    /// is said for them. The interpreter's language is the avatar's badge (L12, `NativeCallAvatarBadge`): only the
    /// neighbour's is chosen, so a "my · neighbour" pair here would mislead.
    static func assistantPageLine(_ event: NativeCallAgentEvent) -> String? {
        switch event {
        case .failure:
            return UntranslatedL10n.screenNativeCallAgentBlockNotDelivered
        case .idle(.recording, _):
            return UntranslatedL10n.screenNativeCallAgentBlockRecording
        default:
            return nil
        }
    }
}

/// L12 (operator's option A, 2026-11-11, then "one visual everywhere"): the translation badge on an avatar, «文 ES» at
/// its bottom-trailing edge. On the assistant's page, the pocket interpreter's other side — the neighbour's language
/// only — while it produces or its new mode syncs (then ringed, as a job asked for is). On a person's avatar, the
/// language you hear them in, while you listen to a translation that covers them.
struct NativeCallAvatarBadge: Equatable {
    enum Kind: Equatable {
        /// The private call's pocket interpreter.
        case interpreter
        /// A person you hear translated.
        case heardIn
    }

    let language: String
    /// The runtime hasn't taken the new mode yet (ADR-0094 A.3 `syncing`).
    let isPending: Bool
    var kind = Kind.interpreter

    /// Nil unless `agent`'s translation is on and not standing by; a stopped one has no languages.
    init?(_ agent: NativeCallAgentPresentation.Agent, myLanguage: String) {
        guard agent.shown.isTranslating, !agent.shown.isStandby else { return nil }
        let languages = agent.shown.languages
        guard let language = languages.first(where: { !NativeCallLanguageCode.isSameSpokenLanguage($0, myLanguage) }) ?? languages.last else {
            return nil
        }
        self.language = language
        isPending = agent.control?.translation.isSyncing == true
    }

    init(language: String, isPending: Bool, kind: Kind = .interpreter) {
        self.language = language
        self.isPending = isPending
        self.kind = kind
    }

    /// Read with the avatar or the tile: «Перевод, испанский»; «Вы слышите их на украинском».
    var accessibilityLabel: String {
        let name = NativeCallTranslationCopy.languageName(language)
        return switch kind {
        case .interpreter: "\(UntranslatedL10n.screenNativeCallAssistantsJobTranslation), \(name)"
        case .heardIn: UntranslatedL10n.a11yNativeCallParticipantHeardIn(name)
        }
    }
}
