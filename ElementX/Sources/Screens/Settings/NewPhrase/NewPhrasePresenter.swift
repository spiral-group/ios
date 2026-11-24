//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: a new account phrase from a signed-in device (Brief 0075).
//
// The server keeps only the public key of the 12-word phrase, so a person who
// lost the words cannot rotate it with the old one. This device is signed in:
// after Face ID / the passcode it asks the platform for a one-time link, and
// the identity page — in ticket mode, without the old phrase — lets the person
// choose new words. The page returns to `spiral://phrase-changed?result=…`.
// An account made with Sign in with Apple has no phrase yet; the same page
// adds its first one (1.0.3).
//

import UIKit

final class NewPhrasePresenter {
    enum Outcome: Equatable {
        case changed
        case cancelled
        /// The device has no passcode, so nothing guards the change.
        case passcodeRequired
        case failed
    }
    
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let authenticator: DeviceOwnerAuthenticatorProtocol
    private let addsFirstPhrase: Bool
    private let pageSession: IdentityPageSession
    
    /// - Parameter addsFirstPhrase: the account has no phrase yet, so Face ID asks to add one rather than change it.
    init(agentPlatformService: AgentPlatformServiceProtocol,
         presentationAnchor: UIWindow,
         addsFirstPhrase: Bool = false,
         authenticator: DeviceOwnerAuthenticatorProtocol = DeviceOwnerAuthenticator()) {
        self.agentPlatformService = agentPlatformService
        self.authenticator = authenticator
        self.addsFirstPhrase = addsFirstPhrase
        // Nothing to share with Safari; the page needs no cookies but its own.
        pageSession = IdentityPageSession(presentationAnchor: presentationAnchor, logName: "New phrase", prefersEphemeralSession: true)
    }
    
    func start() async -> Outcome {
        // AGENT-PLATFORM (1.0.3): from the start, so a swipe home during Face ID or the ticket request cancels too.
        pageSession.watchForBackground()
        defer { pageSession.stopWatchingForBackground() }
        let reason = addsFirstPhrase ? UntranslatedL10n.screenSettingsAddPhraseAuthReason : UntranslatedL10n.screenSettingsNewPhraseAuthReason
        switch await authenticator.authenticate(reason: reason) {
        case .passcodeRequired:
            return .passcodeRequired
        case .cancelled:
            return .cancelled
        case .authenticated:
            break
        }
        
        switch await agentPlatformService.createPhraseReset() {
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
            MXLog.error("New phrase: could not get a reset link: \(error)")
            return .failed
        }
    }
    
    /// `spiral://phrase-changed?result=changed|cancelled`.
    static func outcome(for callbackURL: URL?) -> Outcome {
        IdentityPageSession.result(of: callbackURL, host: "phrase-changed") == "changed" ? .changed : .cancelled
    }
}
