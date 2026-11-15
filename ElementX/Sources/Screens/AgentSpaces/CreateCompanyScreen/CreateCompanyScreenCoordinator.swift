//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CreateCompanyScreenCoordinatorParameters {
    let agentPlatformService: AgentPlatformServiceProtocol
    let userSession: UserSessionProtocol
    /// The stack the coordinator presents the media pickers on
    /// (RoomDetailsEdit canon — the coordinator self-encapsulates the
    /// three pickers, the flow passes only a nav-stack).
    weak var navigationStackCoordinator: NavigationStackCoordinator?
    let userIndicatorController: UserIndicatorControllerProtocol
    let orientationManager: OrientationManagerProtocol
}

enum CreateCompanyScreenCoordinatorAction {
    case created(AgentSpaceSummary)
    case cancel
}

final class CreateCompanyScreenCoordinator: CoordinatorProtocol {
    private let parameters: CreateCompanyScreenCoordinatorParameters
    private let viewModel: CreateCompanyScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<CreateCompanyScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CreateCompanyScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: CreateCompanyScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = CreateCompanyScreenViewModel(agentPlatformService: parameters.agentPlatformService,
                                                 userSession: parameters.userSession,
                                                 userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .created(let space):
                actionsSubject.send(.created(space))
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
        AnyView(CreateCompanyScreen(context: viewModel.context))
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
