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
//

import AuthenticationServices

final class NewPhrasePresenter: NSObject {
    enum Outcome: Equatable {
        case changed
        case cancelled
        /// The device has no passcode, so nothing guards the change.
        case passcodeRequired
        case failed
    }
    
    static let callbackScheme = "spiral"
    
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let presentationAnchor: UIWindow
    private let authenticator: DeviceOwnerAuthenticatorProtocol
    private var session: ASWebAuthenticationSession?
    
    init(agentPlatformService: AgentPlatformServiceProtocol,
         presentationAnchor: UIWindow,
         authenticator: DeviceOwnerAuthenticatorProtocol = DeviceOwnerAuthenticator()) {
        self.agentPlatformService = agentPlatformService
        self.presentationAnchor = presentationAnchor
        self.authenticator = authenticator
        super.init()
    }
    
    func start() async -> Outcome {
        switch await authenticator.authenticate(reason: UntranslatedL10n.screenSettingsNewPhraseAuthReason) {
        case .passcodeRequired:
            return .passcodeRequired
        case .cancelled:
            return .cancelled
        case .authenticated:
            break
        }
        
        switch await agentPlatformService.createPhraseReset() {
        case .success(let url):
            await waitUntilWindowIsActive()
            return await runWebSession(url: url)
        case .failure(let error):
            MXLog.error("New phrase: could not get a reset link: \(error)")
            return .failed
        }
    }
    
    // MARK: - Identity page
    
    /// Right after the passcode sheet the window's scene is still
    /// `foregroundInactive`, and `ASWebAuthenticationSession` refuses to
    /// start on it (error 3). Wait for the scene to come back, briefly.
    private func waitUntilWindowIsActive() async {
        for _ in 0..<20 where presentationAnchor.windowScene?.activationState != .foregroundActive {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    
    private func runWebSession(url: URL) async -> Outcome {
        await withCheckedContinuation { continuation in
            // A refused `start()` normally fires the completion handler too,
            // but that is not promised for every reason, and a checked
            // continuation may resume exactly once: whichever comes first.
            let resumeOnce = ResumeOnce(continuation)
            let session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: Self.callbackScheme) { callbackURL, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    if code != .canceledLogin {
                        MXLog.error("New phrase: web session failed: \(error)")
                    }
                    resumeOnce.resume(code == .canceledLogin ? .cancelled : .failed)
                    return
                }
                resumeOnce.resume(Self.outcome(for: callbackURL))
            }
            // Nothing to share with Safari; the page needs no cookies but its own.
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                MXLog.error("New phrase: web session did not start (canStart: \(session.canStart))")
                resumeOnce.resume(.failed)
            }
        }
    }
    
    /// The session's completion handler runs on the main thread, as does
    /// `start()`; this is only «exactly once», not thread safety.
    private final class ResumeOnce {
        private var continuation: CheckedContinuation<Outcome, Never>?
        
        init(_ continuation: CheckedContinuation<Outcome, Never>) {
            self.continuation = continuation
        }
        
        func resume(_ outcome: Outcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }
    
    /// `spiral://phrase-changed?result=changed|cancelled`.
    static func outcome(for callbackURL: URL?) -> Outcome {
        guard let callbackURL,
              callbackURL.scheme == callbackScheme,
              callbackURL.host() == "phrase-changed" else {
            return .cancelled
        }
        let result = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
        return result == "changed" ? .changed : .cancelled
    }
}

extension NewPhrasePresenter: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor
    }
}
