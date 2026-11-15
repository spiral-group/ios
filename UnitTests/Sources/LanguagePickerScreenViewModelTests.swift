//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct LanguagePickerScreenViewModelTests {
    /// A row names its language as a list item, capitalised, where the tool
    /// line «Перевод → английский» keeps it lower case.
    @Test
    func aRowsNameStandsAlone() {
        let russian = Locale(identifier: "ru")
        #expect(TranslationLanguageDisplayName.standaloneName(for: "uk", locale: russian) == "Украинский")
        #expect(TranslationLanguageDisplayName.localizedName(for: "uk", locale: russian) == "украинский")
    }
    
    private static let sampleLanguages = [AgentLanguage(code: "en", displayName: "English"),
                                          AgentLanguage(code: "de", displayName: "Deutsch"),
                                          AgentLanguage(code: "uk", displayName: "Ukrainian")]

    // MARK: - ViewModel

    @Test
    func rendersPassedInLanguagesOnly() {
        // The picker offers exactly the caller-supplied set (the catalog's
        // per-transport list), never the whole device ISO catalogue.
        let viewModel = LanguagePickerScreenViewModel(languages: Self.sampleLanguages, selectedCode: "uk")
        #expect(viewModel.context.viewState.languages == Self.sampleLanguages)
        #expect(viewModel.context.viewState.visibleLanguages.count == Self.sampleLanguages.count)
    }

    @Test
    func select_emitsChosenCode() async throws {
        let viewModel = LanguagePickerScreenViewModel(languages: Self.sampleLanguages, selectedCode: "uk")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selected(let code) = action { return code == "en" }
            return false
        }
        viewModel.context.send(viewAction: .select(code: "en"))
        try await deferred.fulfill()
    }

    @Test
    func search_filtersByCode() {
        let viewModel = LanguagePickerScreenViewModel(languages: Self.sampleLanguages, selectedCode: "uk")

        viewModel.context.searchQuery = "en"
        #expect(viewModel.context.viewState.visibleLanguages.contains { $0.code == "en" })
        #expect(viewModel.context.viewState.visibleLanguages.allSatisfy {
            $0.displayName.lowercased().contains("en") || $0.code.contains("en")
        })

        viewModel.context.searchQuery = ""
        #expect(viewModel.context.viewState.visibleLanguages.count == Self.sampleLanguages.count)
    }

    @Test
    func search_filtersByDisplayName() {
        let viewModel = LanguagePickerScreenViewModel(languages: Self.sampleLanguages, selectedCode: "uk")
        viewModel.context.searchQuery = Self.sampleLanguages[2].displayName
        #expect(viewModel.context.viewState.visibleLanguages.map(\.code) == ["uk"])
    }

    @Test
    func selectedCode_preservesProviderCasing() {
        let languages = [AgentLanguage(code: "zh-Hans", displayName: "Chinese (Simplified)")]
        let viewModel = LanguagePickerScreenViewModel(languages: languages, selectedCode: "zh-Hans")
        #expect(viewModel.context.viewState.selectedCode == "zh-Hans")
    }

    /// Every list's rule: the selected language, the phone's, the keyboards' — no English, Ukrainian or Russian added,
    /// and no section when none of them is in the list.
    @Test
    func suggestedLanguagesAreTheSelectedThenThePhonesAndKeyboardsWithNoFallback() {
        var state = LanguagePickerScreenViewState(languages: Self.sampleLanguages, selectedCode: "de", preferredLanguages: ["ja-JP"], keyboardLanguages: ["emoji", "uk-UA"])
        #expect(state.suggestedLanguages.map(\.code) == ["de", "uk"])
        #expect(state.otherLanguages.map(\.code) == ["en"])

        state = LanguagePickerScreenViewState(languages: [AgentLanguage(code: "fr", displayName: "Français")], selectedCode: "", preferredLanguages: ["ja-JP"])
        #expect(state.suggestedLanguages.isEmpty)

        state = LanguagePickerScreenViewState(languages: Self.sampleLanguages, selectedCode: "de", preferredLanguages: ["uk"])
        state.bindings.searchQuery = "en"
        #expect(state.suggestedLanguages.isEmpty)
    }

    @Test
    func localizedName_usesTheRequestedInterfaceLocale() {
        let locale = Locale(identifier: "uk")
        #expect(TranslationLanguageDisplayName.localizedName(for: "en", locale: locale) == "англійська")
        #expect(TranslationLanguageDisplayName.localizedName(for: "uk", locale: locale) == "українська")
    }

    @Test
    func localizedName_preservesScriptAndRegionDistinctions() {
        let locale = Locale(identifier: "uk")
        #expect(TranslationLanguageDisplayName.localizedName(for: "zh-Hans", locale: locale) == "китайська (спрощене письмо)")
        #expect(TranslationLanguageDisplayName.localizedName(for: "zh-Hant", locale: locale) == "китайська (традиційне письмо)")
        #expect(TranslationLanguageDisplayName.localizedName(for: "pt-BR", locale: locale) == "португальська (Бразилія)")
        #expect(TranslationLanguageDisplayName.localizedName(for: "pt-PT", locale: locale) == "португальська (Португалія)")
    }

    @Test
    func localizedName_fallsBackToBackendLabelForUnknownIdentifier() {
        #expect(TranslationLanguageDisplayName.localizedName(for: "x-provider-future",
                                                             fallback: "Future language",
                                                             locale: Locale(identifier: "uk")) == "Future language")
    }
}
