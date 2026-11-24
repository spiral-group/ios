//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

enum AuthenticationStartScreenViewModelAction: Equatable {
    case loginWithQR
    case login
    case register
    
    case loginDirectlyWithOAuth(data: OAuthAuthorizationDataProxy, window: UIWindow)
    case loginDirectlyWithPassword(loginHint: String?)
    
    case reportProblem
    case developerOptions
}

struct AuthenticationStartScreenViewState: BindableState {
    /// The presentation anchor used for OAuth authentication.
    var window: UIWindow?
    
    let serverNameOrBaseURL: String?
    let showCreateAccountButton: Bool
    let showQRCodeLoginButton: Bool
    
    // AGENT-PLATFORM (Brief 0083 L1b): no classicAppMode, Element Classic's import is gone.
    
    let hideBrandChrome: Bool
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008): the invitation the person
    // arrived with, if any — drives the "invited by" banner.
    var pendingInvite: PendingInvite?
    
    var bindings = AuthenticationStartScreenViewStateBindings()
    
    var loginButtonTitle: String {
        if serverNameOrBaseURL != nil {
            // AGENT-PLATFORM (ADR-0005 auth v2): a public single-server
            // messenger never surfaces the homeserver domain — plain
            // "Sign in" instead of upstream's "Sign in to <server>".
            UntranslatedL10n.screenStartSignIn
        } else if showQRCodeLoginButton {
            L10n.screenOnboardingSignInManually
        } else {
            L10n.actionContinue
        }
    }
}

struct AuthenticationStartScreenViewStateBindings {
    var alertInfo: AlertInfo<AuthenticationStartScreenAlertType>?
    // AGENT-PLATFORM (Brief 0083 L1b): no showClassicAppBackupInstructions.
    // AGENT-PLATFORM (1.0.3): no «Have an invitation?» sheet — the web registration's first step asks for one.
}

enum AuthenticationStartScreenAlertType {
    case genericError
}

enum AuthenticationStartScreenViewAction {
    /// Updates the window used as the OAuth presentation anchor.
    case updateWindow(UIWindow)
    case developerOptions
    case reportProblem
    
    case loginWithQR
    case login
    case register
    
    // AGENT-PLATFORM (Brief 0083 L1b): no Element Classic actions.
}
