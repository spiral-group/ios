//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: translation language presentation for the agent-tools
// surfaces (Brief 0036 / ADR-0048), not present upstream.
//
// The backend owns which canonical provider codes are selectable; the client
// owns their presentation. Foundation localises each BCP-47 identifier into
// the app's current language, while the original code is stored and forwarded
// unchanged (`zh-Hans` / `pt-BR` casing is provider-significant).
//

import Foundation

nonisolated enum TranslationLanguageDisplayName {
    /// The locale used by the rest of the app's strings. This follows iOS's
    /// per-app language override as well as the device language preference.
    static var appLocale: Locale {
        let identifier = (Bundle.overrideLocalizations ?? Bundle.app.preferredLocalizations).first
            ?? Locale.current.identifier
        return Locale(identifier: identifier)
    }

    /// Resolve a canonical provider code to a human name in `locale`.
    /// `fallback` is the backend's English metadata and is used only if a
    /// future provider identifier is unknown to the installed OS.
    static func localizedName(for code: String,
                              fallback: String? = nil,
                              locale: Locale = appLocale) -> String {
        let identifier = code.replacingOccurrences(of: "_", with: "-")
        if let localized = locale.localizedString(forIdentifier: identifier),
           !localized.isEmpty,
           localized.caseInsensitiveCompare(identifier) != .orderedSame {
            return localized
        }

        if let fallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }
        return code
    }
}

nonisolated extension TranslationLanguageDisplayName {
    /// The name standing alone, as a list or menu item: «Украинский», not
    /// the «украинский» Russian writes inside a sentence.
    static func standaloneName(for code: String,
                               fallback: String? = nil,
                               locale: Locale = appLocale) -> String {
        let name = localizedName(for: code, fallback: fallback, locale: locale)
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}

/// One pickable backend language. `code` is the value sent on the wire;
/// `displayName` is computed for the current app locale.
nonisolated struct AgentLanguage: Identifiable, Hashable {
    let code: String
    private let fallbackDisplayName: String

    init(code: String, displayName: String) {
        self.code = code
        fallbackDisplayName = displayName
    }

    var displayName: String {
        TranslationLanguageDisplayName.localizedName(for: code, fallback: fallbackDisplayName)
    }
    
    /// The name as a picker row shows it.
    var standaloneName: String {
        TranslationLanguageDisplayName.standaloneName(for: code, fallback: fallbackDisplayName)
    }

    var id: String {
        code
    }
}
