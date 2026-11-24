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
    
    // MARK: - Sign-in methods (1.0.3)
    
    /// An account made with Apple has no phrase: the row, the alert and the flow say «add».
    @Test
    func anAccountWithoutAPhraseIsOfferedToAddOne() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(.init(phrase: false, apple: true, appleAvailable: true)))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.phrase == false }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.phraseRowTitle == UntranslatedL10n.screenSettingsAddPhraseTitle)
        #expect(viewModel.context.viewState.signInMethods.appleRow == .linked)
        
        viewModel.context.send(viewAction: .newPhrase)
        #expect(viewModel.context.alertInfo?.title == UntranslatedL10n.screenSettingsAddPhraseTitle)
        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenSettingsAddPhraseMessage)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .newPhrase(addsFirstPhrase: true) }
        viewModel.context.send(viewAction: .confirmNewPhrase)
        try await deferred.fulfill()
    }
    
    @Test
    func anAccountWithAPhraseKeepsNewPhrase() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(.init(phrase: true, apple: false, appleAvailable: true)))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.phrase == true }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.phraseRowTitle == UntranslatedL10n.screenSettingsNewPhraseTitle)
        #expect(viewModel.context.viewState.signInMethods.appleRow == .add)
        
        viewModel.context.send(viewAction: .newPhrase)
        #expect(viewModel.context.alertInfo?.title == UntranslatedL10n.screenSettingsNewPhraseTitle)
        #expect(viewModel.context.alertInfo?.message == UntranslatedL10n.screenSettingsNewPhraseMessage)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .newPhrase(addsFirstPhrase: false) }
        viewModel.context.send(viewAction: .confirmNewPhrase)
        try await deferred.fulfill()
        viewModel.signInFlowFinished()
        
        let addApple = deferFulfillment(viewModel.actionsPublisher) { $0 == .addApple }
        viewModel.context.send(viewAction: .addApple)
        try await addApple.fulfill()
    }
    
    /// Checklist point 1: a failed read is unknown, not «no phrase» — today's label, no Apple row.
    @Test
    func aFailedReadKeepsNewPhraseAndShowsNoAppleRow() async throws {
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .failure(.notFound))
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(service.fetchSignInMethodsCallsCount == 1)
        #expect(viewModel.context.viewState.signInMethods == .unknown)
        #expect(viewModel.context.viewState.phraseRowTitle == UntranslatedL10n.screenSettingsNewPhraseTitle)
        #expect(viewModel.context.viewState.signInMethods.appleRow == nil)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .newPhrase(addsFirstPhrase: false) }
        viewModel.context.send(viewAction: .confirmNewPhrase)
        try await deferred.fulfill()
    }
    
    /// A server without Sign in with Apple configured gets no Apple row.
    @Test
    func noAppleRowWhereTheServerHasNoApple() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(.init(phrase: true, apple: false, appleAvailable: false)))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.phrase == true }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.signInMethods.appleRow == nil)
    }
    
    /// After the Apple link, the flow reloads and the row reads «Connected».
    @Test
    func aReloadAfterLinkingShowsAppleConnected() async throws {
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .success(.init(phrase: true, apple: false, appleAvailable: true)))
        let added = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.appleRow == .add }
        try await added.fulfill()
        
        service.fetchSignInMethodsReturnValue = .success(.init(phrase: true, apple: true, appleAvailable: true))
        let linked = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.appleRow == .linked }
        viewModel.loadSignInMethods()
        try await linked.fulfill()
    }
    
    /// A failed reload keeps what the screen already shows.
    @Test
    func aFailedReloadKeepsTheLastAnswer() async throws {
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .success(.init(phrase: false, apple: true, appleAvailable: true)))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.phrase == false }
        try await loaded.fulfill()
        
        service.fetchSignInMethodsReturnValue = .failure(.serverError(status: 500))
        viewModel.loadSignInMethods()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(service.fetchSignInMethodsCallsCount == 2)
        #expect(viewModel.context.viewState.phraseRowTitle == UntranslatedL10n.screenSettingsAddPhraseTitle)
    }
    
    // MARK: - Cached sign-in methods (stable UI)
    
    /// The cached answer draws the rows on the first frame, before the refresh answers.
    @Test
    func aCachedAnswerRendersImmediately() {
        let userSettings = UserSettings.mock()
        userSettings.account.signInMethods = .init(phrase: false, apple: true, appleAvailable: true)
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(.unknown), userSettings: userSettings) {
            try? await Task.sleep(for: .seconds(5))
        }
        
        #expect(viewModel.context.viewState.phraseRowTitle == UntranslatedL10n.screenSettingsAddPhraseTitle)
        #expect(viewModel.context.viewState.signInMethods.appleRow == .linked)
    }
    
    /// A refresh with a different answer updates the rows and the cache.
    @Test
    func aChangedAnswerReplacesTheCachedOne() async throws {
        let userSettings = UserSettings.mock()
        userSettings.account.signInMethods = .init(phrase: true, apple: false, appleAvailable: true)
        let fresh = SignInMethods(phrase: true, apple: true, appleAvailable: true)
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(fresh), userSettings: userSettings)
        #expect(viewModel.context.viewState.signInMethods.appleRow == .add)
        
        let linked = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.appleRow == .linked }
        try await linked.fulfill()
        #expect(userSettings.account.signInMethods == fresh)
    }
    
    /// The first answer, with nothing cached yet, is kept for next time.
    @Test
    func theFirstAnswerIsCached() async throws {
        let userSettings = UserSettings.mock()
        let answer = SignInMethods(phrase: false, apple: true, appleAvailable: false)
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(answer), userSettings: userSettings)
        #expect(viewModel.context.viewState.signInMethods == .unknown)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0 == answer }
        try await loaded.fulfill()
        #expect(userSettings.account.signInMethods == answer)
    }
    
    /// Sign-out resets the account's settings (`AppCoordinator`), and the cache with them.
    @Test
    func signingOutClearsTheCache() {
        let userSettings = UserSettings.mock()
        userSettings.account.signInMethods = .init(phrase: false, apple: true, appleAvailable: true)
        
        userSettings.account.reset()
        
        #expect(userSettings.account.signInMethods == nil)
    }
    
    // MARK: - Review fixes (1.0.3)
    
    /// A second tap while a flow runs starts nothing; the flow's end lets the next one start.
    @Test
    func aSecondTapStartsNoSecondFlow() async throws {
        let (viewModel, _) = makeViewModel(verification: .verified, recovery: .enabled,
                                           signInMethods: .success(.init(phrase: true, apple: false, appleAvailable: true)))
        var started = [SecuritySettingsScreenViewModelAction]()
        let cancellable = viewModel.actionsPublisher.sink { started.append($0) }
        defer { cancellable.cancel() }
        
        viewModel.context.send(viewAction: .confirmNewPhrase)
        viewModel.context.send(viewAction: .confirmNewPhrase)
        viewModel.context.send(viewAction: .addApple)
        #expect(started == [.newPhrase(addsFirstPhrase: false)])
        
        viewModel.signInFlowFinished()
        viewModel.context.send(viewAction: .addApple)
        viewModel.context.send(viewAction: .addApple)
        #expect(started == [.newPhrase(addsFirstPhrase: false), .addApple])
    }
    
    /// Every outcome reloads, a cancelled sheet included: the page may have saved before it closed.
    @Test
    func theEndOfAnyFlowReloadsTheMethods() async throws {
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .success(.init(phrase: true, apple: false, appleAvailable: true)))
        let added = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.appleRow == .add }
        try await added.fulfill()
        #expect(service.fetchSignInMethodsCallsCount == 1)
        
        viewModel.context.send(viewAction: .addApple)
        service.fetchSignInMethodsReturnValue = .success(.init(phrase: true, apple: true, appleAvailable: true))
        let linked = deferFulfillment(viewModel.context.observe(\.viewState.signInMethods)) { $0.appleRow == .linked }
        viewModel.signInFlowFinished() // e.g. the sheet was closed after Apple had already been linked
        try await linked.fulfill()
        #expect(service.fetchSignInMethodsCallsCount == 2)
    }
    
    /// An answer that arrives after sign-out reset the account doesn't write the cache back.
    @Test
    func anAnswerAfterSignOutIsNotCached() async throws {
        let userSettings = UserSettings.mock()
        let gate = AnswerGate()
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .success(.init(phrase: false, apple: true, appleAvailable: true)),
                                                 userSettings: userSettings) {
            await gate.wait()
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(service.fetchSignInMethodsCallsCount == 1)
        
        userSettings.account.reset() // what sign-out does
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(userSettings.account.signInMethods == nil)
        #expect(viewModel.context.viewState.signInMethods == .unknown)
    }
    
    /// A partial answer keeps what the cache knew for the fields it left out.
    @Test
    func aPartialAnswerKeepsTheCachedFields() async throws {
        let userSettings = UserSettings.mock()
        userSettings.account.signInMethods = .init(phrase: false, apple: true, appleAvailable: true)
        let (viewModel, service) = makeViewModel(verification: .verified, recovery: .enabled,
                                                 signInMethods: .success(.init(phrase: nil, apple: true, appleAvailable: false)),
                                                 userSettings: userSettings)
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(service.fetchSignInMethodsCallsCount == 1)
        #expect(viewModel.context.viewState.signInMethods == .init(phrase: false, apple: true, appleAvailable: true))
        #expect(userSettings.account.signInMethods == .init(phrase: false, apple: true, appleAvailable: true))
    }
    
    // MARK: - Helpers
    
    private func makeViewModel(verification: SessionVerificationState,
                               recovery: SecureBackupRecoveryState) -> (SecuritySettingsScreenViewModel, CurrentValueSubject<SessionSecurityState, Never>) {
        let securityState = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: verification, recoveryState: recovery))
        let userSession = UserSessionMock(.init())
        userSession.sessionSecurityStatePublisher = securityState.asCurrentValuePublisher()
        return (SecuritySettingsScreenViewModel(userSession: userSession, appSettings: AppSettings.volatile()), securityState)
    }
    
    private func makeViewModel(verification: SessionVerificationState,
                               recovery: SecureBackupRecoveryState,
                               signInMethods: Result<SignInMethods, AgentPlatformError>,
                               userSettings: UserSettings = .mock(),
                               beforeAnswering delay: (@Sendable () async -> Void)? = nil) -> (SecuritySettingsScreenViewModel, AgentPlatformServiceMock) {
        let userSession = UserSessionMock(.init())
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(.init(verificationState: verification, recoveryState: recovery)).asCurrentValuePublisher()
        userSession.userSettings = userSettings
        let service = AgentPlatformServiceMock()
        service.fetchSignInMethodsReturnValue = signInMethods
        if let delay {
            service.fetchSignInMethodsClosure = {
                await delay()
                return signInMethods
            }
        }
        userSession.agentPlatformService = service
        return (SecuritySettingsScreenViewModel(userSession: userSession, appSettings: AppSettings.volatile()), service)
    }
}

private extension SecuritySettingsScreenViewModelAction {
    var isNewPhrase: Bool {
        self == .newPhrase(addsFirstPhrase: false)
    }
}

/// Holds a mocked answer until the test opens it.
private actor AnswerGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
