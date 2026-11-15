//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (decision 187): the Security hub.
// The Spiral feature is built on Element's `SettingsScreenViewModelTests.swift`.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct SecuritySettingsScreenViewModelTests {
    nonisolated struct EncryptionCase: CustomTestStringConvertible {
        let verification: SessionVerificationState
        let recovery: SecureBackupRecoveryState
        let showsEncryption: Bool
        let showsBadge: Bool
        
        var testDescription: String {
            "\(verification), \(recovery)"
        }
    }
    
    /// Every (verification, recovery) pair: whether Encryption shows, and whether it carries the badge.
    nonisolated static let encryptionCases: [EncryptionCase] = [
        .init(verification: .unknown, recovery: .unknown, showsEncryption: false, showsBadge: false),
        .init(verification: .unknown, recovery: .disabled, showsEncryption: false, showsBadge: false),
        .init(verification: .unknown, recovery: .enabled, showsEncryption: false, showsBadge: false),
        .init(verification: .unknown, recovery: .incomplete, showsEncryption: false, showsBadge: false),
        .init(verification: .unknown, recovery: .settingUp, showsEncryption: false, showsBadge: false),
        .init(verification: .verified, recovery: .unknown, showsEncryption: true, showsBadge: false),
        .init(verification: .verified, recovery: .disabled, showsEncryption: true, showsBadge: true),
        .init(verification: .verified, recovery: .enabled, showsEncryption: true, showsBadge: false),
        .init(verification: .verified, recovery: .incomplete, showsEncryption: true, showsBadge: true),
        .init(verification: .verified, recovery: .settingUp, showsEncryption: true, showsBadge: false),
        .init(verification: .unverified, recovery: .unknown, showsEncryption: true, showsBadge: false),
        .init(verification: .unverified, recovery: .disabled, showsEncryption: true, showsBadge: false),
        .init(verification: .unverified, recovery: .enabled, showsEncryption: true, showsBadge: false),
        .init(verification: .unverified, recovery: .incomplete, showsEncryption: true, showsBadge: false),
        .init(verification: .unverified, recovery: .settingUp, showsEncryption: true, showsBadge: false)
    ]
    
    @Test(arguments: encryptionCases)
    func encryptionRowFollowsTheSessionSecurityState(_ testCase: EncryptionCase) {
        let state = SessionSecurityState(verificationState: testCase.verification, recoveryState: testCase.recovery)
        #expect(state.showsEncryptionSettings == testCase.showsEncryption)
        #expect(state.needsRecoverySetup == testCase.showsBadge)
    }
    
    @Test
    func encryptionRowFollowsAChangeOfState() async throws {
        let (viewModel, securityState) = makeViewModel(verification: .unknown, recovery: .unknown)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!viewModel.context.viewState.showEncryption)
        
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showEncryption)) { $0 }
        securityState.send(.init(verificationState: .verified, recoveryState: .enabled))
        try await shown.fulfill()
        #expect(!viewModel.context.viewState.showEncryptionBadge)
        
        let badged = deferFulfillment(viewModel.context.observe(\.viewState.showEncryptionBadge)) { $0 }
        securityState.send(.init(verificationState: .verified, recoveryState: .incomplete))
        try await badged.fulfill()
    }
    
    // Brief 0075: the row asks first; only the confirmation starts the Face ID + identity-page flow.
    @Test
    func newPhraseAsksBeforeStarting() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled)
        
        viewModel.context.send(viewAction: .newPhrase)
        #expect(viewModel.context.alertInfo?.id == .newPhrase)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0.isNewPhrase }
        viewModel.context.send(viewAction: .confirmNewPhrase)
        try await deferred.fulfill()
    }
    
    @Test
    func devicesRowOpensTheAccountPage() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.accountProfileURL)) { $0 != nil }
        try await loaded.fulfill()
        let url = try #require(viewModel.context.viewState.accountProfileURL)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .manageAccount(url: url) }
        viewModel.context.send(viewAction: .manageAccount(url: url))
        try await deferred.fulfill()
    }
    
    @Test
    func encryptionAndScreenLockRowsOpenTheirFlows() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled)
        
        let secureBackup = deferFulfillment(viewModel.actionsPublisher) { $0 == .secureBackup }
        viewModel.context.send(viewAction: .secureBackup)
        try await secureBackup.fulfill()
        
        let appLock = deferFulfillment(viewModel.actionsPublisher) { $0 == .appLock }
        viewModel.context.send(viewAction: .appLock)
        try await appLock.fulfill()
    }
    
    // MARK: - Helpers
    
    private func makeViewModel(verification: SessionVerificationState,
                               recovery: SecureBackupRecoveryState) -> (SecuritySettingsScreenViewModel, CurrentValueSubject<SessionSecurityState, Never>) {
        let securityState = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: verification, recoveryState: recovery))
        let userSession = UserSessionMock(.init())
        userSession.sessionSecurityStatePublisher = securityState.asCurrentValuePublisher()
        return (SecuritySettingsScreenViewModel(userSession: userSession, appSettings: AppSettings.volatile()), securityState)
    }
}

private extension SecuritySettingsScreenViewModelAction {
    var isNewPhrase: Bool {
        self == .newPhrase
    }
}
