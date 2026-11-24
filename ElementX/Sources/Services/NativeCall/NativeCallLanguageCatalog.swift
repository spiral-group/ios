//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, backend ADR-0094 A.8): one voice-translation catalog for both sides. Every language the
// call stores, publishes or compares is one of its codes in its exact form (`uk`, `zh-Hans`, `pt-BR`); the base subtag
// only says whether two codes are the same spoken language. Kept on the device for a day, so every list and "As on the
// phone" have it from the first frame.

import SwiftUI

/// The languages every language list puts first (operator, 2026-11-12): the selected one, then the phone's languages,
/// then the keyboards' — as the list's own catalog has them, one per spoken language, nothing added that the person
/// doesn't use. Read on the device when the list shows; nothing leaves it.
nonisolated enum SuggestedLanguages {
    /// The suggestions for a list over `catalog`, at most `limit`.
    static func codes(selected: String?, preferred: [String], keyboards: [String], catalog: [String], limit: Int) -> [String] {
        // The emoji keyboard and dictation name no language.
        let keyboards = keyboards.filter { !["emoji", "dictation"].contains($0.lowercased()) }
        var codes: [String] = []
        for candidate in [selected].compactMap(\.self) + preferred + keyboards where codes.count < limit {
            guard let code = catalog.contains(candidate) ? candidate : NativeCallLanguageCode.closest(to: candidate, in: catalog),
                  !codes.contains(where: { NativeCallLanguageCode.isSameSpokenLanguage($0, code) }) else { continue }
            codes.append(code)
        }
        return codes
    }

    /// The phone's languages, most wanted first.
    static var phoneLanguages: [String] {
        Locale.preferredLanguages
    }

    /// The languages of the keyboards turned on in Settings.
    @MainActor
    static var keyboardLanguages: [String] {
        UITextInputMode.activeInputModes.compactMap(\.primaryLanguage)
    }

    /// The device's suggestions for a list over `catalog`.
    @MainActor
    static func onDevice(selected: String?, catalog: [String], limit: Int) -> [String] {
        codes(selected: selected, preferred: phoneLanguages, keyboards: keyboardLanguages, catalog: catalog, limit: limit)
    }
}

/// The catalog as the device keeps it.
struct NativeCallLanguageCatalogCache {
    static let lifetime: TimeInterval = 24 * 60 * 60

    let defaults: UserDefaults
    let now: () -> Date

    static let standard = NativeCallLanguageCatalogCache(defaults: .standard, now: Date.init)

    private static let languagesKey = "spiralVoiceLanguages"
    private static let fetchedAtKey = "spiralVoiceLanguagesFetchedAt"

    /// The last catalog read, however old: a stale list beats an empty one while the next read is out.
    var languages: [VoiceControlsCatalogLanguage]? {
        guard let data = defaults.data(forKey: Self.languagesKey) else { return nil }
        return try? JSONDecoder().decode([VoiceControlsCatalogLanguage].self, from: data)
    }

    /// The catalog is younger than a day.
    var isFresh: Bool {
        guard languages != nil, let fetchedAt = defaults.object(forKey: Self.fetchedAtKey) as? Date else { return false }
        return now().timeIntervalSince(fetchedAt) < Self.lifetime
    }

    func store(_ languages: [VoiceControlsCatalogLanguage]) {
        guard let data = try? JSONEncoder().encode(languages) else { return }
        defaults.set(data, forKey: Self.languagesKey)
        defaults.set(now(), forKey: Self.fetchedAtKey)
    }

    /// Reads the catalog when the kept one is a day old or missing. A failed read keeps what is kept: it is not "no
    /// languages". Nil only when nothing was ever read.
    func load(_ read: () async -> Result<[VoiceControlsCatalogLanguage], VoiceControlsError>) async -> [VoiceControlsCatalogLanguage]? {
        if isFresh { return languages }
        switch await read() {
        case .success(let languages) where !languages.isEmpty:
            store(languages)
            return languages
        case .success:
            return self.languages
        case .failure(let error):
            MXLog.warning("Voice language catalog read failed: \(error)")
            return languages
        }
    }
}

nonisolated enum NativeCallLanguageCode {
    /// BCP 47's "undetermined": a person whose live memberships publish different languages (DEBT B6). Never a catalog
    /// code and never published, so it is another spoken language than any — unlike a person with none published.
    static let undetermined = "und"

    /// Whether two catalog codes are the same spoken language (ADR-0094 D3): `pt-BR` and `pt-PT` are, so a `pt-BR`
    /// speaker isn't translated into `pt-PT`.
    static func isSameSpokenLanguage(_ lhs: String, _ rhs: String) -> Bool {
        LanguageTag.base(of: lhs) == LanguageTag.base(of: rhs)
    }

    /// The catalog code closest to a phone locale ("As on the phone"): the exact code first (`pt_BR` → `pt-BR`), then
    /// the locale with its last subtags dropped (`zh-Hans-CN` → `zh-Hans`), then any code of the same base
    /// (`uk-UA` → `uk`). Nil when the catalog has nothing in that language.
    static func closest(to identifier: String, in catalog: [String]) -> String? {
        let subtags = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard !subtags.isEmpty else { return nil }
        for count in stride(from: subtags.count, through: 1, by: -1) {
            let candidate = subtags.prefix(count).joined(separator: "-")
            if let code = catalog.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return code
            }
        }
        return catalog.first { isSameSpokenLanguage($0, identifier) }
    }
}

