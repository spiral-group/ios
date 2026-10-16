//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenCoordinator.swift`.
//

import Combine
import SwiftUI

struct LanguagePickerScreenCoordinatorParameters {
    /// The selectable languages — the transport-specific catalog list
    /// (text vs voice) the arm form fetched from `GET /tools/catalog`.
    let languages: [AgentLanguage]
    /// The currently-selected code (renders the checkmark), or empty.
    let selectedCode: String
}

enum LanguagePickerScreenCoordinatorAction {
    /// User picked a language — carries the stable lowercase code.
    case selected(code: String)
}

final class LanguagePickerScreenCoordinator: CoordinatorProtocol {
    private let viewModel: LanguagePickerScreenViewModel

    private let actionsSubject: PassthroughSubject<LanguagePickerScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<LanguagePickerScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(parameters: LanguagePickerScreenCoordinatorParameters) {
        viewModel = LanguagePickerScreenViewModel(languages: parameters.languages,
                                                  selectedCode: parameters.selectedCode)
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .selected(let code):
                actionsSubject.send(.selected(code: code))
            }
        }
        .store(in: &cancellables)
    }

    func toPresentable() -> AnyView {
        AnyView(LanguagePickerScreen(context: viewModel.context))
    }
}
