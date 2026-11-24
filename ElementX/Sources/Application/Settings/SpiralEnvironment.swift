//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0084): the backend this build talks to, and the only
// reader of `SPIRAL_STAGING` and `SPIRAL_DEV_STACK`. Every target compiles it.
//
// Staging is a build configuration of the same app, not a second app: the same
// bundle ID, App Group and keychain (question 350), so a staging and a prod
// build replace each other on a phone. Nothing here keeps their stored sessions
// apart: swapping builds is the tester's job (docs/project/CODEBASE/07-build-and-codegen.md).
//
// The local dev stack differs in two ways. It's chosen at launch, not at build,
// by a Debug build started with `SPIRAL_DEV_STACK=1`
// (docs/project/DEV_STACK_SIMULATOR.md). And the NSE doesn't see that launch
// environment, so `AppSettings.agentPlatformBaseURL(forUserID:)` keeps its
// `:localhost` rule beside this.

import Foundation

nonisolated enum SpiralEnvironment {
    case production
    case staging
    case localDev
    
    static let current: SpiralEnvironment = {
        #if SPIRAL_STAGING
        .staging
        #elseif DEBUG
        ProcessInfo.processInfo.environment["SPIRAL_DEV_STACK"] == "1" ? .localDev : .production
        #else
        .production
        #endif
    }()
    
    /// The Matrix server name.
    var serverName: String {
        switch self {
        case .production: "spiral.md"
        case .staging: "staging.spiral.md"
        case .localDev: "localhost"
        }
    }
    
    /// The homeserver offered at sign-in. The dev stack's is plain HTTP on purpose:
    /// the Rust SDK accepts the dev MAS issuer (http://localhost:8081) only for an http homeserver.
    var accountProvider: AccountProvider {
        switch self {
        case .production, .staging: .managed(serverName: serverName, baseURL: baseURL)
        case .localDev: .generic("http://localhost:8008")
        }
    }
    
    /// The platform API. The dev stack's goes through Caddy, whose root CA the simulator must trust.
    /// AGENT-PLATFORM (1.0.3): identity-login's host (`IDENTITY_PUBLIC_URL` in the backend's deploy vars),
    /// where the one-time New phrase and Add Sign in with Apple pages live.
    var identityHost: String {
        switch self {
        case .production: "id.spiral.md"
        case .staging: "id.staging.spiral.md"
        case .localDev: "id.localhost"
        }
    }
    
    var platformURL: URL {
        switch self {
        case .production, .staging: baseURL
        case .localDev: "https://synapse.localhost"
        }
    }
    
    /// The public site: the pages below and the push gateway. The dev stack has none, so it keeps prod's.
    var baseURL: URL {
        switch self {
        case .production, .localDev: "https://spiral.md"
        case .staging: "https://staging.spiral.md"
        }
    }
    
    // These four are the OAuth client's metadata, with `oAuthRedirectURL`: MAS
    // rejects a client whose URIs don't share a host, so none can stay on prod.
    var websiteURL: URL { baseURL.appending(path: "brand/") }
    var logoURL: URL { baseURL.appending(path: "brand/logo.png") }
    var acceptableUseURL: URL { baseURL.appending(path: "brand/terms") }
    var privacyURL: URL { baseURL.appending(path: "brand/privacy") }
    
    var oAuthRedirectURL: URL { baseURL.appending(path: "oidc/login") }
    var catalogURL: URL { baseURL.appending(path: "catalog/") }
    
    /// The word beside the app's name in a build that isn't prod. A word for
    /// developers, so it stays out of `L10n`.
    var screenMark: String? {
        switch self {
        case .production, .localDev: nil
        case .staging: "Staging"
        }
    }
    
    /// The version line as Settings shows it.
    func markedVersionLine(_ versionLine: String) -> String {
        screenMark.map { "\($0) · \(versionLine)" } ?? versionLine
    }
}
