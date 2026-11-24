//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: the one-time identity page in the in-app web session,
// shared by New phrase (Brief 0075) and Add Sign in with Apple (1.0.3).
//
// The page returns to `spiral://<host>?result=…`; each presenter reads its
// own host and results from the callback this hands back.
//

import AuthenticationServices

final class IdentityPageSession: NSObject {
    enum Outcome: Equatable {
        /// The page returned to the callback scheme (or the session ended without a URL).
        case returned(URL?)
        /// The person closed the sheet.
        case cancelled
        case failed
    }

    static let callbackScheme = "spiral"

    private let presentationAnchor: UIWindow
    private let logName: String
    private let prefersEphemeralSession: Bool
    private var session: ASWebAuthenticationSession?
    private var backgroundObserver: NSObjectProtocol?
    private var didEnterBackground = false

    /// - Parameters:
    ///   - logName: names the flow in the log, e.g. "New phrase".
    ///   - prefersEphemeralSession: share nothing with Safari's session.
    init(presentationAnchor: UIWindow, logName: String, prefersEphemeralSession: Bool) {
        self.presentationAnchor = presentationAnchor
        self.logName = logName
        self.prefersEphemeralSession = prefersEphemeralSession
        super.init()
    }

    /// Starts noting a trip to the background, so one during Face ID or the ticket request still cancels `open(_:)`.
    /// Call it before anything slow that comes first; `open(_:)` and `stopWatchingForBackground()` end it.
    func watchForBackground() {
        guard backgroundObserver == nil else { return }
        didEnterBackground = false
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIScene.didEnterBackgroundNotification,
                                                                    object: presentationAnchor.windowScene,
                                                                    queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnterBackground = true }
        }
    }
    
    func stopWatchingForBackground() {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        backgroundObserver = nil
    }
    
    func open(_ url: URL) async -> Outcome {
        watchForBackground()
        defer { stopWatchingForBackground() }
        // `ASWebAuthenticationSession` raises an Objective-C exception on a non-http(s) URL.
        guard Self.canOpen(url) else {
            MXLog.error("\(logName): refused a page that is not https")
            return .failed
        }
        switch await waitUntilWindowIsActive() {
        case .active:
            return await runWebSession(url: url)
        case .wentToBackground:
            // Swiped home during Face ID: the page must not open by itself once the app comes back.
            MXLog.info("\(logName): the app went to the background before the page opened")
            return .cancelled
        case .timedOut:
            MXLog.error("\(logName): the scene never became active, the page isn't opened")
            return .failed
        }
    }
    
    /// What waiting for the window's scene to become active ended with.
    enum SceneWait: Equatable {
        case active
        case wentToBackground
        case timedOut
    }
    
    /// Polls `activationState` until the scene is active, at most `attempts` times. A trip to the background ends the
    /// wait, even one already over when the app is woken again (`hasEnteredBackground`).
    static func waitForActiveScene(activationState: () -> UIScene.ActivationState?,
                                   hasEnteredBackground: () -> Bool,
                                   attempts: Int = 100,
                                   interval: Duration = .milliseconds(100)) async -> SceneWait {
        for attempt in 0...attempts {
            let state = activationState()
            if hasEnteredBackground() || state == .background {
                return .wentToBackground
            }
            if state == .foregroundActive {
                return .active
            }
            if attempt < attempts {
                try? await Task.sleep(for: interval)
            }
        }
        return .timedOut
    }

    /// Only an `https` page with a host; the service has already matched the host itself.
    static func canOpen(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host() ?? "").isEmpty
    }

    /// Reads `result` from `spiral://<host>?result=…`; `nil` for any other URL.
    static func result(of callbackURL: URL?, host: String) -> String? {
        guard let callbackURL,
              callbackURL.scheme == callbackScheme,
              callbackURL.host() == host else {
            return nil
        }
        return URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "result" }?.value
    }

    // MARK: - Private

    /// Right after the passcode sheet the window's scene is still
    /// `foregroundInactive`, and `ASWebAuthenticationSession` refuses to
    /// start on it (error 3). Wait for the scene to come back. Face ID can
    /// keep it inactive for about 3 s after it returns (iPhone 15 Pro,
    /// 2026-11-20: active again 2.9 s later, past the old 2 s wait), so the
    /// bound is generous; the loop ends as soon as the scene is active, or
    /// gone to the background (the app can be suspended mid-loop, so the
    /// scene's notification is watched as well as its state, from `watchForBackground()`).
    private func waitUntilWindowIsActive() async -> SceneWait {
        let scene = presentationAnchor.windowScene
        return await Self.waitForActiveScene(activationState: { scene?.activationState },
                                             hasEnteredBackground: { [weak self] in self?.didEnterBackground ?? true })
    }
    
    private func runWebSession(url: URL) async -> Outcome {
        await withCheckedContinuation { continuation in
            // A refused `start()` normally fires the completion handler too,
            // but that is not promised for every reason, and a checked
            // continuation may resume exactly once: whichever comes first.
            let resumeOnce = ResumeOnce(continuation)
            let logName = logName
            let session = ASWebAuthenticationSession(url: url,
                                                     callbackURLScheme: Self.callbackScheme) { callbackURL, error in
                if let error {
                    let code = (error as? ASWebAuthenticationSessionError)?.code
                    if code != .canceledLogin {
                        MXLog.error("\(logName): web session failed: \(error)")
                    }
                    resumeOnce.resume(code == .canceledLogin ? .cancelled : .failed)
                    return
                }
                resumeOnce.resume(.returned(callbackURL))
            }
            session.prefersEphemeralWebBrowserSession = prefersEphemeralSession
            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                MXLog.error("\(logName): web session did not start (canStart: \(session.canStart))")
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
}

extension IdentityPageSession: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor
    }
}
