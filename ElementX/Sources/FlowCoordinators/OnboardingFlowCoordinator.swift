//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
import SwiftState

enum OnboardingFlowCoordinatorAction {
    case requestPresentation(animated: Bool)
    case dismiss
    case logoutConfirmed
}

class OnboardingFlowCoordinator: FlowCoordinatorProtocol {
    private let userSession: UserSessionProtocol
    private let appLockService: AppLockServiceProtocol
    private let analyticsService: AnalyticsServiceProtocol
    private let appMediator: AppMediatorProtocol
    private let appSettings: AppSettings
    private let appHooks: AppHooks
    private let notificationManager: NotificationManagerProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let windowManager: WindowManagerProtocol
    private var isNewLogin: Bool
    // AGENT-PLATFORM (Brief 0078 phase 2): known only after `refreshAIConsent()`.
    private var aiConsentRequirement = AIConsentRequirement.unknown
    private enum AIConsentRequirement { case unknown, required, notRequired }
    
    private var navigationStackCoordinator: NavigationStackCoordinator!
    
    enum State: StateType {
        case initial
        case identityConfirmation
        case identityConfirmed
        case appLockSetup
        case analyticsPrompt
        // AGENT-PLATFORM (Brief 0078 phase 2): consent to third-party AI.
        case aiConsentPrompt
        // AGENT-PLATFORM (walk F3): the flow can't finish before it knows whether to ask.
        case awaitingAIConsent
        case notificationPermissions
        case finished
    }
    
    enum Event: EventType {
        case next
        case nextSkippingIdentityConfirmed
        case aiConsentKnown // AGENT-PLATFORM (walk F3)
    }
    
    private let stateMachine: StateMachine<State, Event>
    private var cancellables = Set<AnyCancellable>()
    
    // periphery: ignore - used to store the coordinator to avoid deallocation
    private var appLockFlowCoordinator: AppLockSetupFlowCoordinator?
    // periphery: ignore - used to store the coordinator to avoid deallocation
    private var encryptionResetFlowCoordinator: EncryptionResetFlowCoordinator?
    
    private let actionsSubject: PassthroughSubject<OnboardingFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<OnboardingFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    private var verificationStateCancellable: AnyCancellable?
    
