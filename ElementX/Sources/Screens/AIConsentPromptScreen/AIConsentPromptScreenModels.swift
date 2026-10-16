//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum AIConsentPromptScreenViewModelAction {
    /// The person decided; the onboarding moves on.
    case done
}

enum AIConsentPromptScreenViewAction {
    case allow
    case notNow
}

struct AIConsentPromptScreenViewState: BindableState {
    /// The disclosure and a link to the privacy policy.
    let content: AttributedString
    var isSaving = false
    var bindings = AIConsentPromptScreenViewStateBindings()
    
    init(privacyURL: URL) {
        var link = AttributedString(UntranslatedL10n.screenAiConsentPromptPrivacyPolicy)
        link.link = privacyURL
        link.bold()
        content = AttributedString(UntranslatedL10n.screenAiConsentPromptContent) + "\n\n" + link
    }
}

struct AIConsentPromptScreenViewStateBindings {
    var alertInfo: AlertInfo<AIConsentPromptScreenAlert>?
}

enum AIConsentPromptScreenAlert {
    case saveFailed
}
