//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias LanguagePickerScreenViewModelType = StateStoreViewModelV2<LanguagePickerScreenViewState, LanguagePickerScreenViewAction>

/// Drives `LanguagePickerScreen`. A static single-select over the caller-
/// supplied language set (the transport-specific catalog list — text vs
/// voice — from `GET /tools/catalog`), emitting the chosen code so the
/// form that opened it can store it. No service, no async — the list is
/// passed in.
class LanguagePickerScreenViewModel: LanguagePickerScreenViewModelType, LanguagePickerScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<LanguagePickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<LanguagePickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(languages: [AgentLanguage], selectedCode: String) {
        super.init(initialViewState: LanguagePickerScreenViewState(languages: languages,
                                                                   selectedCode: selectedCode,
                                                                   keyboardLanguages: SuggestedLanguages.keyboardLanguages))
    }

    override func process(viewAction: LanguagePickerScreenViewAction) {
        MXLog.info("LanguagePickerScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .select(let code):
            actionsSubject.send(.selected(code: code))
        }
    }
}
