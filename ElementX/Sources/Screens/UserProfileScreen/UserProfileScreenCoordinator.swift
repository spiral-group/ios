//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct UserProfileScreenCoordinatorParameters {
    let userID: String
    let isPresentedModally: Bool
    let userSession: UserSessionProtocol
    let analytics: AnalyticsServiceProtocol
    let userIndicatorController: UserIndicatorControllerProtocol
}

enum UserProfileScreenCoordinatorAction {
    case openDirectChat(roomID: String)
    case startCall(roomProxy: JoinedRoomProxyProtocol, isVoiceCall: Bool)
    case dismiss
    case openAgentRow(AgentPageRow, card: AgentSpaceAgentCard) // AGENT-PLATFORM (Brief 0083, question 359)
}

final class UserProfileScreenCoordinator: CoordinatorProtocol {
    private var viewModel: UserProfileScreenViewModelProtocol
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<UserProfileScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<UserProfileScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: UserProfileScreenCoordinatorParameters) {
        viewModel = UserProfileScreenViewModel(userID: parameters.userID,
                                               isPresentedModally: parameters.isPresentedModally,
                                               userSession: parameters.userSession,
                                               analytics: parameters.analytics,
                                               userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .openDirectChat(let roomID):
                actionsSubject.send(.openDirectChat(roomID: roomID))
            case .startCall(let roomProxy, let isVoiceCall):
                actionsSubject.send(.startCall(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
            case .dismiss:
                actionsSubject.send(.dismiss)
            case .openAgentRow(let row, let card): // AGENT-PLATFORM (Brief 0083, question 359)
                actionsSubject.send(.openAgentRow(row, card: card))
            }
        }
        .store(in: &cancellables)
    }
    
    func stop() {
        viewModel.stop()
    }
    
    func toPresentable() -> AnyView {
        AnyView(UserProfileScreen(context: viewModel.context))
    }
}
