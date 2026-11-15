//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias SettingsScreenViewModelType = StateStoreViewModelV2<SettingsScreenViewState, SettingsScreenViewAction>

class SettingsScreenViewModel: SettingsScreenViewModelType, SettingsScreenViewModelProtocol {
    private let userSettings: UserSettings
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM (Brief 0078): App Review 2.3.1 — no hidden features in a Release build.
    /// Whether Developer options may appear at all: Debug and Nightly builds only.
    private let allowsDeveloperOptions: Bool
    
    private var actionsSubject: PassthroughSubject<SettingsScreenViewModelAction, Never> = .init()
    
    var actions: AnyPublisher<SettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userSession: UserSessionProtocol,
         isBugReportServiceEnabled: Bool,
         isInSecondaryWindow: Bool,
         userIndicatorController: UserIndicatorControllerProtocol,
         allowsDeveloperOptions: Bool = AppSettings.appBuildType != .release) { // AGENT-PLATFORM (Brief 0078)
        userSettings = userSession.userSettings
        clientProxy = userSession.clientProxy
        self.userIndicatorController = userIndicatorController
        self.allowsDeveloperOptions = allowsDeveloperOptions
        
        super.init(initialViewState: .init(deviceID: userSession.clientProxy.deviceID,
                                           userProfile: userSession.clientProxy.userProfilePublisher.value,
                                           // AGENT-PLATFORM (Brief 0078): a Spiral account is deleted through the platform.
                                           showAccountDeactivation: userSession.clientProxy.canDeactivateAccount || userSession.agentPlatformService != nil,
                                           showYourData: userSession.agentPlatformService != nil, // AGENT-PLATFORM (Brief 0078)
                                           showDeveloperOptions: allowsDeveloperOptions && userSettings.app.developerOptionsEnabled, // AGENT-PLATFORM (Brief 0078)
                                           showAnalyticsSettings: userSettings.app.canPromptForAnalytics,
                                           isBugReportServiceEnabled: isBugReportServiceEnabled,
                                           navigationBarVisibility: isInSecondaryWindow ? .hidden : .automatic,
                                           bindings: .init(userSettings: userSettings)),
                   mediaProvider: userSession.mediaProvider)
        
        userSettings.app.developerOptionsEnabledPublisher
            .map { allowsDeveloperOptions && $0 } // AGENT-PLATFORM (Brief 0078): a stored `true` from an older build stays hidden.
            .weakAssign(to: \.state.showDeveloperOptions, on: self)
            .store(in: &cancellables)
        
        userSession.clientProxy.userProfilePublisher
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.userProfile, on: self)
            .store(in: &cancellables)
        
        // AGENT-PLATFORM (decision 187): Encryption lives in the Security hub;
        // its badge stays visible here, on the hub's row.
        userSession.sessionSecurityStatePublisher
            .receive(on: DispatchQueue.main)
            .map(\.needsRecoverySetup)
            .weakAssign(to: \.state.showSecuritySectionBadge, on: self)
            .store(in: &cancellables)
        
        Task {
            if case .success(true) = await userSession.clientProxy.isUserStatusSupported() {
                state.showUserStatusInput = true
            }
            await userSession.clientProxy.loadUserProfileIfNeeded()
        }
    }
    
    override func process(viewAction: SettingsScreenViewAction) {
        switch viewAction {
            
        case .userDetails:
            actionsSubject.send(.userDetails)
        case .userStatus(.pickStatus):
            state.bindings.isPresentingStatusPicker = true
        case .userStatus(.customStatus):
            state.bindings.isPresentingStatusPicker = false
            state.bindings.isShowingCustomStatusField = true
        case .userStatus(.pickCustomEmoji):
            pickCustomEmoji()
        case .userStatus(.set(let status)):
            Task { await setUserStatus(status) }
        case .userStatus(.clear):
            Task { await clearUserStatus() }
        case .userStatus(.cancel):
            state.bindings.isPresentingStatusPicker = false
            state.bindings.isShowingCustomStatusField = false
        case .invitePeople: // AGENT-PLATFORM (Brief 0073).
            actionsSubject.send(.invitePeople)
        case .security: // AGENT-PLATFORM (decision 187).
            actionsSubject.send(.security)
        case .privacy: // AGENT-PLATFORM (decision 187).
            actionsSubject.send(.privacy)
        case .notifications:
            actionsSubject.send(.notifications)
        case .yourData: // AGENT-PLATFORM (Brief 0078).
            actionsSubject.send(.yourData)
        case .appearanceAndMedia: // AGENT-PLATFORM (decision 187).
            actionsSubject.send(.appearanceAndMedia)
        case .analytics:
            actionsSubject.send(.analytics)
        case .reportBug:
            actionsSubject.send(.reportBug)
        case .about:
            actionsSubject.send(.about)
        case .labs:
            actionsSubject.send(.labs)
        case .logout:
            actionsSubject.send(.logout)
        case .enableDeveloperOptions:
            guard allowsDeveloperOptions else { return } // AGENT-PLATFORM (Brief 0078): seven taps do nothing in Release.
            userSettings.app.developerOptionsEnabled.toggle()
        case .developerOptions:
            actionsSubject.send(.developerOptions)
        case .deactivateAccount:
            actionsSubject.send(.deactivateAccount)
        }
    }
    
    // MARK: - Private
    
    private var pickCustomEmojiCancellable: AnyCancellable?
    private func pickCustomEmoji() {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        actionsSubject.send(.userStatusEmojiPicker(continuation))
        
        pickCustomEmojiCancellable = Task { [weak self] in
            for await emoji in stream {
                self?.state.bindings.customStatusEmoji = Character(emoji)
            }
        }
        .asCancellable()
    }
    
    private func setUserStatus(_ status: UserStatus.Raw) async {
        showSavingIndicator()
        defer { hideSavingIndicator() }
        
        state.bindings.isPresentingStatusPicker = false
        state.bindings.isShowingCustomStatusField = false
        
        if case .failure = await clientProxy.setUserStatus(status) {
            showFailureIndicator()
        }
    }
    
    /// Clears both the `UserStatus.Raw` and `UserStatus.Call` values simultaneously.
    private func clearUserStatus() async {
        showSavingIndicator()
        defer { hideSavingIndicator() }
        
        state.bindings.isPresentingStatusPicker = false
        state.bindings.isShowingCustomStatusField = false
        
        if case .failure = await clientProxy.clearUserStatus() {
            showFailureIndicator()
        }
    }
    
    // MARK: - Indicators
    
    private static var savingIndicatorID: String {
        "\(Self.self)-Saving"
    }
    
    private static var failureIndicatorID: String {
        "\(Self.self)-Failure"
    }
    
    private func showSavingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.savingIndicatorID,
                                                              type: .toast(progress: .indeterminate),
                                                              title: L10n.commonSaving,
                                                              persistent: true))
    }
    
    private func hideSavingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.savingIndicatorID)
    }
    
    private func showFailureIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.failureIndicatorID,
                                                              type: .toast,
                                                              title: L10n.commonFailed,
                                                              icon: \.close))
    }
}
