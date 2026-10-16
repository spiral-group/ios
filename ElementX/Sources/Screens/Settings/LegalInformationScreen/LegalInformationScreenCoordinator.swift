//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

final class LegalInformationScreenCoordinator: CoordinatorProtocol {
    private let viewModel: LegalInformationScreenViewModelProtocol
    
    init(appSettings: AppSettings, appMediator: AppMediatorProtocol) {
        viewModel = LegalInformationScreenViewModel(appSettings: appSettings, appMediator: appMediator)
    }
    
    func toPresentable() -> AnyView {
        AnyView(LegalInformationScreen(context: viewModel.context))
    }
}
