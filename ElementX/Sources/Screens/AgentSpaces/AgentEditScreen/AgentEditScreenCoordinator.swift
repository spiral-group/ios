//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct AgentEditScreenCoordinatorParameters {
    let agent: AgentSpaceAgentCard
    let agentPlatformService: AgentPlatformServiceProtocol
    let store: AgentsStore
    let userSession: UserSessionProtocol
    /// The stack the coordinator presents the media pickers on
    /// (RoomDetailsEdit canon — the coordinator self-encapsulates the
    /// three pickers, the flow passes only its nav-stack).
    weak var navigationStackCoordinator: NavigationStackCoordinator?
    let userIndicatorController: UserIndicatorControllerProtocol
    let orientationManager: OrientationManagerProtocol
}

enum AgentEditScreenCoordinatorAction {
    case saved
    case cancel
}

final class AgentEditScreenCoordinator: CoordinatorProtocol {
    private let parameters: AgentEditScreenCoordinatorParameters
    private let viewModel: AgentEditScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<AgentEditScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentEditScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: AgentEditScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = AgentEditScreenViewModel(agent: parameters.agent,
                                             agentPlatformService: parameters.agentPlatformService,
                                             store: parameters.store,
                                             userSession: parameters.userSession,
                                             userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .saved:
                actionsSubject.send(.saved)
            case .cancel:
                actionsSubject.send(.cancel)
            case .displayCameraPicker:
                displayMediaPickerWithMode(.init(source: .camera, selectionType: .single))
            case .displayMediaPicker:
                displayMediaPickerWithMode(.init(source: .photoLibrary, selectionType: .single))
            case .displayFilePicker:
                displayMediaPickerWithMode(.init(source: .documents(types: [.image]), selectionType: .single))
            }
        }
        .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AgentEditScreen(context: viewModel.context))
    }
    
    // MARK: Private
    
    private func displayMediaPickerWithMode(_ mode: MediaPickerScreenMode) {
        let stackCoordinator = NavigationStackCoordinator()
        
        let mediaPickerCoordinator = MediaPickerScreenCoordinator(mode: mode,
                                                                  userIndicatorController: parameters.userIndicatorController,
                                                                  orientationManager: parameters.orientationManager) { [weak self] action in
            guard let self else { return }
            switch action {
            case .cancel:
                parameters.navigationStackCoordinator?.setSheetCoordinator(nil)
            case .selectedMediaAtURLs(let urls):
                guard urls.count == 1,
                      let url = urls.first else {
                    fatalError("Received an invalid number of URLs")
                }
                
                parameters.navigationStackCoordinator?.setSheetCoordinator(nil)
                viewModel.didSelectMediaUrl(url: url)
            }
        }
        
        stackCoordinator.setRootCoordinator(mediaPickerCoordinator)
        parameters.navigationStackCoordinator?.setSheetCoordinator(stackCoordinator)
    }
}
