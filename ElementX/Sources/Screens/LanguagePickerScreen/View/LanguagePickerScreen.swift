//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//

import Compound
import SwiftUI

struct LanguagePickerScreen: View {
    @Bindable var context: LanguagePickerScreenViewModel.Context

    var body: some View {
        Form {
            if context.viewState.visibleLanguages.isEmpty {
                emptySection
            } else {
                languagesSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenLanguagePickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $context.searchQuery, placement: .navigationBarDrawer(displayMode: .always))
        .compoundSearchField()
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    // MARK: - Sections

    @ViewBuilder
    private var languagesSection: some View {
        let suggested = context.viewState.suggestedLanguages
        if !suggested.isEmpty {
            Section {
                ForEach(suggested) { language in
                    languageRow(language)
                }
            } header: {
                Text(UntranslatedL10n.screenLanguagePickerSuggestedSection)
                    .compoundListSectionHeader()
            }
        }
        Section {
            ForEach(context.viewState.otherLanguages) { language in
                languageRow(language)
            }
        } header: {
            // A search shows one list, which needs no name.
            if !suggested.isEmpty {
                Text(UntranslatedL10n.screenLanguagePickerAllSection)
                    .compoundListSectionHeader()
            }
        }
    }

    private func languageRow(_ language: AgentLanguage) -> some View {
        let isSelected = language.code == context.viewState.selectedCode
        return ListRow(label: .plain(title: language.standaloneName),
                       kind: .selection(isSelected: isSelected) {
                           context.send(viewAction: .select(code: language.code))
                       })
    }

    private var emptySection: some View {
        Section {
            Text(UntranslatedL10n.screenLanguagePickerEmpty)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Previews

struct LanguagePickerScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = LanguagePickerScreenViewModel(languages: [AgentLanguage(code: "en", displayName: "English"),
                                                                     AgentLanguage(code: "uk", displayName: "Українська"),
                                                                     AgentLanguage(code: "ru", displayName: "Русский"),
                                                                     AgentLanguage(code: "de", displayName: "Deutsch"),
                                                                     AgentLanguage(code: "fr", displayName: "Français")],
                                                         selectedCode: "uk")

    static var previews: some View {
        ElementNavigationStack {
            LanguagePickerScreen(context: viewModel.context)
        }
    }
}
