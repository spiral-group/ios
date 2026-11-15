//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

struct CompanyEditScreenCoordinatorParameters {
    let detail: AgentSpaceDetail
    let agentPlatformService: AgentPlatformServiceProtocol
    let userSession: UserSessionProtocol
    /// The stack the coordinator presents the media pickers on
    /// (RoomDetailsEdit canon — the coordinator self-encapsulates the
    /// three pickers, the flow passes only a nav-stack).
    weak var navigationStackCoordinator: NavigationStackCoordinator?
    let userIndicatorController: UserIndicatorControllerProtocol
    let orientationManager: OrientationManagerProtocol
}

enum CompanyEditScreenCoordinatorAction {
    case dismiss
    case saved
}

final class CompanyEditScreenCoordinator: CoordinatorProtocol {
    private let parameters: CompanyEditScreenCoordinatorParameters
    private let viewModel: CompanyEditScreenViewModelProtocol
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<CompanyEditScreenCoordinatorAction, Never> = .init()
    var actionsPublisher: AnyPublisher<CompanyEditScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(parameters: CompanyEditScreenCoordinatorParameters) {
        self.parameters = parameters
        viewModel = CompanyEditScreenViewModel(detail: parameters.detail,
                                               agentPlatformService: parameters.agentPlatformService,
                                               userSession: parameters.userSession,
                                               userIndicatorController: parameters.userIndicatorController)
    }
    
    func start() {
        viewModel.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .cancel:
                actionsSubject.send(.dismiss)
            case .saveFinished:
                actionsSubject.send(.saved)
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
        AnyView(CompanyEditScreen(context: viewModel.context))
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
