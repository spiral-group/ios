//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct LegalInformationScreen: View {
    let context: LegalInformationScreenViewModel.Context
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0083, lane settings): a row that opens outside the app shows Security's pop-out glyph,
        // grey as the chevron.
        Form {
            Section {
                ListRow(label: .plain(title: L10n.commonCopyright),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.copyrightURL) })
                // AGENT-PLATFORM: the URL is the full Terms of Use, and the row says so.
                ListRow(label: .plain(title: UntranslatedL10n.commonTermsOfUseSpiral),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.acceptableUseURL) })
                ListRow(label: .plain(title: L10n.commonPrivacyPolicy),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.privacyURL) })
                // AGENT-PLATFORM (Brief 0078): the acknowledgements in Settings.bundle.
                ListRow(label: .plain(title: L10n.commonOpenSourceLicenses),
                        details: .icon(popOut),
                        kind: .button { context.send(viewAction: .openAcknowledgements) })
            }
            
            // AGENT-PLATFORM (AGPL publication, decision 107): what Spiral is built on,
            // and where the source of the app and of the server it talks to is.
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationSourceCodeSpiral),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.sourceCodeURL) })
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationServerSourceCodeSpiral),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.serverSourceCodeURL) })
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationAllSourcesSpiral),
                        details: .icon(popOut),
                        kind: .button { openURL(context.viewState.sourcesListURL) })
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationSourceRequestSpiral),
                        details: .title(context.viewState.sourceRequestAddress),
                        kind: .button {
                            if let url = context.viewState.sourceRequestURL {
                                openURL(url)
                            }
                        })
            } footer: {
                Text(UntranslatedL10n.screenLegalInformationBasedOnElementSpiral)
                    .compoundListSectionFooter()
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .navigationTitle(L10n.commonAbout)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // AGENT-PLATFORM (Brief 0083, lane settings).
    private var popOut: some View {
        CompoundIcon(\.popOut)
            .foregroundStyle(.compound.iconTertiaryAlpha)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct LegalInformationScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = LegalInformationScreenViewModel(userSettings: .mock(), appMediator: AppMediatorMock())
    static var previews: some View {
        LegalInformationScreen(context: viewModel.context)
    }
}
