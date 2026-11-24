//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (1.0.3, operator 2026-11-20): add Sign in with Apple to an
// account made with a sign-in phrase, so it has two ways in.
//
// The same gate as New phrase (Brief 0075): Face ID / the passcode, then a
// one-time link from the platform (`POST /me/apple-link`), then the identity
// page in the in-app web session. The page returns to
// `spiral://apple-linked?result=linked|cancelled|taken`.
//

import UIKit

final class AppleLinkPresenter {
    enum Outcome: Equatable {
        case linked
        case cancelled
        /// This Apple ID already signs in to another Spiral account.
        case taken
        /// The device has no passcode, so nothing guards the change.
        case passcodeRequired
        case failed
    }
    
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let authenticator: DeviceOwnerAuthenticatorProtocol
    private let pageSession: IdentityPageSession
    
    init(agentPlatformService: AgentPlatformServiceProtocol,
         presentationAnchor: UIWindow,
         authenticator: DeviceOwnerAuthenticatorProtocol = DeviceOwnerAuthenticator()) {
        self.agentPlatformService = agentPlatformService
        self.authenticator = authenticator
        // Not ephemeral, unlike New phrase: Apple's sign-in page then sees the Apple ID this
        // device is signed in with and offers its own Face ID sheet. In an ephemeral session it
        // can't, and asks for the Apple ID password and a two-factor code instead. The app's
        // main sign-in (`OAuthAuthenticationPresenter`) shares Safari's session the same way.
        pageSession = IdentityPageSession(presentationAnchor: presentationAnchor, logName: "Apple link", prefersEphemeralSession: false)
    }
    
    func start() async -> Outcome {
        // AGENT-PLATFORM (1.0.3): from the start, so a swipe home during Face ID or the ticket request cancels too.
        pageSession.watchForBackground()
        defer { pageSession.stopWatchingForBackground() }
        switch await authenticator.authenticate(reason: UntranslatedL10n.screenSettingsAppleAuthReason) {
        case .passcodeRequired:
            return .passcodeRequired
        case .cancelled:
            return .cancelled
        case .authenticated:
            break
        }
        
        switch await agentPlatformService.createAppleLink() {
        case .success(let url):
            switch await pageSession.open(url) {
            case .returned(let callbackURL):
                return Self.outcome(for: callbackURL)
            case .cancelled:
                return .cancelled
            case .failed:
                return .failed
            }
        case .failure(let error):
            MXLog.error("Apple link: could not get a link: \(error)")
            return .failed
        }
    }
    
    /// `spiral://apple-linked?result=linked|cancelled|taken`; anything else is a cancel.
    static func outcome(for callbackURL: URL?) -> Outcome {
        switch IdentityPageSession.result(of: callbackURL, host: "apple-linked") {
        case "linked": .linked
        case "taken": .taken
        default: .cancelled
        }
    }
}
