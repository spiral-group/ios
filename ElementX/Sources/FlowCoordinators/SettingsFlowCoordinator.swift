//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

enum SettingsFlowCoordinatorAction {
    // AGENT-PLATFORM (Brief 0073): someone who joined by invitation was
    // tapped — the session flow opens their profile on the Chats tab.
    case openUserProfile(userID: String)
    case clearCache
    case runLogoutFlow
    /// Logout without a confirmation. The user forgot their PIN.
    case forceLogout
}

class SettingsFlowCoordinator: FlowCoordinatorProtocol {
    private let appLockService: AppLockServiceProtocol
    private let isInSecondaryWindow: Bool
    private let navigationStackCoordinator: NavigationStackCoordinator
    private let flowParameters: CommonFlowParameters
    
    private var userSettings: UserSettings {
        flowParameters.userSession.userSettings
    }
    
    // periphery:ignore - retaining purpose
    private var appLockSetupFlowCoordinator: AppLockSetupFlowCoordinator?
    private var bugReportFlowCoordinator: BugReportFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var encryptionSettingsFlowCoordinator: EncryptionSettingsFlowCoordinator?
    // periphery:ignore - retaining purpose
    private var linkNewDeviceFlowCoordinator: LinkNewDeviceFlowCoordinator?
    
    private var cancellables = Set<AnyCancellable>()
    
    private let actionsSubject: PassthroughSubject<SettingsFlowCoordinatorAction, Never> = .init()
    var actions: AnyPublisher<SettingsFlowCoordinatorAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(appLockService: AppLockServiceProtocol,
         isInSecondaryWindow: Bool,
         navigationStackCoordinator: NavigationStackCoordinator,
         flowParameters: CommonFlowParameters) {
        self.appLockService = appLockService
        self.isInSecondaryWindow = isInSecondaryWindow
        self.navigationStackCoordinator = navigationStackCoordinator
        self.flowParameters = flowParameters
    }
    
    func start(animated: Bool) {
        fatalError("Unavailable")
    }
    
    func handleAppRoute(_ appRoute: AppRoute, animated: Bool) {
        MXLog.info("Handling app route: \(appRoute)")
        
        switch appRoute {
        case .settings:
            presentSettingsScreen(animated: animated)
        case .chatBackupSettings:
            startEncryptionSettingsFlow()
        case .aiConsentSettings: // AGENT-PLATFORM (decisions 150, 187): the toggle is the first row of Privacy.
            presentModerationAndSafetySettings()
        default:
            break
        }
    }
    
    func clearRoute(animated: Bool) {
        fatalError("Unavailable")
    }
    
    // MARK: - Private
    
