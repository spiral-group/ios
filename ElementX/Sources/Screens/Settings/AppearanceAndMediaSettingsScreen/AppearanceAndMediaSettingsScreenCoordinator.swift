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
// The Spiral feature is built on Element's `AdvancedSettingsScreenCoordinator.swift`.
//

import SwiftUI

struct AppearanceAndMediaSettingsScreenCoordinatorParameters {
    let appSettings: AppSettings
    let analytics: AnalyticsServiceProtocol
}

final class AppearanceAndMediaSettingsScreenCoordinator: CoordinatorProtocol {
    private let viewModel: AppearanceAndMediaSettingsScreenViewModelProtocol
    
    init(parameters: AppearanceAndMediaSettingsScreenCoordinatorParameters) {
        viewModel = AppearanceAndMediaSettingsScreenViewModel(settings: parameters.appSettings,
                                                              analytics: parameters.analytics)
    }
    
    func toPresentable() -> AnyView {
        AnyView(AppearanceAndMediaSettingsScreen(context: viewModel.context))
    }
}
