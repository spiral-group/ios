//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// A single-select language chooser reused by every
// agent-tools surface that needs a target language (message translate,
// live-call interpreter, …). It renders the caller-supplied language set
// — the per-transport list the arm form fetched from the backend catalog
// — so the option set is defined in one place (the backend). Pushed onto
// the flow's sheet stack — the system back button dismisses it, no
// explicit cancel item.
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum LanguagePickerScreenViewModelAction {
    /// User picked a language — carries the canonical provider code back to
    /// the form unchanged.
    case selected(code: String)
}

// MARK: - View ↔ ViewModel state

struct LanguagePickerScreenViewState: BindableState {
    /// The full catalog, rendered filtered by the search query.
    let languages: [AgentLanguage]
    /// The currently-selected code (renders the checkmark).
    let selectedCode: String
    /// The device's languages, most wanted first (`Locale.preferredLanguages`).
    var preferredLanguages: [String] = Locale.preferredLanguages
    /// The languages of the keyboards turned on, read as the picker opens.
    var keyboardLanguages: [String] = []
    var bindings = LanguagePickerScreenViewStateBindings()

    /// Languages matching the search query (`TranslationLanguageDisplayName.matches`),
    /// sorted for the current app locale.
    var visibleLanguages: [AgentLanguage] {
        let filtered = languages.filter {
            TranslationLanguageDisplayName.matches(bindings.searchQuery, code: $0.code, shownName: $0.displayName)
        }
        return filtered.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

extension LanguagePickerScreenViewState {
    /// Without a search, the languages this person uses come first (`SuggestedLanguages`, every list's rule): the
    /// selected one, the phone's, the keyboards', as this list has them. None, and the section isn't there.
    var suggestedLanguages: [AgentLanguage] {
        guard bindings.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return SuggestedLanguages.codes(selected: selectedCode,
                                        preferred: preferredLanguages,
                                        keyboards: keyboardLanguages,
                                        catalog: languages.map(\.code),
                                        limit: 5)
            .compactMap { code in languages.first { $0.code == code } }
    }
    
    /// The rest, or everything that matches a search.
    var otherLanguages: [AgentLanguage] {
        let suggested = Set(suggestedLanguages)
        return visibleLanguages.filter { !suggested.contains($0) }
    }
}

struct LanguagePickerScreenViewStateBindings {
    var searchQuery = ""
}

// MARK: - View → ViewModel actions

enum LanguagePickerScreenViewAction {
    /// User tapped a language row.
    case select(code: String)
}
