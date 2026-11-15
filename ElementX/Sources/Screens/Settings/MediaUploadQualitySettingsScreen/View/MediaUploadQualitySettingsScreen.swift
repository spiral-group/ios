//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct MediaUploadQualitySettingsScreen: View {
    @Bindable var context: MediaUploadQualitySettingsScreenViewModel.Context
    
    var body: some View {
        Form {
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
        .navigationTitle(L10n.commonMediaUploadQuality)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct MediaUploadQualitySettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = MediaUploadQualitySettingsScreenViewModel(userSettings: .mock(), analytics: AnalyticsServiceMock(.init()))
    
    static var previews: some View {
        ElementNavigationStack {
            MediaUploadQualitySettingsScreen(context: viewModel.context)
        }
    }
}