    init(isNewLogin: Bool,
         appLockService: AppLockServiceProtocol,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.isNewLogin = isNewLogin
        userSession = flowParameters.userSession
        self.appLockService = appLockService
        analyticsService = flowParameters.analytics
        appMediator = flowParameters.appMediator
        appSettings = flowParameters.appSettings
        appHooks = flowParameters.appHooks
        notificationManager = flowParameters.notificationManager
        userIndicatorController = flowParameters.userIndicatorController
        windowManager = flowParameters.windowManager
        
        self.navigationStackCoordinator = navigationStackCoordinator
        
        stateMachine = .init(state: .initial)
        
        configureStateMachine()
        
        // Verification can change as part of the onboarding flow by verifying with
        // another device, using a recovery key or by resetting one's crypto identity.
        // It can also happen that onboarding started before it had a chance to update,
        // usually seen when registering a new account.
        // Handle all those cases here instead of spreading them throughout the code.
        verificationStateCancellable = userSession.sessionSecurityStatePublisher
            .map(\.verificationState)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self,
                      value == .verified,
                      stateMachine.state == .identityConfirmation else { return }
                
                appSettings.hasRunIdentityConfirmationOnboarding = true
                stateMachine.tryEvent(.nextSkippingIdentityConfirmed)
            }
    }
    
    var shouldStart: Bool {
        guard stateMachine.state == .initial, !ProcessInfo.isRunningIntegrationTests else {
            return false
        }
        
        return isNewLogin || requiresVerification || requiresAppLockSetup || requiresAnalyticsSetup || requiresNotificationsSetup || aiConsentRequirement == .required // AGENT-PLATFORM
    }
    
    /// AGENT-PLATFORM (Brief 0073, G05): no flow is on screen and the AI consent
    /// answer is in with nothing to ask. A cover meant for after onboarding (the
    /// invite welcome) waits for this: the consent read is what can start the flow
    /// after the session is up. The other steps start with the session, and a
    /// session left unverified (identity confirmation skipped) is settled too.
    var isSettled: Bool {
        guard stateMachine.state == .initial || stateMachine.state == .finished else { return false }
        return ProcessInfo.isRunningIntegrationTests || aiConsentRequirement == .notRequired
    }
    
    func start(animated: Bool) {
        guard shouldStart else {
            fatalError("This flow coordinator shouldn't have been started")
        }
        
        actionsSubject.send(.requestPresentation(animated: !isNewLogin))
        
        stateMachine.tryEvent(.next)
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        fatalError()
    }
    
    func clearRoute(animated: Bool) {
        fatalError()
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2): the server holds the decision, so
    // whether to ask is only known after a fetch; the caller then re-attempts
    // onboarding. A failed fetch asks nothing — without a grant the server
    // keeps everything from AI anyway.
    func refreshAIConsent() async {
        guard let agentPlatformService = userSession.agentPlatformService else {
            setAIConsentRequirement(.notRequired)
            return
        }
        switch await agentPlatformService.fetchAIConsent() {
        case .success(let consent):
            setAIConsentRequirement(consent.needsDecision ? .required : .notRequired)
        case .failure(let error):
            MXLog.error("Fetching the AI consent failed: \(error)")
            setAIConsentRequirement(.notRequired)
        }
    }
    
    // AGENT-PLATFORM (walk F3): finishing before the answer and starting again
    // after it dismissed the cover and presented it again within one dismissal
    // animation, which left a dead prompt on screen. A flow that got this far
    // waits for the answer instead.
    private func setAIConsentRequirement(_ requirement: AIConsentRequirement) {
        aiConsentRequirement = requirement
        if stateMachine.state == .awaitingAIConsent {
            stateMachine.tryEvent(.aiConsentKnown)
        }
    }
    
    // MARK: - Private
    
    private var requiresVerification: Bool {
        // We want to make sure onboarding finishes but also every time the user becomes unverified (e.g. account reset)
        !appSettings.hasRunIdentityConfirmationOnboarding || userSession.sessionSecurityStatePublisher.value.verificationState == .unverified
    }
    
    private var requiresAppLockSetup: Bool {
        appSettings.appLockIsMandatory && !appLockService.isEnabled
    }
    
    private var requiresAnalyticsSetup: Bool {
        analyticsService.shouldShowAnalyticsPrompt
    }
    
    private var requiresNotificationsSetup: Bool {
        !appSettings.hasRunNotificationPermissionsOnboarding
    }
    
    private func configureStateMachine() {
        stateMachine.addRoute(.init(fromState: .finished, toState: .initial))
        stateMachine.addRouteMapping { [weak self] event, fromState, _ in
            guard let self else {
                return nil
            }
            
            // AGENT-PLATFORM (Brief 0078 phase 2): the AI consent step goes in
            // before the first step past identity and app lock; after it the
            // flow carries on as it would after app lock.
            let isPastAIConsent = fromState == .aiConsentPrompt || fromState == .awaitingAIConsent
            if fromState == .awaitingAIConsent {
                guard event == .aiConsentKnown else { return nil }
                if aiConsentRequirement == .required { return .aiConsentPrompt }
            }
            let next = upstreamNextState(event: event, fromState: isPastAIConsent ? .appLockSetup : fromState)
            guard !isPastAIConsent, let next, [.analyticsPrompt, .notificationPermissions, .finished].contains(next) else {
                return next
            }
            switch aiConsentRequirement {
            case .required: return .aiConsentPrompt
            case .unknown: return .awaitingAIConsent // AGENT-PLATFORM (walk F3)
            case .notRequired: return next
            }
        }
        
        stateMachine.addAnyHandler(.any => .any) { [weak self] context in
            guard let self else { return }
            
            switch (context.fromState, context.event, context.toState) {
            case (_, _, .identityConfirmation):
                presentIdentityConfirmationScreen()
            case (_, _, .identityConfirmed):
                presentIdentityConfirmedScreen()
            case (_, _, .appLockSetup):
                presentAppLockSetupFlow()
            case (_, _, .analyticsPrompt):
                presentAnalyticsPromptScreen()
            case (_, _, .aiConsentPrompt): // AGENT-PLATFORM (Brief 0078 phase 2)
                presentAIConsentPromptScreen()
            case (_, _, .awaitingAIConsent): // AGENT-PLATFORM (walk F3)
                presentAIConsentWait()
            case (_, _, .notificationPermissions):
                presentNotificationPermissionsScreen()
            case (_, _, .finished):
                isNewLogin = false
                appSettings.hasSignedInBefore = true
                actionsSubject.send(.dismiss)
                stateMachine.tryState(.initial)
            case (.finished, _, .initial):
                break
            default:
                fatalError("Unknown transition: \(context)")
            }
            
            if let event = context.event {
                MXLog.info("Transitioning from `\(context.fromState)` to `\(context.toState)` with event `\(event)`")
            } else {
                MXLog.info("Transitioning from \(context.fromState)` to `\(context.toState)`")
            }
        }
        
        stateMachine.addErrorHandler { context in
            fatalError("Unexpected transition: \(context)")
        }
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2): upstream's route mapping, moved out
    // unchanged so the AI consent step can wrap it.
    private func upstreamNextState(event: Event?, fromState: State) -> State? {
        switch (fromState, requiresVerification, requiresAppLockSetup, requiresAnalyticsSetup, requiresNotificationsSetup) {
        case (.initial, true, _, _, _):
            return .identityConfirmation
        case (.initial, false, true, _, _):
            return .appLockSetup
        case (.initial, false, false, true, _):
            return .analyticsPrompt
        case (.initial, false, false, false, true):
            return .notificationPermissions
        case (.initial, false, false, false, false):
            return .finished
            
        case (.identityConfirmation, _, _, _, _):
            if event == .nextSkippingIdentityConfirmed {
                // Used when the verification state has updated to verified
                // after starting the onboarding flow
                switch (requiresAppLockSetup, requiresAnalyticsSetup, requiresNotificationsSetup) {
                case (true, _, _):
                    return .appLockSetup
                case (false, true, _):
                    return .analyticsPrompt
                case (false, false, true):
                    return .notificationPermissions
                case (false, false, false):
                    return .finished
                }
            } else {
                return .identityConfirmed
            }
        case (.identityConfirmed, _, true, _, _):
            return .appLockSetup
        case (.identityConfirmed, _, false, true, _):
            return .analyticsPrompt
        case (.identityConfirmed, _, false, false, true):
            return .notificationPermissions
        case (.identityConfirmed, _, false, false, false):
            return .finished
            
        case (.appLockSetup, _, _, true, _):
            return .analyticsPrompt
        case (.appLockSetup, _, _, false, true):
            return .notificationPermissions
        case (.appLockSetup, _, _, false, false):
            return .finished
            
        case (.analyticsPrompt, _, _, _, true):
            return .notificationPermissions
        case (.analyticsPrompt, _, _, _, false):
            return .finished
            
        case (.notificationPermissions, _, _, _, _):
            return .finished
            
        default:
            return nil
        }
    }
    
    private func presentIdentityConfirmationScreen() {
        let parameters = IdentityConfirmationScreenCoordinatorParameters(userSession: userSession,
                                                                         appSettings: appSettings,
                                                                         userIndicatorController: userIndicatorController)
        
        let coordinator = IdentityConfirmationScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            
            switch action {
            case .otherDevice:
                presentSessionVerificationScreen()
            case .recoveryKey:
                presentRecoveryKeyScreen()
            case .skip:
                appSettings.hasRunIdentityConfirmationOnboarding = true
                stateMachine.tryEvent(.nextSkippingIdentityConfirmed)
            case .reset:
                startEncryptionResetFlow()
            case .logoutConfirmed:
                actionsSubject.send(.logoutConfirmed)
            }
        }
        .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    private func presentSessionVerificationScreen() {
        guard let sessionVerificationController = userSession.clientProxy.sessionVerificationController else {
            fatalError("The sessionVerificationController should aways be valid at this point")
        }
        
        let parameters = SessionVerificationScreenCoordinatorParameters(sessionVerificationControllerProxy: sessionVerificationController,
                                                                        flow: .deviceInitiator,
                                                                        appSettings: appSettings,
                                                                        mediaProvider: userSession.mediaProvider)
        
        let coordinator = SessionVerificationScreenCoordinator(parameters: parameters)
        
        coordinator.actions
            .sink { action in
                switch action {
                case .done:
                    break // Moving to next state is handled by the global session verification listener
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    private func presentRecoveryKeyScreen() {
        let parameters = SecureBackupRecoveryKeyScreenCoordinatorParameters(secureBackupController: userSession.clientProxy.secureBackupController,
                                                                            userIndicatorController: userIndicatorController,
                                                                            isModallyPresented: false)
        
        let coordinator = appHooks.recoveryKeyScreenHook.makeCoordinator(parameters: parameters,
                                                                         homeserver: userSession.clientProxy.homeserver)
        
        coordinator.actions
            .sink { action in
                switch action {
                case .complete:
                    break // Moving to next state is Handled by the global session verification listener
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    private func startEncryptionResetFlow() {
        let resetNavigationStackCoordinator = NavigationStackCoordinator()
        let coordinator = EncryptionResetFlowCoordinator(parameters: .init(userSession: userSession,
                                                                           appMediator: appMediator,
                                                                           appSettings: appSettings,
                                                                           appHooks: appHooks,
                                                                           userIndicatorController: userIndicatorController,
                                                                           navigationStackCoordinator: resetNavigationStackCoordinator,
                                                                           windowManger: windowManager))
        
        coordinator.actionsPublisher.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .resetComplete:
                // Moving to next state is handled by the global session verification listener
                navigationStackCoordinator.setSheetCoordinator(nil)
            case .cancel:
                navigationStackCoordinator.setSheetCoordinator(nil)
            }
        }
        .store(in: &cancellables)
        
        encryptionResetFlowCoordinator = coordinator
        coordinator.start()
        
        navigationStackCoordinator.setSheetCoordinator(resetNavigationStackCoordinator) { [weak self] in
            self?.encryptionResetFlowCoordinator = nil
        }
    }
    
    private func presentIdentityConfirmedScreen() {
        let coordinator = IdentityConfirmedScreenCoordinator()
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .done:
                    stateMachine.tryEvent(.next)
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    private func presentAppLockSetupFlow() {
        let coordinator = AppLockSetupFlowCoordinator(presentingFlow: .onboarding,
                                                      appLockService: appLockService,
                                                      navigationStackCoordinator: navigationStackCoordinator)
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                appLockFlowCoordinator = nil
                stateMachine.tryEvent(.next)
            case .forceLogout:
                fatalError("The PIN creation flow should not fail.")
            }
        }
        .store(in: &cancellables)
        
        appLockFlowCoordinator = coordinator
        coordinator.start()
    }
    
    private func presentAnalyticsPromptScreen() {
        let coordinator = AnalyticsPromptScreenCoordinator(analytics: analyticsService, termsURL: appSettings.analyticsTermsURL)
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .done:
                    stateMachine.tryEvent(.next)
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2)
    private func presentAIConsentPromptScreen() {
        guard let agentPlatformService = userSession.agentPlatformService else {
            aiConsentRequirement = .notRequired
            stateMachine.tryEvent(.next)
            return
        }
        
        let coordinator = AIConsentPromptScreenCoordinator(parameters: .init(agentPlatformService: agentPlatformService,
                                                                             privacyURL: appSettings.privacyURL))
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .done:
                    aiConsentRequirement = .notRequired
                    stateMachine.tryEvent(.next)
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    // AGENT-PLATFORM (walk F3): the logo replaces the last step's screen, so a
    // tap on it can't move a flow that is waiting.
    private func presentAIConsentWait() {
        navigationStackCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: false))
    }
    
    private func presentNotificationPermissionsScreen() {
        let coordinator = NotificationPermissionsScreenCoordinator(parameters: .init(notificationManager: notificationManager))
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                switch action {
                case .done:
                    appSettings.hasRunNotificationPermissionsOnboarding = true
                    stateMachine.tryEvent(.next)
                }
            }
            .store(in: &cancellables)
        
        presentCoordinator(coordinator)
    }
    
    private func presentCoordinator(_ coordinator: CoordinatorProtocol, dismissalCallback: (() -> Void)? = nil) {
        if navigationStackCoordinator.rootCoordinator == nil {
            navigationStackCoordinator.setRootCoordinator(coordinator, dismissalCallback: dismissalCallback)
        } else {
            navigationStackCoordinator.push(coordinator, dismissalCallback: dismissalCallback)
        }
    }
}