    private func presentSettingsScreen(animated: Bool) {
        let settingsScreenCoordinator = SettingsScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                                    isBugReportServiceEnabled: flowParameters.bugReportService.isEnabled,
                                                                                    isInSecondaryWindow: isInSecondaryWindow,
                                                                                    userIndicatorController: flowParameters.userIndicatorController))
        
        settingsScreenCoordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .userDetails:
                    presentUserDetailsEditScreen()
                case let .userStatusEmojiPicker(continuation):
                    presentEmojiPicker(emojiPickerContinuation: continuation)
                case .invitePeople: // AGENT-PLATFORM (Brief 0073).
                    presentInvitePeopleScreen()
                case .security: // AGENT-PLATFORM (decision 187).
                    presentSecuritySettings()
                case .privacy: // AGENT-PLATFORM (decision 187): upstream's Moderation and safety plus AI consent.
                    presentModerationAndSafetySettings()
                case .notifications:
                    presentNotificationSettings()
                case .yourData: // AGENT-PLATFORM (Brief 0078).
                    presentYourDataScreen()
                case .appearanceAndMedia: // AGENT-PLATFORM (decision 187).
                    presentAppearanceAndMediaSettings()
                case .analytics:
                    presentAnalyticsScreen()
                case .bugReport:
                    bugReportFlowCoordinator = BugReportFlowCoordinator(parameters: .init(presentationMode: .push(navigationStackCoordinator),
                                                                                          userIndicatorController: flowParameters.userIndicatorController,
                                                                                          bugReportService: flowParameters.bugReportService,
                                                                                          userSession: flowParameters.userSession))
                    bugReportFlowCoordinator?.start()
                case .about:
                    presentLegalInformationScreen()
                case .labs:
                    presentLabs()
                case .developerOptions:
                    presentDeveloperOptions()
                case .logout:
                    actionsSubject.send(.runLogoutFlow)
                case .deactivateAccount:
                    presentDeactivateAccount()
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.setRootCoordinator(settingsScreenCoordinator, animated: animated)
    }
    
    // AGENT-PLATFORM (decision 188): no row opens Labs; kept for upstream syncs.
    private func presentLabs() {
        let coordinator = LabsScreenCoordinator(parameters: .init(userSettings: userSettings))
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .clearCache:
                    self?.actionsSubject.send(.clearCache)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    private func startEncryptionSettingsFlow() {
        let coordinator = EncryptionSettingsFlowCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                              userIndicatorController: flowParameters.userIndicatorController,
                                                                              navigationStackCoordinator: navigationStackCoordinator))
        coordinator.actionsPublisher.sink { [weak self] action in
            switch action {
            case .complete:
                // The flow coordinator tidies up the stack, no need to do anything.
                self?.encryptionSettingsFlowCoordinator = nil
            }
        }
        .store(in: &cancellables)
        
        encryptionSettingsFlowCoordinator = coordinator
        coordinator.start()
    }
    
    private func presentEmojiPicker(emojiPickerContinuation: EmojiPickerScreenContinuation) {
        let coordinator = EmojiPickerScreenCoordinator(parameters: .init(mode: .userStatus,
                                                                         selectedEmojis: [],
                                                                         emojiProvider: flowParameters.emojiProvider,
                                                                         continuation: emojiPickerContinuation))
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .dismiss:
                    self?.navigationStackCoordinator.setSheetCoordinator(nil)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.setSheetCoordinator(coordinator)
    }
    
    private func presentUserDetailsEditScreen() {
        let coordinator = UserDetailsEditScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                             mediaUploadingPreprocessor: MediaUploadingPreprocessor(userSettings: userSettings),
                                                                             navigationStackCoordinator: navigationStackCoordinator,
                                                                             appMediator: flowParameters.appMediator,
                                                                             userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actions
            .sink { [weak self] action in
                switch action {
                case .dismiss:
                    self?.navigationStackCoordinator.pop()
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    private func startLinkNewDeviceFlow() {
        let stackCoordinator = NavigationStackCoordinator()
        let flowCoordinator = LinkNewDeviceFlowCoordinator(navigationStackCoordinator: stackCoordinator,
                                                           appLockService: appLockService,
                                                           flowParameters: flowParameters)
        flowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .dismiss:
                    navigationStackCoordinator.setSheetCoordinator(nil)
                case .requestOAuthAuthorisation(let url, let continuation):
                    presentAccountManagementURL(url, continuation: continuation)
                case .forceLogout:
                    actionsSubject.send(.forceLogout)
                }
            }
            .store(in: &cancellables)
        
        linkNewDeviceFlowCoordinator = flowCoordinator
        flowCoordinator.start()
        
        navigationStackCoordinator.setSheetCoordinator(stackCoordinator) { [weak self] in
            self?.linkNewDeviceFlowCoordinator = nil
        }
    }
    
    private func presentAnalyticsScreen() {
        let coordinator = AnalyticsSettingsScreenCoordinator(parameters: .init(userSettings: userSettings,
                                                                               analytics: flowParameters.analytics))
        navigationStackCoordinator.push(coordinator)
    }
    
    private func presentAppLockSetupFlow() {
        let coordinator = AppLockSetupFlowCoordinator(presentingFlow: .settings,
                                                      appLockService: appLockService,
                                                      navigationStackCoordinator: navigationStackCoordinator)
        coordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .complete:
                // The flow coordinator tidies up the stack, no need to do anything.
                appLockSetupFlowCoordinator = nil
            case .forceLogout:
                actionsSubject.send(.forceLogout)
            }
        }
        .store(in: &cancellables)
        
        appLockSetupFlowCoordinator = coordinator
        coordinator.start()
    }
    
    private func presentLegalInformationScreen() {
        navigationStackCoordinator.push(LegalInformationScreenCoordinator(userSettings: userSettings,
                                                                          appMediator: flowParameters.appMediator)) // AGENT-PLATFORM (Brief 0078)
    }
    
    // AGENT-PLATFORM (Brief 0073 / ADR-0008).
    private func presentInvitePeopleScreen() {
        let coordinator = InvitePeopleScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                          userIndicatorController: flowParameters.userIndicatorController))
        coordinator.actionsPublisher.sink { [weak self] action in
            switch action {
            case .openUser(let userID):
                self?.actionsSubject.send(.openUserProfile(userID: userID))
            }
        }
        .store(in: &cancellables)
        navigationStackCoordinator.push(coordinator)
    }
    
    // AGENT-PLATFORM (Brief 0075): a new account phrase from this device.
    // 1.0.3: an account made with Apple has none yet, so the same flow adds its first.
    private var newPhrasePresenter: NewPhrasePresenter?
    private func startNewPhrase(addsFirstPhrase: Bool) {
        // One sign-in flow at a time: a second tap while one runs starts nothing.
        guard newPhrasePresenter == nil, appleLinkPresenter == nil else { return }
        guard let service = flowParameters.userSession.agentPlatformService else {
            securitySettingsCoordinator?.signInFlowFinished()
            return
        }
        let presenter = NewPhrasePresenter(agentPlatformService: service,
                                           presentationAnchor: flowParameters.windowManager.mainWindow,
                                           addsFirstPhrase: addsFirstPhrase)
        newPhrasePresenter = presenter
        Task { [weak self] in
            let outcome = await presenter.start()
            guard let self else { return }
            newPhrasePresenter = nil
            // Every outcome reloads: a sheet closed after the page already saved still changed the account.
            securitySettingsCoordinator?.signInFlowFinished()
            switch outcome {
            case .changed:
                let title = addsFirstPhrase ? UntranslatedL10n.screenSettingsAddPhraseDone : UntranslatedL10n.screenSettingsNewPhraseDone
                flowParameters.userIndicatorController.submitIndicator(.init(title: title, icon: \.checkCircle))
            case .cancelled:
                break
            case .passcodeRequired:
                let title = addsFirstPhrase ? UntranslatedL10n.screenSettingsSignInPasscodeRequired : UntranslatedL10n.screenSettingsNewPhrasePasscodeRequired
                flowParameters.userIndicatorController.submitIndicator(.init(title: title))
            case .failed:
                let title = addsFirstPhrase ? UntranslatedL10n.screenSettingsAddPhraseFailed : UntranslatedL10n.screenSettingsNewPhraseFailed
                flowParameters.userIndicatorController.submitIndicator(.init(title: title))
            }
        }
    }
    
    // AGENT-PLATFORM (1.0.3, operator 2026-11-20): add Sign in with Apple to a phrase account.
    private var appleLinkPresenter: AppleLinkPresenter?
    private func startAppleLink() {
        guard newPhrasePresenter == nil, appleLinkPresenter == nil else { return }
        guard let service = flowParameters.userSession.agentPlatformService else {
            securitySettingsCoordinator?.signInFlowFinished()
            return
        }
        let presenter = AppleLinkPresenter(agentPlatformService: service,
                                           presentationAnchor: flowParameters.windowManager.mainWindow)
        appleLinkPresenter = presenter
        Task { [weak self] in
            let outcome = await presenter.start()
            guard let self else { return }
            appleLinkPresenter = nil
            securitySettingsCoordinator?.signInFlowFinished()
            switch outcome {
            case .linked:
                flowParameters.userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenSettingsAppleLinked,
                                                                             icon: \.checkCircle))
            case .taken:
                flowParameters.userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenSettingsAppleTaken))
            case .cancelled:
                break
            case .passcodeRequired:
                flowParameters.userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenSettingsSignInPasscodeRequired))
            case .failed:
                flowParameters.userIndicatorController.submitIndicator(.init(title: UntranslatedL10n.screenSettingsAppleFailed))
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0078): the account export and one call's export.
    private func presentYourDataScreen() {
        guard let service = flowParameters.userSession.agentPlatformService else { return }
        let coordinator = YourDataScreenCoordinator(parameters: .init(agentPlatformService: service,
                                                                      clientProxy: flowParameters.userSession.clientProxy,
                                                                      userIndicatorController: flowParameters.userIndicatorController))
        navigationStackCoordinator.push(coordinator)
    }
    
    private func presentBlockedUsersScreen() {
        let coordinator = BlockedUsersScreenCoordinator(parameters: .init(hideProfiles: userSettings.app.hideIgnoredUserProfiles,
                                                                          userSession: flowParameters.userSession,
                                                                          userIndicatorController: flowParameters.userIndicatorController))
        navigationStackCoordinator.push(coordinator)
    }
    
    private func presentNotificationSettings() {
        let notificationParameters = NotificationSettingsScreenCoordinatorParameters(navigationStackCoordinator: navigationStackCoordinator,
                                                                                     userSession: flowParameters.userSession,
                                                                                     userNotificationCenter: UNUserNotificationCenter.current(),
                                                                                     userIndicatorController: flowParameters.userIndicatorController,
                                                                                     isModallyPresented: false)
        let coordinator = NotificationSettingsScreenCoordinator(parameters: notificationParameters)
        navigationStackCoordinator.push(coordinator)
    }
    
    // AGENT-PLATFORM (decision 187): «Privacy» is upstream's Moderation and
    // safety screen plus the AI consent row.
    private func presentModerationAndSafetySettings() {
        let parameters = ModerationAndSafetySettingsScreenCoordinatorParameters(userSession: flowParameters.userSession,
                                                                                userIndicatorController: flowParameters.userIndicatorController)
        let coordinator = ModerationAndSafetySettingsScreenCoordinator(parameters: parameters)
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .blockedUsers:
                    presentBlockedUsersScreen()
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    // AGENT-PLATFORM (decision 187): the Security hub; each row opens a presenter of this flow.
    /// Held weakly: the navigation stack owns it, and a sign-in method added from it reloads its rows.
    private weak var securitySettingsCoordinator: SecuritySettingsScreenCoordinator?
    private func presentSecuritySettings() {
        let coordinator = SecuritySettingsScreenCoordinator(parameters: .init(userSession: flowParameters.userSession,
                                                                              appSettings: flowParameters.userSession.userSettings.app))
        securitySettingsCoordinator = coordinator
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .newPhrase(let addsFirstPhrase):
                    startNewPhrase(addsFirstPhrase: addsFirstPhrase)
                case .addApple:
                    startAppleLink()
                case .manageAccount(let url):
                    presentAccountManagementURL(url)
                case .linkNewDevice:
                    startLinkNewDeviceFlow()
                case .secureBackup:
                    startEncryptionSettingsFlow()
                case .appLock:
                    presentAppLockSetupFlow()
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    // AGENT-PLATFORM (decision 187): upstream's inline Appearance picker and MediaUploadQualitySettingsScreen, as one screen.
    private func presentAppearanceAndMediaSettings() {
        let coordinator = AppearanceAndMediaSettingsScreenCoordinator(parameters: .init(appSettings: flowParameters.userSession.userSettings.app,
                                                                                        analytics: flowParameters.analytics))
        navigationStackCoordinator.push(coordinator)
    }
    
    private func presentDeveloperOptions() {
        let coordinator = DeveloperOptionsScreenCoordinator(appSettings: userSettings.app,
                                                            screenHook: flowParameters.userSession.userHooks.developerOptionsScreenHook,
                                                            clientProxy: flowParameters.userSession.clientProxy)
        
        coordinator.actions
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .clearCache:
                    actionsSubject.send(.clearCache)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    private func presentDeactivateAccount() {
        let parameters = DeactivateAccountScreenCoordinatorParameters(clientProxy: flowParameters.userSession.clientProxy,
                                                                      userIndicatorController: flowParameters.userIndicatorController,
                                                                      // AGENT-PLATFORM (Brief 0078)
                                                                      spiralDeletion: flowParameters.userSession.agentPlatformService.map { SpiralAccountDeletion(agentPlatformService: $0) })
        let coordinator = DeactivateAccountScreenCoordinator(parameters: parameters)
        
        coordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .accountDeactivated:
                    actionsSubject.send(.forceLogout)
                }
            }
            .store(in: &cancellables)
        
        navigationStackCoordinator.push(coordinator)
    }
    
    // MARK: OAuth Account Management
    
    private var accountSettingsPresenter: OAuthAccountSettingsPresenter?
    private func presentAccountManagementURL(_ url: URL, continuation: OAuthAccountSettingsPresenter.Continuation? = nil) {
        // Note to anyone in the future if you come back here to make this open in Safari instead of a WAS.
        // As of iOS 16, there is an issue on the simulator with accessing the cookie but it works on a device. 🤷‍♂️
        accountSettingsPresenter = OAuthAccountSettingsPresenter(accountURL: url,
                                                                 presentationAnchor: flowParameters.windowManager.mainWindow,
                                                                 appMediator: flowParameters.appMediator,
                                                                 userSession: flowParameters.userSession,
                                                                 continuation: continuation)
        accountSettingsPresenter?.start()
    }
}
