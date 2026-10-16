//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// periphery:ignore - required for the architecture
enum LegalInformationScreenViewModelAction { }

struct LegalInformationScreenViewState: BindableState {
    let copyrightURL: URL
    let acceptableUseURL: URL
    let privacyURL: URL
    // AGENT-PLATFORM (AGPL publication)
    let sourceCodeURL: URL
    let serverSourceCodeURL: URL
    let sourcesListURL: URL
    let sourceRequestAddress: String
    
    var sourceRequestURL: URL? {
        URL(string: "mailto:\(sourceRequestAddress)")
    }
}

enum LegalInformationScreenViewAction {
    // AGENT-PLATFORM (Brief 0078): the acknowledgements live in the app's
    // Settings.bundle, so the row opens the app's page in iOS Settings.
    case openAcknowledgements
}
