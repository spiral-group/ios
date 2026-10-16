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
        Form {
            Section {
                ListRow(label: .plain(title: L10n.commonCopyright),
                        kind: .button { openURL(context.viewState.copyrightURL) })
                // AGENT-PLATFORM: the URL is the full Terms of Use, and the row says so.
                ListRow(label: .plain(title: UntranslatedL10n.commonTermsOfUseSpiral),
                        kind: .button { openURL(context.viewState.acceptableUseURL) })
                ListRow(label: .plain(title: L10n.commonPrivacyPolicy),
                        kind: .button { openURL(context.viewState.privacyURL) })
                // AGENT-PLATFORM (Brief 0078): the acknowledgements in Settings.bundle.
                ListRow(label: .plain(title: L10n.commonOpenSourceLicenses),
                        kind: .button { context.send(viewAction: .openAcknowledgements) })
            }
            
            // AGENT-PLATFORM (AGPL publication, decision 107): what Spiral is built on,
            // and where the source of the app and of the server it talks to is.
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationSourceCodeSpiral),
                        kind: .button { openURL(context.viewState.sourceCodeURL) })
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationServerSourceCodeSpiral),
                        kind: .button { openURL(context.viewState.serverSourceCodeURL) })
                ListRow(label: .plain(title: UntranslatedL10n.screenLegalInformationAllSourcesSpiral),
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
        .compoundList()
        .navigationTitle(L10n.commonAbout)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews

struct LegalInformationScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = LegalInformationScreenViewModel(appSettings: .volatile(), appMediator: AppMediatorMock())
    static var previews: some View {
        LegalInformationScreen(context: viewModel.context)
    }
}
