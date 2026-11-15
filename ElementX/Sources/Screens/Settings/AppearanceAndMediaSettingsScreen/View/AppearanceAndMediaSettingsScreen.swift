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
// The Spiral feature is built on Element's `AdvancedSettingsScreen.swift`.
//

import Compound
import SwiftUI

struct AppearanceAndMediaSettingsScreen: View {
    @Bindable var context: AppearanceAndMediaSettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            Section {
                ListRow(label: .plain(title: L10n.commonAppearance),
                        kind: .picker(selection: $context.appAppearance,
                                      items: AppAppearance.allCases.map { (title: $0.name, tag: $0) }))
            }
            
            Section {
                ListRow(label: .plain(title: L10n.screenAdvancedSettingsMediaCompressionTitle,
                                      description: L10n.screenAdvancedSettingsMediaCompressionDescription),
                        kind: .toggle($context.optimizeMediaUploads))
                    .onChange(of: context.optimizeMediaUploads) {
                        context.send(viewAction: .optimizeMediaUploadsChanged)
                    }
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(UntranslatedL10n.screenSettingsAppearanceMediaTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AppAppearance {
    var name: String {
        switch self {
        case .system:
            L10n.themeSystem
        case .light:
            L10n.themeLight
        case .dark:
            L10n.themeDark
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct AppearanceAndMediaSettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = AppearanceAndMediaSettingsScreenViewModel(settings: AppSettings.volatile(),
                                                                     analytics: AnalyticsServiceMock(.init()))
    
    static var previews: some View {
        ElementNavigationStack {
            AppearanceAndMediaSettingsScreen(context: viewModel.context)
        }
    }
}
