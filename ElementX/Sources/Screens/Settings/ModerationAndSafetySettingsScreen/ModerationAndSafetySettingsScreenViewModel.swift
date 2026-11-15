//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias ModerationAndSafetySettingsScreenViewModelType = StateStoreViewModelV2<ModerationAndSafetySettingsScreenViewState, ModerationAndSafetySettingsScreenViewAction>

class ModerationAndSafetySettingsScreenViewModel: ModerationAndSafetySettingsScreenViewModelType, ModerationAndSafetySettingsScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let agentsStore: AgentsStore? // AGENT-PLATFORM (Brief 0083, question 359)
    /// AGENT-PLATFORM (Brief 0083, question 359): whether a read that left after this opening has answered.
    private var hasReadAIConsent = false
    
    private var timelineMediaVisibilityTask: Task<Void, Never>?
    private var aiConsentTask: Task<Void, Never>?
    private var hideInviteAvatarsTask: Task<Void, Never>?
    
    private var actionsSubject: PassthroughSubject<ModerationAndSafetySettingsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ModerationAndSafetySettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userSession: UserSessionProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        clientProxy = userSession.clientProxy
        self.userIndicatorController = userIndicatorController
        agentsStore = userSession.agentsStore // AGENT-PLATFORM (Brief 0083, question 359)
        
        let state = ModerationAndSafetySettingsScreenViewState(hideInviteAvatars: clientProxy.hideInviteAvatarsPublisher.value,
                                                               timelineMediaVisibility: clientProxy.timelineMediaVisibilityPublisher.value,
                                                               bindings: .init(userSettings: userSession.userSettings))
        super.init(initialViewState: state)
        
        clientProxy.hideInviteAvatarsPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.hideInviteAvatars, on: self)
            .store(in: &cancellables)
        
        clientProxy.timelineMediaVisibilityPublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .weakAssign(to: \.state.timelineMediaVisibility, on: self)
            .store(in: &cancellables)
        
        clientProxy.ignoredUsersPublisher
            .receive(on: DispatchQueue.main)
            .map { $0?.isEmpty == false }
            .weakAssign(to: \.state.showBlockedUsers, on: self)
            .store(in: &cancellables)
        
        startShowingAIConsent() // AGENT-PLATFORM (Brief 0078 phase 2)
    }
    
    // AGENT-PLATFORM (Brief 0083, question 359)
    isolated deinit {
        agentsStore?.stopShowing(.aiConsent, by: self)
    }
    
    override func process(viewAction: ModerationAndSafetySettingsScreenViewAction) {
        switch viewAction {
        case let .updateHideInviteAvatars(value):
            hideInviteAvatarsTask = Task { [weak self] in await self?.updateHideInviteAvatars(value) }
        case let .updateTimelineMediaVisibility(value):
            timelineMediaVisibilityTask = Task { [weak self] in await self?.updateTimelineMediaVisibility(value) }
        case .blockedUsers:
            actionsSubject.send(.blockedUsers)
        case let .updateAIConsent(granted): // AGENT-PLATFORM (Brief 0078 phase 2)
            aiConsentTask = Task { [weak self] in await self?.updateAIConsent(granted) }
        case .retryAIConsent: // AGENT-PLATFORM (decision 150)
            aiConsentTask = Task { [weak self] in await self?.retryAIConsent() }
        }
    }
    
    // MARK: - AI consent (AGENT-PLATFORM, Brief 0078 phase 2, Brief 0083 question 359)
    
    private func startShowingAIConsent() {
        guard let agentsStore else { return }
        agentsStore.show(.aiConsent, by: self)
        renderAIConsent()
        agentsStore.observe { [weak self] in
            guard let self else { return false }
            renderAIConsent()
            return true
        }
        aiConsentTask = Task { [weak self] in await self?.readAIConsent() }
    }
    
    /// A value kept from earlier shows, but a failed read still means Retry: unlike the store's
    /// other readers, the switch writes only what was just read. The store's own retry can still answer.
    private func renderAIConsent() {
        // A write shows the choice until the server answers.
        guard let agentsStore, !state.isWaitingAIConsent else { return }
        let isGranted = agentsStore.aiConsent?.isGranted
        state.aiConsent = if !hasReadAIConsent {
            .reading(isGranted: isGranted)
        } else if let isGranted, agentsStore.failures[.aiConsent] == nil {
            .answered(isGranted: isGranted)
        } else {
            .failed
        }
    }
    
    private func readAIConsent() async {
        await agentsStore?.reread(.aiConsent)
        hasReadAIConsent = true
        renderAIConsent()
    }
    
    private func retryAIConsent() async {
        guard state.aiConsent == .failed, !state.isWaitingAIConsent else { return }
        state.isWaitingAIConsent = true
        await agentsStore?.reread(.aiConsent)
        state.isWaitingAIConsent = false
        renderAIConsent()
    }
    
    private func updateAIConsent(_ granted: Bool) async {
        guard let agentsStore, state.aiConsent.takesTaps, state.aiConsent.isGranted != granted, !state.isWaitingAIConsent else { return }
        
        state.isWaitingAIConsent = true
        state.aiConsent = .answered(isGranted: granted)
        let result = await agentsStore.setAIConsent(granted: granted)
        state.isWaitingAIConsent = false
        
        switch result {
        case .success:
            renderAIConsent()
        case .failure(let error):
            MXLog.error("Recording the AI consent decision failed: \(error)")
            userIndicatorController.submitIndicator(.init(title: L10n.errorUnknown))
            // It may have landed anyway: the switch takes taps again once a read says what the server holds.
            hasReadAIConsent = false
            renderAIConsent()
            await readAIConsent()
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
