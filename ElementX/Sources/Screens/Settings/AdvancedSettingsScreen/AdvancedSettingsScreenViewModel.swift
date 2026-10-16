//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AdvancedSettingsScreenViewModelType = StateStoreViewModelV2<AdvancedSettingsScreenViewState, AdvancedSettingsScreenViewAction>

class AdvancedSettingsScreenViewModel: AdvancedSettingsScreenViewModelType, AdvancedSettingsScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let agentPlatformService: AgentPlatformServiceProtocol? // AGENT-PLATFORM (Brief 0078 phase 2)
    
    private var timelineMediaVisibilityTask: Task<Void, Never>?
    private var aiConsentTask: Task<Void, Never>?
    private var hideInviteAvatarsTask: Task<Void, Never>?
    
    private let actionsSubject: PassthroughSubject<AdvancedSettingsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AdvancedSettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(advancedSettings: AdvancedSettingsProtocol,
         clientProxy: ClientProxyProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         agentPlatformService: AgentPlatformServiceProtocol?) {
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        self.agentPlatformService = agentPlatformService
        
        let state = AdvancedSettingsScreenViewState(timelineMediaVisibility: clientProxy.timelineMediaVisibilityPublisher.value,
                                                    hideInviteAvatars: clientProxy.hideInviteAvatarsPublisher.value,
                                                    bindings: .init(advancedSettings: advancedSettings))
        super.init(initialViewState: state)
        
        clientProxy.timelineMediaVisibilityPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.timelineMediaVisibility, on: self)
            .store(in: &cancellables)
        
        clientProxy.hideInviteAvatarsPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.hideInviteAvatars, on: self)
            .store(in: &cancellables)
        
        // AGENT-PLATFORM (decision 187): the row shows only while someone is blocked, as on upstream's main screen.
        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .map { !($0?.isEmpty ?? true) }
            .weakAssign(to: \.state.showBlockedUsers, on: self)
            .store(in: &cancellables)
        
        aiConsentTask = Task { [weak self] in await self?.loadAIConsent() }
    }
    
    override func process(viewAction: AdvancedSettingsScreenViewAction) {
        switch viewAction {
        case .blockedUsers: // AGENT-PLATFORM (decision 187)
            actionsSubject.send(.blockedUsers)
        case let .updateHideInviteAvatars(value):
            hideInviteAvatarsTask = Task { [weak self] in await self?.updateHideInviteAvatars(value) }
        case let .updateTimelineMediaVisibility(value):
            timelineMediaVisibilityTask = Task { [weak self] in await self?.updateTimelineMediaVisibility(value) }
        case let .updateAIConsent(granted):
            aiConsentTask = Task { [weak self] in await self?.updateAIConsent(granted) }
        case .retryAIConsent:
            aiConsentTask = Task { [weak self] in await self?.retryAIConsent() }
        }
    }
    
    // MARK: - AI consent (AGENT-PLATFORM, Brief 0078 phase 2)
    
    private func loadAIConsent() async {
        guard let agentPlatformService else { return }
        switch await agentPlatformService.fetchAIConsent() {
        case .success(let consent):
            state.aiConsentGranted = consent.isGranted
            state.aiConsentLoadFailed = false
        case .failure(let error):
            MXLog.error("Fetching the AI consent failed: \(error)")
            state.aiConsentLoadFailed = true
        }
    }
    
    private func retryAIConsent() async {
        state.isWaitingAIConsent = true
        await loadAIConsent()
        state.isWaitingAIConsent = false
    }
    
    private func updateAIConsent(_ granted: Bool) async {
        guard let agentPlatformService, let previous = state.aiConsentGranted else { return }
        defer { state.isWaitingAIConsent = false }
        
        state.isWaitingAIConsent = true
        state.aiConsentGranted = granted
        
        switch await agentPlatformService.setAIConsent(granted: granted) {
        case .success(let consent):
            state.aiConsentGranted = consent.isGranted
        case .failure(let error):
            MXLog.error("Recording the AI consent decision failed: \(error)")
            state.aiConsentGranted = previous
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
        }
    }
    
    private func updateTimelineMediaVisibility(_ value: TimelineMediaVisibility) async {
        defer {
            timelineMediaVisibilityTask = nil
            state.isWaitingTimelineMediaVisibility = false
        }
        
        let previousState = state.timelineMediaVisibility
        state.isWaitingTimelineMediaVisibility = true
        state.timelineMediaVisibility = value
        // If the other value is updating wait also for it to finish
        await hideInviteAvatarsTask?.value
        
        switch await clientProxy.setTimelineMediaVisibility(value) {
        case .success:
            break
        case .failure:
            state.timelineMediaVisibility = previousState
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
        }
    }
    
    private func updateHideInviteAvatars(_ value: Bool) async {
        defer {
            hideInviteAvatarsTask = nil
            state.isWaitingHideInviteAvatars = false
        }
        
        let previousState = state.hideInviteAvatars
        state.isWaitingHideInviteAvatars = true
        state.hideInviteAvatars = value
        // If the other value is updating wait also for it to finish
        await timelineMediaVisibilityTask?.value
        
        switch await clientProxy.setHideInviteAvatars(value) {
        case .success:
            break
        case .failure:
            state.hideInviteAvatars = previousState
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
        }
    }
}