/// "My language": the language a person hears and speaks (model point 2), the app's unless they chose another.
/// Stored on the device as a catalog code; published to the call with the membership.
struct NativeCallMyLanguageStore {
    let defaults: UserDefaults
    /// The app's language (`Bundle.app`, or the per-app override), as the screens' strings use it: a locale identifier,
    /// not yet a catalog code.
    let phoneLanguage: () -> String
    /// The phone's own languages, tried after the app's (ADR-0094 D1).
    let deviceLanguages: () -> [String]

    init(defaults: UserDefaults, deviceLanguages: @escaping () -> [String] = { [] }, phoneLanguage: @escaping () -> String) {
        self.defaults = defaults
        self.deviceLanguages = deviceLanguages
        self.phoneLanguage = phoneLanguage
    }

    static let standard = NativeCallMyLanguageStore(defaults: .standard,
                                                    deviceLanguages: { Locale.preferredLanguages },
                                                    phoneLanguage: { TranslationLanguageDisplayName.appLocale.identifier })

    private static let languageKey = "spiralCallMyLanguage"
    private static let languageChosenKey = "spiralCallMyLanguageChosen"
    private static let assistantKeyPrefix = "spiralCallAssistant."
    private static let neighbourKey = "spiralCallNeighbourLanguage"
    private static let listenKeyPrefix = "spiralCallListenLanguage."

    /// Nil: "As on the phone".
    var chosen: String? {
        defaults.string(forKey: Self.languageKey)
    }

    /// ADR-0094 D1, the only code ever published: the chosen one while the catalog has it, else the catalog's closest
    /// to the app's language, else to the phone's. Nil while no catalog was read, or when it has none of them — no
    /// language is published then.
    func resolved(catalog: [String]) -> String? {
        guard !catalog.isEmpty else { return nil }
        if let chosen, catalog.contains(chosen) { return chosen }
        return phoneCode(catalog: catalog)
    }

    /// "As on the phone", as a catalog code; nil when the catalog has neither the app's language nor the phone's.
    func phoneCode(catalog: [String]) -> String? {
        ([phoneLanguage()] + deviceLanguages()).lazy.compactMap { NativeCallLanguageCode.closest(to: $0, in: catalog) }.first
    }

    /// What the screens name before there is a code to publish: the chosen one, else the app's base language.
    var displayLanguage: String {
        chosen ?? LanguageTag.base(of: phoneLanguage())
    }

    /// Question 409: the person picked their language — "As on the phone" too — rather than living with the default. A
    /// language stored is a pick whenever it was made.
    var isChosen: Bool {
        defaults.bool(forKey: Self.languageChosenKey) || chosen != nil
    }

    /// The person's pick: nil is "As on the phone", picked.
    func setChosen(_ language: String?) {
        defaults.set(language, forKey: Self.languageKey)
        defaults.set(true, forKey: Self.languageChosenKey)
    }

    /// Never picked: the default again, as the lab and the tests start.
    func clearChoice() {
        defaults.removeObject(forKey: Self.languageKey)
        defaults.removeObject(forKey: Self.languageChosenKey)
    }

    /// The own assistant picked in this chat when there are several (scenario 9.3).
    func assistant(roomID: String) -> String? {
        defaults.string(forKey: Self.assistantKeyPrefix + roomID)
    }

    func setAssistant(_ agentID: String, roomID: String) {
        defaults.set(agentID, forKey: Self.assistantKeyPrefix + roomID)
    }

    /// The pocket interpreter's other side: the language of the person next to you (scenario 8.2).
    var neighbourLanguage: String? {
        defaults.string(forKey: Self.neighbourKey)
    }

    func setNeighbourLanguage(_ language: String) {
        defaults.set(language, forKey: Self.neighbourKey)
    }

    /// "In calls here I listen in …" (ADR-0094 Appendix C row 14): kept on the device per chat, because listening is no
    /// agent action. Nil: the chat has no such preference.
    func listenLanguage(roomID: String) -> String? {
        defaults.string(forKey: Self.listenKeyPrefix + roomID)
    }

    func setListenLanguage(_ language: String?, roomID: String) {
        defaults.set(language, forKey: Self.listenKeyPrefix + roomID)
    }
}
