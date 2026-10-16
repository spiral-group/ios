//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

enum DeveloperOptionsScreenCoordinatorAction {
    case clearCache
}

final class DeveloperOptionsScreenCoordinator: CoordinatorProtocol {
    private var viewModel: DeveloperOptionsScreenViewModelProtocol
    
    private let actionsSubject: PassthroughSubject<DeveloperOptionsScreenCoordinatorAction, Never> = .init()
    private var cancellables = Set<AnyCancellable>()
    
    var actions: AnyPublisher<DeveloperOptionsScreenCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    #if DEBUG
    // AGENT-PLATFORM (Brief 0066): the Interactive Post slice harness needs a
    // real room to post into and read back from. Held here rather than put in
    // the view state, which is for values a view renders, not for services.
    private let clientProxy: ClientProxyProtocol?
    #endif
    
    init(appSettings: AppSettings, appHooks: AppHooks, clientProxy: ClientProxyProtocol?) {
        #if DEBUG
        self.clientProxy = clientProxy
        #endif
        
        viewModel = DeveloperOptionsScreenViewModel(developerOptions: appSettings,
                                                    appHooks: appHooks,
                                                    clientProxy: clientProxy)
        
        viewModel.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .clearCache:
                    actionsSubject.send(.clearCache)
                }
            }
            .store(in: &cancellables)
    }
    
    func toPresentable() -> AnyView {
        #if DEBUG
        AnyView(DeveloperOptionsScreen(context: viewModel.context, clientProxy: clientProxy))
        #else
        AnyView(DeveloperOptionsScreen(context: viewModel.context))
        #endif
    }
}
