//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403, scenario 5.1): one language with search, as a settings list, for the
// chat's tool "Call translation" — a regular iOS settings screen outside the call. In the call's Assistants sheet the
// language is picked on the call's glass instead (`NativeCallLanguagePage`, L1).

import Compound
import SwiftUI

/// One language, with search: a chat tool's language.
struct CallTranslationLanguageList: View {
    let title: String
    let languages: [String]
    /// Nil with the default picked.
    let selected: String?
    /// Offers `defaultTitle` first, naming this language: picking no language.
    let defaultLanguage: String
    /// What picking no language is called: the tool's "My language".
    let defaultTitle: String
    let onPick: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// The catalog's exact codes (ADR-0094 A.8), by name: the only languages a tool may store.
    static func languages(catalog: [VoiceControlsCatalogLanguage]) -> [String] {
        catalog.map(\.code).sorted { NativeCallTranslationCopy.languageTitle($0).localizedStandardCompare(NativeCallTranslationCopy.languageTitle($1)) == .orderedAscending }
    }

    /// The languages this person uses (every list's rule), without a search.
    static func suggested(selected: String?, languages: [String], query: String, preferred: [String], keyboards: [String]) -> [String] {
        guard query.isEmpty else { return [] }
        return SuggestedLanguages.codes(selected: selected, preferred: preferred, keyboards: keyboards, catalog: languages, limit: 5)
    }

    private var suggested: [String] {
        Self.suggested(selected: selected,
                       languages: languages,
                       query: query,
                       preferred: SuggestedLanguages.phoneLanguages,
                       keyboards: SuggestedLanguages.keyboardLanguages)
    }

    private var visible: [String] {
        let suggested = suggested
        return NativeCallTranslationCopy.languages(languages, matching: query).filter { !suggested.contains($0) }
    }

    var body: some View {
        Form {
            if query.isEmpty {
                Section {
                    ListRow(label: .default(title: defaultTitle,
                                            description: NativeCallTranslationCopy.languageTitle(defaultLanguage),
                                            icon: \.mobile),
                            kind: .selection(isSelected: selected == nil) { pick(nil) })
                }
            }
            let suggested = suggested
            if !suggested.isEmpty {
                Section {
                    ForEach(suggested, id: \.self, content: row)
                } header: {
                    Text(UntranslatedL10n.screenLanguagePickerSuggestedSection)
                        .compoundListSectionHeader()
                }
            }
            Section {
                ForEach(visible, id: \.self, content: row)
            } header: {
                if !suggested.isEmpty {
                    Text(UntranslatedL10n.screenLanguagePickerAllSection)
                        .compoundListSectionHeader()
                }
            }
        }
        .spiralGroupedList()
        .searchable(text: $query, prompt: UntranslatedL10n.screenNativeCallAssistantsSearchLanguages)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ code: String) -> some View {
        ListRow(label: .plain(title: NativeCallTranslationCopy.languageTitle(code)),
                kind: .selection(isSelected: code == selected) { pick(code) })
    }

    private func pick(_ code: String?) {
        onPick(code)
        dismiss()
    }
}
