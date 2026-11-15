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
    // AGENT-PLATFORM: platform sync (decision 289): the screen renders from the
    // session's store, so a change from the stream shows here and in the list.
    private let store: AgentsStore
    private var hasReportedGone = false
    
    private let actionsSubject: PassthroughSubject<AgentDetailScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentDetailScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(selection: AgentSelection,
         agentPlatformService: AgentPlatformServiceProtocol,
         clientProxy: ClientProxyProtocol,
         mediaProvider: MediaProviderProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         store: AgentsStore) {
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        self.store = store
        
        super.init(initialViewState: AgentDetailScreenViewState(selection: selection), mediaProvider: mediaProvider)
        
        state.ownerDMRoomID = AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: selection.card.matrixUserID, clientProxy: clientProxy)
        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        for resource in shownResources {
            store.show(resource, by: self)
        }
    }
    
    isolated deinit {
        for resource in shownResources {
            store.stopShowing(resource, by: self)
        }
    }
    
    /// The agent itself, its blocks (the count) and what waits for the owner; its card comes with the spaces.
    private var shownResources: [AgentsResource] {
        agentResources + [.needsAction]
    }
    
    private var agentResources: [AgentsResource] {
        [.agent(agentID: state.selection.card.agentID), .blocks(agentID: state.selection.card.agentID)]
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
        guard state.canWriteSwitches, state.paused != isPaused, !state.isPausing else { return }
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
        case .success(let readModel):
            // S5: the Agents tab's row follows the answer at once.
            store.agentEdited(readModel)
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
        guard state.canWriteSwitches, state.showInSearch != isOn, !state.isWritingVisibility else { return }
        state.isWritingVisibility = true
        state.pendingShowInSearch = isOn
        defer {
            state.isWritingVisibility = false
            state.pendingShowInSearch = nil
        }
        
        switch await agentPlatformService.editAgent(agentID: state.card.agentID, patch: AgentEditPatch(visibility: isOn ? "public" : "private")) {
        case .success(let readModel):
            // S5: the Agents tab's row follows the answer at once.
            store.agentEdited(readModel)
            actionsSubject.send(.changed)
        case .failure(let error):
            MXLog.error("Failed to set the visibility of agent \(state.card.agentID): \(error)")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentEditFailure,
                                                                  icon: \.error))
        }
        await reload()
    }
    
    /// What the store holds of this agent.
    private func render() {
        let agentID = state.selection.card.agentID
        let liveCard = store.card(agentID: agentID)
        if state.liveCard != liveCard {
            state.liveCard = liveCard
        }
        renderCounts(agentID: agentID)
        let detailState: AgentDetailScreenDetailState
        switch store.readState(.agent(agentID: agentID), \.agent) {
        case .loading:
            detailState = .loading
        case .failed(.notFound):
            // Deleted elsewhere: the screen closes rather than show a stale header over a failure.
            detailState = .failure
            if !hasReportedGone {
                hasReportedGone = true
                actionsSubject.send(.gone)
            }
        case .failed:
            detailState = .failure
        case .loaded(let detail):
            detailState = .loaded(detail.readModel, detail.rooms)
            let deviceRoomNames = AgentRoomLabel.deviceRoomNames(of: detail.rooms, clientProxy: clientProxy)
            if state.deviceRoomNames != deviceRoomNames {
                state.deviceRoomNames = deviceRoomNames
            }
            // Contextual verification banner (artboard 0037-D): never read, it stays hidden.
            if state.pendingVerifications != detail.pendingVerifications ?? [] {
                state.pendingVerifications = detail.pendingVerifications ?? []
            }
        }
        if state.detailState != detailState {
            state.detailState = detailState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }
    
    /// What waits and who is blocked. What waits is `nil` until read, never a made-up `0`.
    private func renderCounts(agentID: String) {
        let pendingApprovalsCount = store.needsAction.map { items in
            items.count { item in
                if case .approval(let approval) = item { approval.agentID == agentID } else { false }
            }
        }
        if state.pendingApprovalsCount != pendingApprovalsCount {
            state.pendingApprovalsCount = pendingApprovalsCount
        }
        let isReadingPendingApprovals = isReading(.needsAction, \.needsAction)
        if state.isReadingPendingApprovals != isReadingPendingApprovals {
            state.isReadingPendingApprovals = isReadingPendingApprovals
        }
        // A failed read keeps the last count rather than showing none.
        if case .blocks(let page)? = store.value(.blocks(agentID: agentID)), state.blockedCount != AgentBlockedCount(page: page) {
            state.blockedCount = AgentBlockedCount(page: page)
        }
        let isReadingBlocked = isReading(.blocks(agentID: agentID), \.blocks)
        if state.isReadingBlocked != isReadingBlocked {
            state.isReadingBlocked = isReadingBlocked
        }
    }
    
    /// Nothing of it is held and no read has failed yet.
    private func isReading<Value>(_ resource: AgentsResource, _ extract: (AgentsValue) -> Value?) -> Bool {
        if case .loading = store.readState(resource, extract) { true } else { false }
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
    
    /// Reads the agent now, after the person's own change (a write here or deeper in the flow).
    func reload() async {
        state.ownerDMRoomID = AgentRoomLabel.ownerDMRoomID(agentMatrixUserID: state.card.matrixUserID, clientProxy: clientProxy)
        for resource in agentResources {
            await store.reread(resource)
        }
    }
}
