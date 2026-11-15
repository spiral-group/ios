//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct AnalyticsSettingsScreen: View {
    @Bindable var context: AnalyticsSettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            analyticsSection
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(L10n.commonAnalytics)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var analyticsSection: some View {
        Section {
            ListRow(label: .plain(title: L10n.screenAnalyticsSettingsShareData),
                    kind: .toggle($context.enableAnalytics))
                .onChange(of: context.enableAnalytics) {
                    context.send(viewAction: .toggleAnalytics)
                }
        } footer: {
            Text(context.viewState.strings.sectionFooter)
                .compoundListSectionFooter()
        }
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct AnalyticsSettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        let userSettings = UserSettings.mock()
        let viewModel = AnalyticsSettingsScreenViewModel(userSettings: userSettings,
                                                         analytics: AnalyticsServiceMock(.init()))
        AnalyticsSettingsScreen(context: viewModel.context)
    }
}
