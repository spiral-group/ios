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
    var bindings = LanguagePickerScreenViewStateBindings()

    /// Languages matching the search query (by localized display name or the
    /// hidden wire code), sorted for the current app locale.
    var visibleLanguages: [AgentLanguage] {
        let query = bindings.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? languages : languages.filter {
            $0.displayName.lowercased().contains(query) || $0.code.contains(query)
        }
        return filtered.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

extension LanguagePickerScreenViewState {
    /// Without a search, the languages most people here want come first
    /// (step B.5): the device's, then English, Ukrainian and Russian.
    var suggestedLanguages: [AgentLanguage] {
        guard bindings.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var suggested: [AgentLanguage] = []
        for code in Self.suggestedCodes(preferredLanguages: preferredLanguages) {
            if let language = languages.first(where: { Self.languagePart($0.code) == code }),
               !suggested.contains(language) {
                suggested.append(language)
            }
        }
        return suggested
    }
    
    /// The rest, or everything that matches a search.
    var otherLanguages: [AgentLanguage] {
        let suggested = Set(suggestedLanguages)
        return visibleLanguages.filter { !suggested.contains($0) }
    }
    
    static func suggestedCodes(preferredLanguages: [String]) -> [String] {
        var codes: [String] = []
        for code in preferredLanguages.map(languagePart) + ["en", "uk", "ru"] where !codes.contains(code) {
            codes.append(code)
        }
        return codes
    }
    
    static func languagePart(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map { $0.lowercased() } ?? code.lowercased()
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
