//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import MatrixRustSDK

/// Represents a particular authentication flow.
enum AuthenticationFlow {
    /// The flow for signing in to an existing account.
    case login
    /// The flow for creating a new account.
    case register
}

enum AuthenticationServiceError: Error, Equatable {
    /// An error occurred during OAuth authentication.
    case oAuthError(OAuthError)
    /// An error occurred during login with QR Code.
    case qrCodeError(QRCodeLoginError)
    
    case invalidServer
    case invalidCredentials
    case invalidHomeserverAddress
    case invalidWellKnown(String)
    case slidingSyncNotAvailable
    case loginNotSupported
    case registrationNotSupported
    case elementProRequired(serverName: String)
    case accountDeactivated
    case failedLoggingIn
    case sessionTokenRefreshNotSupported
}

protocol AuthenticationServiceProtocol: QRCodeLoginServiceProtocol {
    /// The currently configured homeserver.
    var homeserver: CurrentValuePublisher<LoginHomeserver, Never> { get }
    /// The type of flow the service is currently configured with.
    var flow: AuthenticationFlow { get }
    
    /// Sets up the service for login on the specified homeserver address.
    func configure(for homeserverAddress: String, flow: AuthenticationFlow) async -> Result<Void, AuthenticationServiceError>
    /// Performs login using OAuth for the current homeserver.
    func urlForOAuthLogin(loginHint: String?) async -> Result<OAuthAuthorizationDataProxy, AuthenticationServiceError>
    /// Asks the SDK to abort an ongoing OAuth login if we didn't get a callback to complete the request with.
    func abortOAuthLogin(data: OAuthAuthorizationDataProxy) async
    /// Completes an OAuth login that was started using ``urlForOAuthLogin``.
    func loginWithOAuthCallback(_ callbackURL: URL) async -> Result<UserSessionProtocol, AuthenticationServiceError>
    /// Performs a password login using the current homeserver.
    func login(username: String, password: String, initialDeviceName: String?, deviceID: String?) async -> Result<UserSessionProtocol, AuthenticationServiceError>
    
    /// Resets the current configuration requiring `configure(for:flow:)` to be called again.
    func reset()
    
    // MARK: - Classic App
    
    /// Account details discovered from the Classic app that is used for automatic verification when the same account is authenticated.
    var classicAppAccount: ClassicAppAccount? { get }
    /// Populates the Classic app account's state by checking if the homeserver is supported and which secrets are available.
    ///
    /// **Note:** This is no longer automatic purely for testing purposes. It needs to have been called before using ``classicAppAccount``.
    func setupClassicAppAccountState() async
    /// This can be called whenever the user has potentially updated their secrets in the Classic app.
    func refreshClassicAppAccountState() async
}

// MARK: - OAuth

enum OAuthError: Error {
    /// Failed to get the URL that should be presented for login.
    case urlFailure
    /// The user cancelled the login.
    case userCancellation
    /// OAuth isn't supported on the currently configured server.
    case notSupported
    /// An unknown error occurred.
    case unknown
}

struct OAuthAuthorizationDataProxy: Hashable {
    let underlyingData: OAuthAuthorizationData
    // AGENT-PLATFORM (Brief 0073 / ADR-0008): the invitation token the
    // person arrived with. Appended to the authorization URL as
    // `spiral_invite`; MAS forwards it to Hydra (additional authorization
    // parameters) and identity-login reads it from the login request. The
    // SDK never sees the modified URL — it only validates the callback's
    // `state`, which is untouched.
    var inviteToken: String?
    // AGENT-PLATFORM (Brief 0073): `spiral_flow=register` tells identity-login
    // which tab to open. The OIDC way (`prompt=create`) is broken in MAS
    // (element-hq/matrix-authentication-service#3429), so the page used to
    // guess from the invitation alone and opened «Sign in» without one.
    var isRegistration = false
    
    static let flowQueryParameter = "spiral_flow"
    
