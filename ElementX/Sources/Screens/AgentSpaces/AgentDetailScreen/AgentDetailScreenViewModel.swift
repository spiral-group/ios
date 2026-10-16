//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentDetailScreenViewModelType = StateStoreViewModelV2<AgentDetailScreenViewState, AgentDetailScreenViewAction>

class AgentDetailScreenViewModel: AgentDetailScreenViewModelType, AgentDetailScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let approvalsStreamService: ApprovalsStreamServiceProtocol?
    
    private let actionsSubject: PassthroughSubject<AgentDetailScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentDetailScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(selection: AgentSelection,
         agentPlatformService: AgentPlatformServiceProtocol,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         approvalsStreamService: ApprovalsStreamServiceProtocol?) {
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        self.approvalsStreamService = approvalsStreamService
        
        super.init(initialViewState: AgentDetailScreenViewState(selection: selection), mediaProvider: mediaProvider)
        
        observePendingApprovals()
        Task { await reload() }
    }
    
    // MARK: - Public
    
    override func process(viewAction: AgentDetailScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .selectRoom(let room):
            actionsSubject.send(.selectRoom(room))
        case .edit:
            actionsSubject.send(.showEdit)
        case .message:
            actionsSubject.send(.message)
        case .addToChat:
            guard !state.isAddingToChat else { return }
            actionsSubject.send(.addToChat(agentRoomIDs: state.agentRoomIDs))
        case .openVerification:
            if let first = state.pendingVerifications.first {
                actionsSubject.send(.showVerification(id: first.id))
            }
        case .openActivity:
            actionsSubject.send(.showActivity)
        case .openUsage:
            actionsSubject.send(.showUsage)
        case .openQueue:
            actionsSubject.send(.showQueue)
        case .openSettings(let section):
            actionsSubject.send(.showSettings(section))
        case .openPendingApprovals:
            actionsSubject.send(.showPendingApprovals)
        case .openBlocked:
            actionsSubject.send(.showBlocked)
        case .setPaused(let isPaused):
            Task { await setPaused(isPaused) }
        case .setShowInSearch(let isOn):
            Task { await setShowInSearch(isOn) }
        case .archiveTapped:
            guard state.canArchive else { return }
            state.bindings.alertInfo = AlertInfo(id: .confirmArchive,
                                                 title: UntranslatedL10n.screenAgentDetailArchiveAlertTitle,
                                                 message: UntranslatedL10n.screenAgentDetailArchiveAlertMessage,
                                                 primaryButton: .init(title: UntranslatedL10n.actionArchiveAgent, role: .destructive) { [weak self] in
                                                     self?.context.send(viewAction: .confirmArchive)
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        case .confirmArchive:
            guard state.canArchive else { return }
            Task { await archive() }
        case .retry:
            state.detailState = .loading
            Task { await reload() }
        case .refresh:
            Task { await reload() }
        }
    }
    
    /// The chat the owner picked gets the agent: the owner invites it, then
    /// the agent accepts (ADR-0017, never a force-join). An invite that fails
    /// because the agent is already invited is fine — the accept is what says
    /// whether it worked. An accept that fails takes back the invite this
    /// attempt sent, so the chat isn't left with an invite nobody accepts.
    func addToChat(roomID: String) async {
        guard !state.isAddingToChat else { return }
        state.isAddingToChat = true
        defer { state.isAddingToChat = false }
        
        let indicatorID = "agent-detail-add-to-chat"
        userIndicatorController.submitIndicator(UserIndicator(id: indicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true))
        defer { userIndicatorController.retractIndicatorWithId(indicatorID) }
        
        guard case .joined(let roomProxy) = await clientProxy.roomForIdentifier(roomID) else {
            MXLog.error("Add to chat: \(roomID) is not a joined room")
            showAddToChatFailure()
            return
        }
        
        let agentUserID = state.card.matrixUserID
        if case .success(let member) = await roomProxy.getMember(userID: agentUserID), member.membership == .join {
            MXLog.info("Add to chat: \(agentUserID) is already in \(roomID)")
            state.bindings.alertInfo = AlertInfo(id: .alreadyInChat,
                                                 title: UntranslatedL10n.screenAgentDetailAlreadyInChat)
            return
        }
        
        let didInvite: Bool
        switch await roomProxy.invite(userID: agentUserID) {
        case .success:
            didInvite = true
        case .failure:
            MXLog.info("Add to chat: the invite of \(agentUserID) to \(roomID) failed; trying the accept")
            didInvite = false
        }
        
        switch await agentPlatformService.joinRoom(agentID: state.card.agentID, roomID: roomID) {
        case .success:
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentDetailAddedToChat,
                                                                  icon: \.checkCircle))
            await reload()
            actionsSubject.send(.addedToChat)
        case .failure:
            MXLog.error("Add to chat: agent \(state.card.agentID) didn't join \(roomID)")
            if didInvite {
                await withdrawInvite(of: agentUserID, from: roomProxy)
            }
            showAddToChatFailure()
        }
    }
    
    /// Best effort: kicking an invited user revokes the invite.
    private func withdrawInvite(of userID: String, from roomProxy: JoinedRoomProxyProtocol) async {
        if case .failure = await roomProxy.kickUser(userID, reason: nil) {
            MXLog.error("Add to chat: couldn't withdraw the invite of \(userID) to \(roomProxy.id)")
        }
    }
    
    /// The pause applies at once; a failure says so quietly and the switch
    /// follows the server again.
    private func setPaused(_ isPaused: Bool) async {
        guard let current = state.paused, current != isPaused, !state.isPausing else { return }
        state.isPausing = true
        // Shown at once; the read after the write says what stuck.
        state.pendingPause = isPaused
        defer {
            state.isPausing = false
            state.pendingPause = nil
        }
        
        let patch = AgentEditPatch(paused: isPaused)
        var result = await agentPlatformService.editAgent(agentID: state.card.agentID, patch: patch)
        // A 500 on a pause: it is stored, but leaving a call failed. Sending
        // it again leaves the calls again (decision 195); once is enough.
        if isPaused, case .failure(.serverError(status: 500)) = result {
            MXLog.info("Pausing agent \(state.card.agentID) left a call behind; sending the pause again")
            result = await agentPlatformService.editAgent(agentID: state.card.agentID, patch: patch)
        }

        switch result {
        case .success:
            actionsSubject.send(.changed)
        case .failure(let error):
            MXLog.error("Failed to set the pause of agent \(state.card.agentID): \(error)")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentEditFailure,
                                                                  icon: \.error))
        }
        await reload()
    }
    
    /// Like the pause: applied at once, the read after it says what stuck.
    private func setShowInSearch(_ isOn: Bool) async {
        guard let current = state.showInSearch, current != isOn, !state.isWritingVisibility else { return }
        state.isWritingVisibility = true
        state.pendingShowInSearch = isOn
        defer {
            state.isWritingVisibility = false
            state.pendingShowInSearch = nil
        }
        
        switch await agentPlatformService.editAgent(agentID: state.card.agentID, patch: AgentEditPatch(visibility: isOn ? "public" : "private")) {
        case .success:
            actionsSubject.send(.changed)
        case .failure(let error):
            MXLog.error("Failed to set the visibility of agent \(state.card.agentID): \(error)")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentEditFailure,
                                                                  icon: \.error))
        }
        await reload()
    }
    
    /// Follows the stream while the screen is shown. Only a seeded stream has
    /// read what waits; before that it holds nothing, not zero.
    private func observePendingApprovals() {
        guard let approvalsStreamService else { return }
        let agentID = state.card.agentID
        // Reads only the stream inside the tracking: a write to `state` there would re-fire it.
        let count = withObservationTracking {
            approvalsStreamService.isSeeded ? approvalsStreamService.needsAction.count { item in
                if case .approval(let approval) = item { approval.agentID == agentID } else { false }
            } : nil
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observePendingApprovals() }
        }
        state.pendingApprovalsCount = count
    }
    
    private func showAddToChatFailure() {
        state.bindings.alertInfo = AlertInfo(id: .addToChatFailed,
                                             title: UntranslatedL10n.screenAgentDetailAddToChatFailure)
    }
    
    private func archive() async {
        state.isArchiving = true
        defer { state.isArchiving = false }
        
        switch await agentPlatformService.archiveAgent(agentID: state.card.agentID) {
        case .success:
            actionsSubject.send(.archived)
        case .failure(.conflict):
            // Decision 153: the agent stays; there is nothing to retry.
            state.bindings.alertInfo = AlertInfo(id: .archiveRefused,
                                                 title: UntranslatedL10n.screenAgentDetailArchiveRefused)
        case .failure(let error):
            MXLog.error("Failed to archive agent: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .archiveFailed,
                                                 title: UntranslatedL10n.screenAgentDetailArchiveFailure)
        }
    }
    
    func reload() async {
        // Sequential awaits: Swift 6.2 strict checking forbids `async let`
        // child tasks capturing the non-Sendable service existential.
        let readModelResult = await agentPlatformService.fetchAgentReadModel(agentID: state.card.agentID)
        let roomsResult = await agentPlatformService.fetchAgentRooms(agentID: state.card.agentID)
        // Contextual verification banner (artboard 0037-D) — a failed
        // fetch just leaves the banner hidden; never blocks the screen.
        let verificationsResult = await agentPlatformService.listVerificationsForAgent(agentID: state.card.agentID)
        
        if case .success(let pending) = verificationsResult {
            state.pendingVerifications = pending
        }
        // A failed read keeps the last count rather than showing none.
        switch await agentPlatformService.listBlockedContacts(agentID: state.card.agentID, cursor: nil, limit: AgentBlockedScreenViewModel.pageSize) {
        case .success(let page):
            state.blockedCount = AgentBlockedCount(page: page)
        case .failure(let error):
            MXLog.error("Failed to count the blocks of agent \(state.card.agentID): \(error)")
        }
        
        state.ownerDMRoomID = AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: state.card.matrixUserID, clientProxy: clientProxy)
        
        switch (readModelResult, roomsResult) {
        case (.success(let readModel), .success(let rooms)):
            state.detailState = .loaded(readModel, rooms)
        case (.failure(let error), _), (_, .failure(let error)):
            MXLog.error("Failed to load agent \(state.card.agentID): \(error)")
            // Keep stale content when a refresh fails.
            if case .loaded = state.detailState {} else {
                state.detailState = .failure
            }
        }
    }
}
