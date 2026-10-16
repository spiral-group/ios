//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): «Appearance & media», the two cosmetic rows
// that left Advanced settings. Upstream has them as the inline Appearance
// picker and MediaUploadQualitySettingsScreen (#6288).
// The Spiral feature is built on Element's `AdvancedSettingsScreenViewModel.swift`.
//

import SwiftUI

typealias AppearanceAndMediaSettingsScreenViewModelType = StateStoreViewModelV2<AppearanceAndMediaSettingsScreenViewState, AppearanceAndMediaSettingsScreenViewAction>

class AppearanceAndMediaSettingsScreenViewModel: AppearanceAndMediaSettingsScreenViewModelType, AppearanceAndMediaSettingsScreenViewModelProtocol {
    private let analytics: AnalyticsServiceProtocol
    
    init(settings: AppearanceAndMediaSettingsProtocol, analytics: AnalyticsServiceProtocol) {
        self.analytics = analytics
        super.init(initialViewState: .init(bindings: .init(settings: settings)))
    }
    
    override func process(viewAction: AppearanceAndMediaSettingsScreenViewAction) {
        switch viewAction {
        case .optimizeMediaUploadsChanged:
            // A view action, as sinking the AppSettings publisher would track the initial value too.
            analytics.trackInteraction(name: state.bindings.optimizeMediaUploads ? .MobileSettingsOptimizeMediaUploadsEnabled : .MobileSettingsOptimizeMediaUploadsDisabled)
        }
    }
}
