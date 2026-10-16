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
@testable import ElementX
import Foundation
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
        let viewModel = AIConsentPromptScreenViewModel(agentPlatformService: service, privacyURL: "https://spiral.md/brand/privacy")
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .done }
        viewModel.context.send(viewAction: .allow)
        try await deferred.fulfill()
        
        #expect(service.setAIConsentGrantedReceivedGranted == true)
    }
    
    /// Walk F3: the onboarding tapped Allow again while the next screen was
    /// still coming in; each tap saved again and moved the flow on again.
    @Test
    func anAnswerIsRecordedOnceHoweverOftenItIsTapped() async throws {
        let service = AgentPlatformServiceMock()
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        let viewModel = AIConsentPromptScreenViewModel(agentPlatformService: service, privacyURL: "https://spiral.md/brand/privacy")
        
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
        let viewModel = AIConsentPromptScreenViewModel(agentPlatformService: service, privacyURL: "https://spiral.md/brand/privacy")
        
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
        let viewModel = AIConsentPromptScreenViewModel(agentPlatformService: service, privacyURL: "https://spiral.md/brand/privacy")
        
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
    
    private func makeOnboarding(consent: AIConsent, isNewLogin: Bool = false) -> (OnboardingFlowCoordinator, NavigationStackCoordinator) {
        let appSettings = AppSettings.volatile()
        appSettings.hasRunIdentityConfirmationOnboarding = true
        appSettings.hasRunNotificationPermissionsOnboarding = true
        
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(consent)
        let userSession = UserSessionMock(.init())
        userSession.agentPlatformService = service
        
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(appSettings: appSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  appSettings: appSettings,
                                                  appHooks: AppHooks(),
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  notificationManager: NotificationManagerMock(),
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
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentGranted)) { $0 == true }
        try await deferred.fulfill()
    }
    
    @Test
    func withdrawingThatFailsToSaveFlipsTheToggleBack() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentGranted)) { $0 == true }
        try await loaded.fulfill()
        
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.isWaitingAIConsent)) { !$0 }
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await settled.fulfill()
        
        #expect(service.setAIConsentGrantedReceivedGranted == false)
        #expect(viewModel.context.viewState.aiConsentGranted == true)
    }
    
    @Test
    func withdrawingRecordsTheDecline() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(.init(isGranted: true, currentVersion: current, decidedVersion: current))
        service.setAIConsentGrantedReturnValue = .success(.init(isGranted: false, currentVersion: current, decidedVersion: current))
        let viewModel = makeAdvancedSettings(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentGranted)) { $0 == true }
        try await loaded.fulfill()
        
        let withdrawn = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentGranted)) { $0 == false }
        viewModel.context.send(viewAction: .updateAIConsent(false))
        try await withdrawn.fulfill()
    }
    
    // Decision 150: «Open Settings» lands here, so a failed read must not hide the choice.
    @Test
    func aFailedReadOffersARetryThatLoadsTheToggle() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeAdvancedSettings(service: service)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentLoadFailed)) { $0 }
        try await failed.fulfill()
        #expect(viewModel.context.viewState.aiConsentGranted == nil)
        
        service.fetchAIConsentReturnValue = .success(.init(isGranted: false, currentVersion: current, decidedVersion: current))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.aiConsentGranted)) { $0 == false }
        viewModel.context.send(viewAction: .retryAIConsent)
        try await loaded.fulfill()
        #expect(!viewModel.context.viewState.aiConsentLoadFailed)
        #expect(service.fetchAIConsentCallsCount == 2)
    }
    
    @Test
    func advancedSettingsWithoutThePlatformHasNoToggle() async throws {
        let viewModel = makeAdvancedSettings(service: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.context.viewState.aiConsentGranted == nil)
    }
    
    private func makeAdvancedSettings(service: AgentPlatformServiceMock?) -> AdvancedSettingsScreenViewModel {
        AdvancedSettingsScreenViewModel(advancedSettings: AppSettings.volatile(),
                                        clientProxy: ClientProxyMock(.init()),
                                        userIndicatorController: UserIndicatorControllerMock(),
                                        agentPlatformService: service)
    }
}
