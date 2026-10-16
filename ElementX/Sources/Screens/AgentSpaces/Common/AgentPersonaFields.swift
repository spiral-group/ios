//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Agents tab step B, decision 194): the personal assistant's
// text settings and their limits, shared by the settings screens.
//

import Foundation

enum AgentEditPersonaField: CaseIterable {
    case ownerDisplayName, tone, greeting, visitorGreeting

    func bounds(in persona: AgentEditSchema.PersonaBounds) -> AgentEditSchema.FieldBounds {
        switch self {
        case .ownerDisplayName: persona.ownerDisplayName
        case .tone: persona.tone
        case .greeting: persona.greeting
        case .visitorGreeting: persona.visitorGreeting
        }
    }

    func value(in persona: PersonaView) -> String {
        switch self {
        case .ownerDisplayName: persona.ownerDisplayName
        case .tone: persona.tone
        case .greeting: persona.greeting
        case .visitorGreeting: persona.visitorGreeting
        }
    }

    var title: String {
        switch self {
        case .ownerDisplayName: UntranslatedL10n.screenAgentEditPersonaOwnerName
        case .tone: UntranslatedL10n.screenAgentEditPersonaTone
        case .greeting: UntranslatedL10n.screenAgentEditPersonaGreeting
        case .visitorGreeting: UntranslatedL10n.screenAgentEditPersonaVisitorGreeting
        }
    }
}

/// Why a changed text can't be saved, mirroring the server's
/// `persona_validation`: non-empty after trimming, at most the limit.
enum AgentEditPersonaIssue: Equatable {
    case empty
    case tooLong

    /// `nil` when `value` fits `bounds`.
    init?(value: String, bounds: AgentEditSchema.FieldBounds) {
        let count = value.trimmedForPersona.unicodeScalars.count
        if count < max(bounds.minLength, 1) {
            self = .empty
        } else if count > bounds.maxLength {
            self = .tooLong
        } else {
            return nil
        }
    }
}

extension String {
    /// The server trims persona fields before it checks and stores them.
    var trimmedForPersona: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension AgentEditPatch.Persona {
    subscript(field: AgentEditPersonaField) -> String? {
        get {
            switch field {
            case .ownerDisplayName: ownerDisplayName
            case .tone: tone
            case .greeting: greeting
            case .visitorGreeting: visitorGreeting
            }
        }
        set {
            switch field {
            case .ownerDisplayName: ownerDisplayName = newValue
            case .tone: tone = newValue
            case .greeting: greeting = newValue
            case .visitorGreeting: visitorGreeting = newValue
            }
        }
    }
}

/// The tone as a choice plus «Свой вариант» (decision 192). A preset is sent
/// as its words in the app's language: the wire is still free text. The
/// friendly words match the server's default tone in each language.
enum AgentToneChoice: CaseIterable, Hashable {
    case friendly, business, calm, brief, custom

    static let presets: [AgentToneChoice] = [.friendly, .business, .calm, .brief]

    /// The words a preset stands for; `nil` for «Свой вариант».
    var value: String? {
        switch self {
        case .friendly: UntranslatedL10n.screenAgentEditToneFriendly
        case .business: UntranslatedL10n.screenAgentEditToneBusiness
        case .calm: UntranslatedL10n.screenAgentEditToneCalm
        case .brief: UntranslatedL10n.screenAgentEditToneBrief
        case .custom: nil
        }
    }

    var title: String {
        value ?? UntranslatedL10n.screenAgentEditToneCustom
    }

    static func preset(matching tone: String) -> AgentToneChoice? {
        let tone = tone.trimmedForPersona
        return presets.first { $0.value?.caseInsensitiveCompare(tone) == .orderedSame }
    }
}

extension AgentVoiceLanguage {
    /// The language in the app's language, as the tool's language picker
    /// names it, starting with a capital as a menu item does: «Украинский».
    var title: String {
        title(locale: TranslationLanguageDisplayName.appLocale)
    }
    
    func title(locale: Locale) -> String {
        TranslationLanguageDisplayName.standaloneName(for: rawValue, locale: locale)
    }
}

extension AgentVisitorPolicy {
    var title: String {
        switch self {
        case .askFirst: UntranslatedL10n.screenAgentSettingsVisitorAskFirst
        case .reply: UntranslatedL10n.screenAgentSettingsVisitorReply
        case .off: UntranslatedL10n.screenAgentSettingsVisitorOff
        }
    }

    var subtitle: String {
        switch self {
        case .askFirst: UntranslatedL10n.screenAgentSettingsVisitorAskFirstDescription
        case .reply: UntranslatedL10n.screenAgentSettingsVisitorReplyDescription
        case .off: UntranslatedL10n.screenAgentSettingsVisitorOffDescription
        }
    }
}
