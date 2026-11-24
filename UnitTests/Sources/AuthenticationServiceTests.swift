//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
import MatrixRustSDKMocks
@testable import Spiral
import Testing

@MainActor
struct AuthenticationServiceTests {
    var client: ClientSDKMock!
    var userSessionManager: UserSessionManagerMock!
    var encryptionKeyProvider: MockEncryptionKeyProvider!
    var service: AuthenticationService!
    var appSettings: AppSettings!
    
    @Test
    mutating func passwordLogin() async throws {
        try await setup(serverNameOrBaseURL: "example.com")
        
        switch await service.configure(for: "example.com", flow: .login) {
        case .success:
            break
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
        
        #expect(service.flow == .login)
        #expect(service.homeserver.value == .mockBasicServer)
        
        switch await service.login(username: "alice", password: "12345678", initialDeviceName: nil, deviceID: nil) {
        case .success:
            #expect(client.loginUsernamePasswordInitialDeviceNameDeviceIdCallsCount == 1)
            #expect(userSessionManager.userSessionForSessionDirectoriesPassphraseCallsCount == 1)
            #expect(userSessionManager.userSessionForSessionDirectoriesPassphraseReceivedArguments?.passphrase == encryptionKeyProvider.generateKey())
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }
    
    @Test
    mutating func configureLoginWithOAuth() async throws {
        try await setup()
        
        try await service.configure(for: "matrix.org", flow: .login).get()
        
        #expect(service.flow == .login)
        #expect(service.homeserver.value == .mockMatrixDotOrg)
    }
    
    @Test
    mutating func configureRegisterWithOAuth() async throws {
        try await setup()
        
        try await service.configure(for: "matrix.org", flow: .register).get()
        
        #expect(service.flow == .register)
        #expect(service.homeserver.value == .mockMatrixDotOrg)
    }
    
    @Test
    mutating func configureRegisterNoSupport() async throws {
        let serverNameOrBaseURL = "example.com"
        try await setup(serverNameOrBaseURL: serverNameOrBaseURL)
        
        try await #require(throws: AuthenticationServiceError.registrationNotSupported) {
            try await service.configure(for: serverNameOrBaseURL, flow: .register).get()
        }
        
        #expect(service.flow == .login)
        #expect(service.homeserver.value == .init(accountProvider: .managed(serverName: "matrix.org", baseURL: "https://matrix-client.matrix.org"),
                                                  loginMode: .unknown))
    }
    
    @Test(arguments: [("matrix.org", AuthenticationFlow.login, OAuthPrompt.consent),
                      ("matrix.org", .register, .create),
                      ("company.com", .register, .consent)])
    mutating func oAuthPrompt(serverName: String, flow: AuthenticationFlow, expectedPrompt: OAuthPrompt) async throws {
        try await setup(serverNameOrBaseURL: serverName)
        try await service.configure(for: serverName, flow: flow).get()
        
        _ = try await service.urlForOAuthLogin(loginHint: nil).get()
        
        #expect(client.urlForOauthOauthConfigurationPromptLoginHintDeviceIdAdditionalScopesReceivedArguments?.prompt == expectedPrompt)
    }
    
    // AGENT-PLATFORM (Brief 0083 L1b): no classicAppAccountSecretsBundle* tests, Element Classic's import is gone.
    
    // MARK: - The pending invitation after a sign-in (1.0.3 B8)
    
    private static let invite = PendingInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Ann", inviterUserID: "@ann:matrix.org")
    private static let callbackURL: URL = "io.element:/callback?code=c&state=s"
    
    @Test
    mutating func aRegistrationThatCarriedTheInvitationKeepsIt() async throws {
        try await setup()
        appSettings.pendingInvite = Self.invite
        
        try await service.configure(for: "matrix.org", flow: .register).get()
        let data = try await service.urlForOAuthLogin(loginHint: nil).get()
        #expect(data.inviteToken == Self.invite.token)
        _ = try await service.loginWithOAuthCallback(Self.callbackURL).get()
        
        #expect(appSettings.pendingInvite == Self.invite)
    }
    
    // 1.0.3: a sign-in no longer drops the pending invitation here — the app coordinator drops it once a session
    // starts, and the welcome comes from the platform (`InviteWelcomeOfferTests`), so a stale one greets nobody.
    
    @Test
    mutating func aFailedSignInKeepsThePendingInvitation() async throws {
        try await setup()
        appSettings.pendingInvite = Self.invite
        client.loginWithOauthCallbackCallbackUrlThrowableError = NSError(domain: "AuthenticationServiceTests", code: 1)
        
        try await service.configure(for: "matrix.org", flow: .login).get()
        _ = try await service.urlForOAuthLogin(loginHint: nil).get()
        _ = await service.loginWithOAuthCallback(Self.callbackURL)
        
        #expect(appSettings.pendingInvite == Self.invite)
    }
    
    // MARK: - Helpers
    
    private mutating func setup(serverNameOrBaseURL: String = "matrix.org") async throws {
        let configuration: ClientFactoryMock.Configuration = .init()
        let clientFactory = ClientFactoryMock(configuration)
        
        client = configuration.homeserverClients[serverNameOrBaseURL]
        
        userSessionManager = UserSessionManagerMock(.init())
        encryptionKeyProvider = MockEncryptionKeyProvider()
        
        // AGENT-PLATFORM: these tests exercise the UPSTREAM auth flows with
        // matrix.org fixtures; restore the open upstream provider shape since
        // the fork defaults to a single closed provider (spiral.md).
        let appSettings = AppSettings.volatile()
        self.appSettings = appSettings
        appSettings.override(accountProviders: [.managed(serverName: "matrix.org", baseURL: "https://matrix-client.matrix.org")],
                             allowOtherAccountProviders: true,
                             hideBrandChrome: false,
                             pushGatewayBaseURL: appSettings.pushGatewayBaseURL,
                             oAuthRedirectURL: appSettings.oAuthRedirectURL,
                             oAuthClientURIPath: appSettings.oAuthClientURIPath,
                             websiteURL: appSettings.websiteURL,
                             logoURL: appSettings.logoURL,
                             copyrightURL: appSettings.copyrightURL,
                             acceptableUseURL: appSettings.acceptableUseURL,
                             privacyURL: appSettings.privacyURL,
                             encryptionURL: appSettings.encryptionURL,
                             deviceVerificationURL: appSettings.deviceVerificationURL,
                             chatBackupDetailsURL: appSettings.chatBackupDetailsURL,
                             identityPinningViolationDetailsURL: appSettings.identityPinningViolationDetailsURL,
                             historySharingDetailsURL: appSettings.historySharingDetailsURL, // AGENT-PLATFORM (Brief 0083 L1b): no accountProvisioningHost
                             bugReportApplicationID: appSettings.bugReportApplicationID,
                             analyticsTermsURL: appSettings.analyticsTermsURL,
                             mapTilerConfiguration: AppSettings.bundledMapTilerConfiguration)
        
        service = AuthenticationService(userSessionManager: userSessionManager,
                                        encryptionKeyProvider: encryptionKeyProvider,
                                        clientFactory: clientFactory,
                                        appSettings: appSettings,
                                        appHooks: AppHooks()) // AGENT-PLATFORM (Brief 0083 L1b): no Classic app manager
    }
}

struct MockEncryptionKeyProvider: EncryptionKeyProviderProtocol {
    private let key = "12345678"
    
    func generateKey() -> Data {
        Data(key.utf8)
    }
}