    init(underlyingData: OAuthAuthorizationData, inviteToken: String? = nil, isRegistration: Bool = false) {
        self.underlyingData = underlyingData
        self.inviteToken = inviteToken
        self.isRegistration = isRegistration
    }
    
    var url: URL {
        guard let url = URL(string: underlyingData.loginUrl()) else {
            fatalError("OAuth login URL hasn't been validated.")
        }
        
        // AGENT-PLATFORM (Brief 0073): carry the invitation and the intent.
        var items: [URLQueryItem] = []
        if let inviteToken {
            // The token's alphabet needs no escaping.
            items.append(.init(name: SpiralInviteLink.authorizationQueryParameter,
                               value: inviteToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inviteToken))
        }
        if isRegistration {
            items.append(.init(name: Self.flowQueryParameter, value: "register"))
        }
        guard !items.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        // Append to the percent-encoded query: reading `queryItems` decodes
        // the SDK's values and writing them back re-encodes them differently
        // (`%2B` comes back as `+`).
        components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? []) + items
        return components.url ?? url
    }
}

extension OAuthAuthorizationData: @retroactive Hashable {
    public static func == (lhs: MatrixRustSDK.OAuthAuthorizationData, rhs: MatrixRustSDK.OAuthAuthorizationData) -> Bool {
        lhs.loginUrl() == rhs.loginUrl()
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(loginUrl())
    }
}

// MARK: - Login with QR code

enum QRCodeLoginError: Error, Equatable {
    case invalidQRCode
    case providerNotAllowed(scannedProvider: String, allowedProviders: [String])
    case cancelled
    case connectionInsecure
    case invalidCheckCode
    case declined
    case linkingNotSupported
    case expired
    case slidingSyncNotAvailable
    case deviceNotSignedIn
    case deviceAlreadySignedIn
    case unknown
}

// sourcery: AutoMockable
protocol QRCodeLoginServiceProtocol {
    typealias QRLoginProgressPublisher = CurrentValuePublisher<QRLoginProgress, AuthenticationServiceError>
    func loginWithQRCode(data: Data) -> QRLoginProgressPublisher
}

enum QRLoginProgress {
    case starting
    case establishingSecureChannel(checkCode: UInt8, checkCodeString: String)
    case waitingForToken(userCode: String)
    case syncingSecrets
    case signedIn(UserSessionProtocol)
    
    init?(rustProgress: QrLoginProgress) {
        switch rustProgress {
        case .starting:
            self = .starting
        case .establishingSecureChannel(let checkCode, let checkCodeString):
            self = .establishingSecureChannel(checkCode: checkCode, checkCodeString: checkCodeString)
        case .waitingForToken(let userCode):
            self = .waitingForToken(userCode: userCode)
        case .syncingSecrets:
            self = .syncingSecrets
        case .done:
            return nil // The SDK is done, but the app still needs to set up the UserSession.
        }
    }
}

extension QRLoginProgress: Equatable, CustomStringConvertible {
    static func == (lhs: QRLoginProgress, rhs: QRLoginProgress) -> Bool {
        switch (lhs, rhs) {
        case (.starting, .starting):
            true
        case let (.establishingSecureChannel(lhsCheckCode, lhsCheckCodeString), .establishingSecureChannel(rhsCheckCode, rhsCheckCodeString)):
            lhsCheckCode == rhsCheckCode && lhsCheckCodeString == rhsCheckCodeString
        case let (.waitingForToken(lhsUserCode), .waitingForToken(rhsUserCode)):
            lhsUserCode == rhsUserCode
        case (.syncingSecrets, .syncingSecrets):
            true
        case (.signedIn, .signedIn):
            true
        default:
            false
        }
    }
    
    var description: String {
        switch self {
        case .starting: "starting"
        case .establishingSecureChannel: "establishingSecureChannel"
        case .waitingForToken: "waitingForToken"
        case .syncingSecrets: "syncingSecrets"
        case .signedIn: "signedIn"
        }
    }
}
