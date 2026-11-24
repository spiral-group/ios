//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078 phase 2): consent to third-party AI — the
// onboarding step, its screen and the Advanced settings toggle.
//

import Combine
import Foundation
@testable import Spiral
import Testing

private let current = "2026-10-10"

@MainActor
struct SpiralAIConsentTests {
    // MARK: - When to ask
    
    @Test
    func asksUntilTheDisclosureInForceIsDecided() {
        #expect(AIConsent(isGranted: false, currentVersion: current, decidedVersion: nil).needsDecision)
        #expect(AIConsent(isGranted: false, currentVersion: current, decidedVersion: "2026-01-01").needsDecision)
        #expect(!AIConsent(isGranted: true, currentVersion: current, decidedVersion: current).needsDecision)
        #expect(!AIConsent(isGranted: false, currentVersion: current, decidedVersion: current).needsDecision)
    }
    
    // MARK: - The prompt
    
    @Test
    func allowRecordsTheGrantAndMovesOn() async throws {
        let service = AgentPlatformServiceMock()
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        let viewModel = AIConsentPromptScreenViewModel(store: store, privacyURL: "https://spiral.md/brand/privacy")
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .done }
        viewModel.context.send(viewAction: .allow)
        try await deferred.fulfill()
        
        #expect(service.setAIConsentGrantedReceivedGranted == true)
        #expect(store.aiConsent?.isGranted == true)
    }
    
    /// Walk F3: the onboarding tapped Allow again while the next screen was
    /// still coming in; each tap saved again and moved the flow on again.
    @Test
    func anAnswerIsRecordedOnceHoweverOftenItIsTapped() async throws {
        let service = AgentPlatformServiceMock()
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        let viewModel = AIConsentPromptScreenViewModel(store: store, privacyURL: "https://spiral.md/brand/privacy")
        
        let done = deferFulfillment(viewModel.actionsPublisher) { $0 == .done }
        viewModel.context.send(viewAction: .allow)
        viewModel.context.send(viewAction: .allow)
        try await done.fulfill()
        
        let noSecondDone = deferFailure(viewModel.actionsPublisher, timeout: .milliseconds(500)) { $0 == .done }
        viewModel.context.send(viewAction: .allow)
        viewModel.context.send(viewAction: .notNow)
        try await noSecondDone.fulfill()
        
        #expect(service.setAIConsentGrantedCallsCount == 1)
        #expect(viewModel.context.viewState.isSaving)
    }
    
    @Test
    func aGrantThatFailsToSaveStaysOnTheScreen() async throws {
        let service = AgentPlatformServiceMock()
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 500))
        let store = AgentsStore(service: service, retryDelays: [])
        let viewModel = AIConsentPromptScreenViewModel(store: store, privacyURL: "https://spiral.md/brand/privacy")
        
        let alert = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .saveFailed }
        let noDone = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { $0 == .done }
        viewModel.context.send(viewAction: .allow)
        try await alert.fulfill()
        try await noDone.fulfill()
        #expect(!viewModel.context.viewState.isSaving)
    }
    
    @Test
    func notNowRecordsTheDeclineAndMovesOnEvenIfUnsaved() async throws {
        let service = AgentPlatformServiceMock()
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 500))
        let store = AgentsStore(service: service, retryDelays: [])
        let viewModel = AIConsentPromptScreenViewModel(store: store, privacyURL: "https://spiral.md/brand/privacy")
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .done }
        viewModel.context.send(viewAction: .notNow)
        try await deferred.fulfill()
        
        #expect(service.setAIConsentGrantedReceivedGranted == false)
    }
    
    // MARK: - Onboarding
    
    @Test
    func onboardingShowsThePromptWhileADecisionIsPending() async {
        let (coordinator, stack) = makeOnboarding(consent: .init(isGranted: false, currentVersion: current, decidedVersion: nil))
        #expect(!coordinator.shouldStart)
        
        await coordinator.refreshAIConsent()
        #expect(coordinator.shouldStart)
        
        coordinator.start()
        #expect(stack.rootCoordinator is AIConsentPromptScreenCoordinator)
    }
    
    /// Brief 0083, question 359: the launch's read is what lets Privacy open knowing the value.
    @Test
    func onboardingsReadStaysInTheStore() async {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        let (coordinator, _) = makeOnboarding(store: store)
        await coordinator.refreshAIConsent()
        
        #expect(store.aiConsent?.isGranted == true)
    }
    
    /// A failed read asks nothing: without a grant the server keeps everything from AI.
    @Test
    func onboardingAsksNothingWhenTheReadFails() async {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 500))
        let (coordinator, _) = makeOnboarding(store: AgentsStore(service: service, retryDelays: []))
        await coordinator.refreshAIConsent()
        #expect(!coordinator.shouldStart)
    }
    
    @Test
    func onboardingAsksNothingOnceDecided() async {
        let (coordinator, _) = makeOnboarding(consent: .init(isGranted: false, currentVersion: current, decidedVersion: current))
        await coordinator.refreshAIConsent()
        #expect(!coordinator.shouldStart)
    }
    
    /// Walk F3: a sign-in whose other steps end before the consent fetch
    /// answers. Finishing then, and starting again on the answer, dismissed
    /// the cover and presented it again inside one dismissal animation.
    @Test
    func onboardingThatEndsBeforeTheConsentIsKnownWaitsForIt() async {
        let (coordinator, stack) = makeOnboarding(consent: .init(isGranted: false, currentVersion: current, decidedVersion: nil), isNewLogin: true)
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        #expect(dismissals == 0)
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        await coordinator.refreshAIConsent()
        #expect(dismissals == 0)
        #expect(stack.stackCoordinators.last is AIConsentPromptScreenCoordinator)
        #expect(!coordinator.shouldStart)
    }
    
    @Test
    func onboardingThatWaitedEndsOnceNothingIsAsked() async {
        let (coordinator, _) = makeOnboarding(consent: .init(isGranted: true, currentVersion: current, decidedVersion: current), isNewLogin: true)
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        #expect(dismissals == 0)
        
        await coordinator.refreshAIConsent()
        #expect(dismissals == 1)
        #expect(!coordinator.shouldStart)
    }
    
    // MARK: - Identity confirmation waits for the verification state (1.0.3)
    
    /// Operator, 2026-11-21: a new account showed the identity screen with
    /// «Loading…» for a moment and skipped it once it had verified itself.
    @Test
    func aNewAccountWaitsAndNeverSeesTheIdentityScreen() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        security.send(.init(verificationState: .verified, recoveryState: .enabled))
        #expect(await eventually { dismissals == 1 })
        #expect(!(stack.rootCoordinator is IdentityConfirmationScreenCoordinator))
    }
    
    @Test
    func anUnverifiedSessionGetsTheIdentityScreenInPlaceOfTheWait() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        security.send(.init(verificationState: .unverified, recoveryState: .unknown))
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        #expect(stack.stackCoordinators.isEmpty)
    }
    
    /// A state that never arrives still ends on the screen, with its loader and sign-out.
    @Test
    func aStateThatStaysUnknownOpensTheIdentityScreenAfterTheTimeout() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        coordinator.verificationStateWaitTimeout = 0.05
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        #expect(stack.stackCoordinators.isEmpty)
    }
    
    /// Fable review (1.0.3 identity flash): the screen the timeout opens has Sign out within reach, so a person signed
    /// in offline isn't stuck behind a modal «Loading…» that blocks the window.
    @Test
    func theScreenTheTimeoutOpensDoesNotBlockSignOut() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let indicators = UserIndicatorControllerMock()
        var blockingIndicators = 0
        indicators.submitIndicatorDelayClosure = { indicator, _ in
            if !indicator.allowsInteraction { blockingIndicators += 1 }
        }
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, indicators: indicators)
        coordinator.verificationStateWaitTimeout = 0.05
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        try? await Task.sleep(for: .milliseconds(200)) // The screen reads the state in a task of its own.
        #expect(blockingIndicators == 0)
    }
    
    /// Fable review (1.0.3 identity flash): a state that arrives after the timeout still settles the screen.
    @Test
    func aSessionThatVerifiesAfterTheTimeoutLeavesTheIdentityScreen() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        coordinator.verificationStateWaitTimeout = 0.05
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        
        security.send(.init(verificationState: .verified, recoveryState: .enabled))
        #expect(await eventually { dismissals == 1 })
    }
    
    @Test
    func aSessionFoundUnverifiedAfterTheTimeoutKeepsTheOneIdentityScreen() async throws {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        coordinator.verificationStateWaitTimeout = 0.05
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        let screen = try #require(stack.rootCoordinator)
        
        security.send(.init(verificationState: .unverified, recoveryState: .enabled))
        try await Task.sleep(for: .milliseconds(200))
        #expect(stack.rootCoordinator === screen, "The screen already shown is not replaced.")
        #expect(stack.stackCoordinators.isEmpty, "Nor is a second one pushed on it.")
    }
    
    /// A wait that ended (the session verified) and a new one started: the first wait's timer is not the second's.
    @Test
    func aRestartedWaitIsNotCutShortByTheEarlierWaitsTimer() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let userSettings = UserSettings.mock()
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, userSettings: userSettings)
        coordinator.verificationStateWaitTimeout = 0.2
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        security.send(.init(verificationState: .verified, recoveryState: .enabled))
        #expect(await eventually { dismissals == 1 })
        
        // The session is reset meanwhile: identity confirmation is owed again and its state is unknown again.
        userSettings.account.hasRunIdentityConfirmationOnboarding = false
        security.send(.init(verificationState: .unknown, recoveryState: .unknown))
        coordinator.verificationStateWaitTimeout = 10
        #expect(coordinator.shouldStart)
        coordinator.start()
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        try? await Task.sleep(for: .milliseconds(400)) // Past the first wait's 0.2 s.
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
    }
    
    /// Review finding: a session already verified when the step begins skips it.
    @Test
    func aSessionAlreadyVerifiedSkipsTheIdentityStep() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .verified, recoveryState: .enabled))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security)
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        #expect(!(stack.rootCoordinator is IdentityConfirmationScreenCoordinator))
        #expect(await eventually { dismissals == 1 })
    }
    
    /// An account with an identity to confirm gets the screen as soon as that is known, in place of the wait.
    @Test
    func aKnownUnverifiedSessionGetsTheIdentityScreenOnceItsIdentityIsFound() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unverified, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, security: security)
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
        #expect(stack.stackCoordinators.isEmpty)
    }
    
    /// Operator, 2026-11-23: a new account reports `.unverified` until the SDK has set up its cross-signing identity,
    /// then `.verified`; the identity screen showed in between. Without an identity yet, the wait goes on.
    @Test
    func aNewAccountWithoutAnIdentityYetWaitsThroughUnverified() async throws {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, ownIdentity: .missing)
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        security.send(.init(verificationState: .unverified, recoveryState: .unknown))
        try await Task.sleep(for: .milliseconds(200))
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator, "Still the logo, no identity screen.")
        
        security.send(.init(verificationState: .verified, recoveryState: .disabled))
        #expect(await eventually { dismissals == 1 })
        #expect(!(stack.rootCoordinator is IdentityConfirmationScreenCoordinator))
    }
    
    /// The same when the state is already `.unverified` as the step begins (it came while the flow was `.initial`).
    @Test
    func aNewAccountAlreadyUnverifiedWithoutAnIdentityWaitsToo() async throws {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unverified, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, ownIdentity: .missing)
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        security.send(.init(verificationState: .verified, recoveryState: .disabled))
        #expect(await eventually { dismissals == 1 })
    }
    
    /// The identity the SDK has just set up is uploaded a moment before the device is marked verified: still the logo.
    @Test
    func aNewAccountWhoseIdentityIsJustSetUpWaitsToo() async throws {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unknown, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, ownIdentity: .trusted)
        await coordinator.refreshAIConsent()
        var dismissals = 0
        let cancellable = coordinator.actions.sink { if case .dismiss = $0 { dismissals += 1 } }
        defer { cancellable.cancel() }
        
        coordinator.start()
        security.send(.init(verificationState: .unverified, recoveryState: .disabled))
        try await Task.sleep(for: .milliseconds(200))
        #expect(stack.rootCoordinator is PlaceholderScreenCoordinator)
        
        security.send(.init(verificationState: .verified, recoveryState: .disabled))
        #expect(await eventually { dismissals == 1 })
    }
    
    /// An identity that never comes still ends on the screen after the timeout, as an unknown state does.
    @Test
    func anUnverifiedSessionWithoutAnIdentityGetsTheScreenAfterTheTimeout() async {
        let security = CurrentValueSubject<SessionSecurityState, Never>(.init(verificationState: .unverified, recoveryState: .unknown))
        let (coordinator, stack) = makeOnboarding(consent: decided, isNewLogin: true, security: security, ownIdentity: .missing)
        coordinator.verificationStateWaitTimeout = 0.05
        await coordinator.refreshAIConsent()
        
        coordinator.start()
        #expect(await eventually { stack.rootCoordinator is IdentityConfirmationScreenCoordinator })
    }
    
    /// The account's cross-signing identity as this device sees it.
    private enum OwnIdentity {
        /// None yet: a new account before the SDK has set one up.
        case missing
        /// One this device trusts: a new account's, just set up here, before the device is marked verified.
        case trusted
        /// One this device doesn't trust yet: an existing account's, to confirm.
        case untrusted
    }
    
    private var decided: AIConsent {
        .init(isGranted: true, currentVersion: current, decidedVersion: current)
    }
    
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
    
    private func makeOnboarding(consent: AIConsent,
                                isNewLogin: Bool = false,
                                security: CurrentValueSubject<SessionSecurityState, Never>? = nil,
                                indicators: UserIndicatorControllerMock = UserIndicatorControllerMock(),
                                userSettings: UserSettings = .mock(),
                                ownIdentity: OwnIdentity = .untrusted) -> (OnboardingFlowCoordinator, NavigationStackCoordinator) {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(consent)
        return makeOnboarding(store: AgentsStore(service: service, retryDelays: []),
                              isNewLogin: isNewLogin,
                              security: security,
                              indicators: indicators,
                              userSettings: userSettings,
                              ownIdentity: ownIdentity)
    }
    
    private func makeOnboarding(store: AgentsStore,
                                isNewLogin: Bool = false,
                                security: CurrentValueSubject<SessionSecurityState, Never>? = nil,
                                indicators: UserIndicatorControllerMock = UserIndicatorControllerMock(),
                                userSettings: UserSettings = .mock(),
                                ownIdentity: OwnIdentity = .untrusted) -> (OnboardingFlowCoordinator, NavigationStackCoordinator) {
        // A session handed a security state is one that hasn't been through identity confirmation.
        userSettings.account.hasRunIdentityConfirmationOnboarding = security == nil
        userSettings.app.hasRunNotificationPermissionsOnboarding = true
        
        let clientProxy = ClientProxyMock(.init())
        switch ownIdentity {
        case .untrusted: break // The mock's default: an identity this device doesn't trust yet.
        case .missing: clientProxy.userIdentityForFallBackToServerReturnValue = .success(nil)
        case .trusted: clientProxy.userIdentityForFallBackToServerReturnValue = .success(UserIdentityProxyMock(.init(verificationState: .verified)))
        }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy, userSettings: userSettings))
        userSession.agentsStore = store
        if let security {
            userSession.sessionSecurityStatePublisher = security.asCurrentValuePublisher()
        }
        
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: indicators,
                                                  stateMachineFactory: PublishedStateMachineFactory())
        let stack = NavigationStackCoordinator()
        let coordinator = OnboardingFlowCoordinator(isNewLogin: isNewLogin,
                                                    appLockService: AppLockServiceMock(),
                                                    navigationStackCoordinator: stack,
                                                    flowParameters: flowParameters)
        return (coordinator, stack)
    }
    
    // MARK: - Privacy (Advanced settings re-purposed, decision 187)
    
    @Test
    func advancedSettingsShowsTheServersDecision() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let viewModel = makeAdvancedSettings(service: service)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: true) }
        try await deferred.fulfill()
    }
    
    @Test
    func withdrawingThatFailsToSaveFlipsTheToggleBack() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: true) }
        try await loaded.fulfill()
        
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: true) && service.setAIConsentGrantedCalled }
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await settled.fulfill()
        
        #expect(service.setAIConsentGrantedReceivedGranted == false)
    }
    
    @Test
    func withdrawingRecordsTheDeclineThroughTheStore() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: false, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        let viewModel = makeAdvancedSettings(store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: true) }
        try await loaded.fulfill()
        
        let withdrawn = deferFulfillment(viewModel.context.observe(\.viewState.isWaitingAIConsent)) { !$0 && service.setAIConsentGrantedCalled }
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await withdrawn.fulfill()
        
        #expect(viewModel.context.viewState.aiConsent == .answered(isGranted: false))
        #expect(store.aiConsent?.isGranted == false)
    }
    
    /// A write that failed may have landed: the switch waits for a read, and shows Retry when that fails too.
    @Test
    func aFailedWriteTakesNoTapUntilAReadAnswers() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: true) }
        try await loaded.fulfill()
        
        let read = HeldRead<AIConsent>(answer: .failure(.serverError(status: 500)))
        service.fetchAIConsentClosure = { await read.answer() }
        let reading = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .reading(isGranted: true) }
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await reading.fulfill()
        
        viewModel.context.send(viewAction: .updateAIConsent(false))
        await read.waitUntilAsked()
        
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .failed }
        read.release()
        try await failed.fulfill()
        #expect(service.setAIConsentGrantedCallsCount == 1)
    }
    
    // Decision 150: «Open Settings» lands here, so a failed read must not hide the choice.
    @Test
    func aFailedReadOffersARetryThatLoadsTheToggle() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .failed }
        try await failed.fulfill()
        let reads = service.fetchAIConsentCallsCount
        
        service.fetchAIConsentReturnValue = .success(.init(isGranted: false, currentVersion: current, decidedVersion: current))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: false) }
        viewModel.context.send(viewAction: .retryAIConsent)
        try await loaded.fulfill()
        #expect(service.fetchAIConsentCallsCount == reads + 1)
    }
    
    /// Brief 0083, question 359: the row stands from the first frame, in place, and reads as neither on nor off.
    @Test
    func theConsentRowStandsBeforeTheReadAnswers() async throws {
        let service = AgentPlatformServiceMock()
        let read = HeldRead<AIConsent>(answer: .success(.init(isGranted: false, currentVersion: current, decidedVersion: current)))
        service.fetchAIConsentClosure = { await read.answer() }
        let viewModel = makeAdvancedSettings(service: service)
        
        #expect(viewModel.context.viewState.aiConsent == .reading(isGranted: nil))
        await read.waitUntilAsked()
        viewModel.context.send(viewAction: .updateAIConsent(true))
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: false) }
        read.release()
        try await loaded.fulfill()
        #expect(!service.setAIConsentGrantedCalled)
    }
    
    /// Brief 0083, question 359: a value from this session shows at once, but the switch takes taps
    /// only after this opening's read answers, and then shows what that read said.
    @Test
    func aRememberedValueShowsAtOnceAndTakesNoTapUntilTheRead() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        await store.reread(.aiConsent)
        
        let read = HeldRead<AIConsent>(answer: .success(.init(isGranted: false, currentVersion: current, decidedVersion: current)))
        service.fetchAIConsentClosure = { await read.answer() }
        let viewModel = makeAdvancedSettings(store: store)
        
        #expect(viewModel.context.viewState.aiConsent == .reading(isGranted: true))
        #expect(!viewModel.context.viewState.aiConsent.takesTaps)
        await read.waitUntilAsked()
        viewModel.context.send(viewAction: .updateAIConsent(false))
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: false) }
        read.release()
        try await loaded.fulfill()
        #expect(!service.setAIConsentGrantedCalled)
    }
    
    /// Brief 0083, question 359: stricter than the store's "keep what was shown".
    @Test
    func aFailedOpeningReadShowsRetryEvenWithARememberedValue() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let store = AgentsStore(service: service, retryDelays: [])
        await store.reread(.aiConsent)
        
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(store: store)
        #expect(viewModel.context.viewState.aiConsent == .reading(isGranted: true))
        
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .failed }
        try await failed.fulfill()
        
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!service.setAIConsentGrantedCalled)
    }
    
    /// A read that left before this opening doesn't count as this opening's: one more follows it.
    @Test
    func aReadAlreadyOnItsWayIsNotThisOpeningsRead() async throws {
        let service = AgentPlatformServiceMock()
        let earlier = HeldRead<AIConsent>(answer: .success(.init(isGranted: true, currentVersion: current, decidedVersion: current)))
        service.fetchAIConsentClosure = { await earlier.answer() }
        let store = AgentsStore(service: service, retryDelays: [])
        store.refresh(.aiConsent)
        await earlier.waitUntilAsked()
        
        let viewModel = makeAdvancedSettings(store: store)
        await Task.yield()
        let opening = HeldRead<AIConsent>(answer: .success(.init(isGranted: false, currentVersion: current, decidedVersion: current)))
        service.fetchAIConsentClosure = { await opening.answer() }
        
        let remembered = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .reading(isGranted: true) }
        earlier.release()
        try await remembered.fulfill()
        
        await opening.waitUntilAsked()
        #expect(!viewModel.context.viewState.aiConsent.takesTaps)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .answered(isGranted: false) }
        opening.release()
        try await loaded.fulfill()
    }
    
    /// The store keeps trying a shown read, and the Retry row follows its answer.
    @Test
    func theStoresOwnRetryAnswersTheRetryRow() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(store: AgentsStore(service: service, retryDelays: [.seconds(1)]))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent)) { $0 == .failed }
        try await failed.fulfill()
        
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsent), timeout: .seconds(5)) { $0 == .answered(isGranted: true) }
        try await loaded.fulfill()
    }
    
    @Test
    func advancedSettingsWithoutThePlatformHasNoToggle() async throws {
        let viewModel = makeAdvancedSettings(store: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.context.viewState.aiConsent == .unavailable)
    }
    
    private func makeAdvancedSettings(service: AgentPlatformServiceMock) -> ModerationAndSafetySettingsScreenViewModel {
        makeAdvancedSettings(store: AgentsStore(service: service, retryDelays: []))
    }
    
    private func makeAdvancedSettings(store: AgentsStore?) -> ModerationAndSafetySettingsScreenViewModel {
        let userSession = UserSessionMock(.init())
        userSession.agentsStore = store
        return ModerationAndSafetySettingsScreenViewModel(userSession: userSession,
                                                          userIndicatorController: UserIndicatorControllerMock())
    }
}

/// A read that answers only once the test releases it, and says when it was asked.
final class HeldRead<Value: Sendable>: Sendable {
    private let answerValue: Result<Value, AgentPlatformError>
    private let asked = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()
    
    init(answer: Result<Value, AgentPlatformError>) {
        answerValue = answer
    }
    
    func answer() async -> Result<Value, AgentPlatformError> {
        asked.continuation.yield()
        for await _ in gate.stream { }
        return answerValue
    }
    
    func waitUntilAsked() async {
        for await _ in asked.stream {
            return
        }
    }
    
    func release() {
        gate.continuation.finish()
    }
}
