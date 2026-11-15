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

struct ArmToolScreenCoordinatorParameters {
    let roomID: String
    let agentID: String
    let agentDisplayName: String
    /// Whether the form creates a new tool or edits an existing one.
    let mode: Mode
    let agentPlatformService: any RoomToolsServiceProtocol
    let store: AgentsStore

    enum Mode {
        /// A new tool of a kind.
        case create(AgentToolKind)
        /// Edit an existing tool — the form is seeded from it, submit replaces it.
        case edit(ActiveToolDetail)

        /// Call translation is personal (ADR-0094 D9, row 14): it has its own screen, never this form.
        var isCallTranslation: Bool {
            switch self {
            case .create(let kind): kind == .liveTranslate
            case .edit(let tool): if case .liveTranslate = tool.params { true } else { false }
            }
        }
    }
}

enum ArmToolScreenCoordinatorAction {
    /// The arm/disable applied — back to the tools, which read again.
    case finished
    /// Present the room-member picker for a member-carrying scope.
    case selectMembers(current: [String])
    /// Present the shared language picker for a translate tool, populated
    /// with the transport-specific catalog language set.
    case selectLanguage(languages: [AgentLanguage], current: String)
}

final class ArmToolScreenCoordinator: CoordinatorProtocol {
    private let viewModel: ArmToolScreenViewModel

    private let actionsSubject: PassthroughSubject<ArmToolScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()

    var actionsPublisher: AnyPublisher<ArmToolScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// `nil` for a tool with no form here: of a kind this build doesn't know, or Call translation, which has its own
    /// screen.
    init?(parameters: ArmToolScreenCoordinatorParameters) {
        guard !parameters.mode.isCallTranslation else { return nil }
        switch parameters.mode {
        case .create(let kind):
            viewModel = ArmToolScreenViewModel(roomID: parameters.roomID,
                                               agentID: parameters.agentID,
                                               agentDisplayName: parameters.agentDisplayName,
                                               kind: kind,
                                               agentPlatformService: parameters.agentPlatformService,
                                               store: parameters.store)
        case .edit(let tool):
            guard let viewModel = ArmToolScreenViewModel(roomID: parameters.roomID,
                                                         agentID: parameters.agentID,
                                                         agentDisplayName: parameters.agentDisplayName,
                                                         editing: tool,
                                                         agentPlatformService: parameters.agentPlatformService,
                                                         store: parameters.store) else { return nil }
            self.viewModel = viewModel
        }
    }

    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .finished:
                actionsSubject.send(.finished)
            case .selectMembers(let current):
                actionsSubject.send(.selectMembers(current: current))
            case .selectLanguage(let languages, let current):
                actionsSubject.send(.selectLanguage(languages: languages, current: current))
            }
        }
        .store(in: &cancellables)
    }

    /// Feed a member selection back from the room-member picker.
    func applyMemberSelection(_ members: [String]) {
        viewModel.applyMemberSelection(members)
    }

    /// Feed a language selection back from the language picker.
    func applyLanguageSelection(_ code: String) {
        viewModel.applyLanguageSelection(code)
    }

    func toPresentable() -> AnyView {
        AnyView(ArmToolScreen(context: viewModel.context))
    }
}
