//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias LegalInformationScreenViewModelType = StateStoreViewModelV2<LegalInformationScreenViewState, LegalInformationScreenViewAction>

class LegalInformationScreenViewModel: LegalInformationScreenViewModelType, LegalInformationScreenViewModelProtocol {
    private let appMediator: AppMediatorProtocol // AGENT-PLATFORM (Brief 0078)
    
    init(appSettings: AppSettings, appMediator: AppMediatorProtocol) {
        self.appMediator = appMediator
        super.init(initialViewState: LegalInformationScreenViewState(copyrightURL: appSettings.copyrightURL,
                                                                     acceptableUseURL: appSettings.acceptableUseURL,
                                                                     privacyURL: appSettings.privacyURL,
                                                                     sourceCodeURL: appSettings.sourceCodeURL, // AGENT-PLATFORM (AGPL publication)
                                                                     serverSourceCodeURL: appSettings.serverSourceCodeURL,
                                                                     sourcesListURL: appSettings.sourcesListURL,
                                                                     sourceRequestAddress: appSettings.sourceRequestAddress))
    }
    
    override func process(viewAction: LegalInformationScreenViewAction) {
        switch viewAction {
        case .openAcknowledgements:
            appMediator.openAppSettings()
        }
    }
}
