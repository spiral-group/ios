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
    
    private func makeOnboarding(consent: AIConsent, isNewLogin: Bool = false) -> (OnboardingFlowCoordinator, NavigationStackCoordinator) {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = .success(consent)
        return makeOnboarding(store: AgentsStore(service: service, retryDelays: []), isNewLogin: isNewLogin)
    }
    
    private func makeOnboarding(store: AgentsStore, isNewLogin: Bool = false) -> (OnboardingFlowCoordinator, NavigationStackCoordinator) {
        let userSettings = UserSettings.mock()
        userSettings.account.hasRunIdentityConfirmationOnboarding = true
        userSettings.app.hasRunNotificationPermissionsOnboarding = true
        
        let userSession = UserSessionMock(.init(userSettings: userSettings))
        userSession.agentsStore = store
        
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock(),
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
