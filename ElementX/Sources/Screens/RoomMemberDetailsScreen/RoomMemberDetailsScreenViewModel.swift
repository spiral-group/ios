//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias RoomMemberDetailsScreenViewModelType = StateStoreViewModel<RoomMemberDetailsScreenViewState, RoomMemberDetailsScreenViewAction>

class RoomMemberDetailsScreenViewModel: RoomMemberDetailsScreenViewModelType, RoomMemberDetailsScreenViewModelProtocol {
    private let roomProxy: JoinedRoomProxyProtocol
    private let userSession: UserSessionProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let analytics: AnalyticsServiceProtocol
    
    private var actionsSubject: PassthroughSubject<RoomMemberDetailsScreenViewModelAction, Never> = .init()
    
    private var roomMemberProxy: RoomMemberProxyProtocol?
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    private var presenceObservation: PresenceObservation?
    // AGENT-PLATFORM (Brief 0078, ADR-0019 P5)
    private let assistantMemoryEraser: AssistantMemoryEraser?
    // AGENT-PLATFORM (decision 87)
    private let agentBlocks: AgentBlocks?
    /// Only the latest read's answer counts, and `.reading` lasts while any read is out.
    private var agentBlocksReadGeneration = 0
    private var agentBlocksReadsInFlight = 0
    private var latestAgentBlocksOutcome = AgentBlocksRead.notRead
    
    var actions: AnyPublisher<RoomMemberDetailsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userID: String,
         roomProxy: JoinedRoomProxyProtocol,
         userSession: UserSessionProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         analytics: AnalyticsServiceProtocol) {
        self.roomProxy = roomProxy
        self.userSession = userSession
        self.userIndicatorController = userIndicatorController
        self.analytics = analytics
        assistantMemoryEraser = userSession.agentPlatformService.map { // AGENT-PLATFORM (Brief 0078)
            AssistantMemoryEraser(agentPlatformService: $0, userIndicatorController: userIndicatorController)
        }
        agentBlocks = userSession.agentPlatformService.map { // AGENT-PLATFORM (decision 87)
            AgentBlocks(agentPlatformService: $0, userIndicatorController: userIndicatorController)
        }
        
        var initialViewState = RoomMemberDetailsScreenViewState(userID: userID, bindings: .init())
        initialViewState.canEraseAssistantMemory = assistantMemoryEraser != nil // AGENT-PLATFORM (Brief 0078)
        
        super.init(initialViewState: initialViewState, mediaProvider: userSession.mediaProvider)
        loadOwnAgentsIfNeeded() // AGENT-PLATFORM (Brief 0078)

        showMemberLoadingIndicator()
        
        Task {
            await loadMember()
            hideMemberLoadingIndicator()
        }
        
        roomProxy.identityStatusChangesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] changes in
                if changes.map(\.userId).contains(userID) {
                    Task { await self?.loadMember() }
                }
            }
            .store(in: &cancellables)
        
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        presenceObservation = PresenceObservation(userID: userID,
                                                  ownUserID: userSession.clientProxy.userID,
                                                  service: userSession.presenceObserverService) { [weak self] presence in
            self?.state.presence = presence
        }
    }
    
    // MARK: - Public
    
    func stop() {
        // Work around QLPreviewController dismissal issues, see the InteractiveQuickLookModifier.
        state.bindings.mediaPreviewItem = nil
        
        hideMemberLoadingIndicator()
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        presenceObservation?.cancel()
    }
    
    override func process(viewAction: RoomMemberDetailsScreenViewAction) {
        switch viewAction {
        case .showUnignoreAlert:
            state.bindings.ignoreUserAlert = .init(action: .unignore, mentionsAgents: agentBlocks != nil) // AGENT-PLATFORM (decision 98)
        case .showIgnoreAlert:
            state.bindings.ignoreUserAlert = .init(action: .ignore, mentionsAgents: agentBlocks != nil) // AGENT-PLATFORM (decision 98)
        case .ignoreConfirmed:
            Task { await ignoreUser() }
        case .unignoreConfirmed:
            Task { await unignoreUser() }
        case .displayAvatar(let url):
            Task { await displayFullScreenAvatar(url) }
        case .openDirectChat:
            openDirectChat()
        case .createDirectChat:
            Task { await createDirectChat() }
        case .startCall(let roomID, let isVoiceCall):
            Task { await startCall(roomID: roomID, isVoiceCall: isVoiceCall) }
        case .verifyUser:
            actionsSubject.send(.verifyUser(userID: state.userID))
        case .withdrawVerification:
            Task { await userSession.clientProxy.withdrawUserIdentityVerification(state.userID) }
        case .eraseAssistantMemory: // AGENT-PLATFORM (Brief 0078)
            confirmEraseAssistantMemory()
        case .unblockAgent(let agentID): // AGENT-PLATFORM (decision 87)
            confirmUnblock(agentID: agentID)
        case .appeared: // AGENT-PLATFORM (decision 87)
            loadOwnAgentsIfNeeded()
            readAgentBlocksIfOffered()
        }
    }
    
    // MARK: - Assistant memory (AGENT-PLATFORM, Brief 0078, ADR-0019 P5)
    
    /// Only an agent's profile needs to know whether the agent is the person's own.
    /// A failed read is read again on reappearing (decision 87), or one `nil` would
    /// hide the erase and the blocks for the screen's life.
    private func loadOwnAgentsIfNeeded() {
        guard let assistantMemoryEraser, SpiralAppPostSession.isAgent(state.userID),
              state.ownAgentMXIDs == nil, !state.isReadingOwnAgents else { return }
        state.isReadingOwnAgents = true
        Task { [weak self] in
            let mxids = await assistantMemoryEraser.ownAgentMXIDs()
            self?.state.ownAgentMXIDs = mxids
            self?.state.isReadingOwnAgents = false
            self?.loadAgentBlocksIfOffered()
        }
    }
    
    private func confirmEraseAssistantMemory() {
        guard let assistantMemoryEraser, !state.isErasingAssistantMemory else { return }
        let contactName = state.memberDetails?.name ?? state.userID
        state.bindings.alertInfo = assistantMemoryEraser.confirmation(id: .eraseAssistantMemory, contactName: contactName) { [weak self] in
            Task { await self?.eraseAssistantMemory(contactName: contactName) }
        }
    }
    
    private func eraseAssistantMemory(contactName: String) async {
        guard let assistantMemoryEraser else { return }
        state.isErasingAssistantMemory = true
        defer { state.isErasingAssistantMemory = false }
        await assistantMemoryEraser.erase(contactMXID: state.userID, contactName: contactName)
    }
    
    // MARK: - Agent blocks (AGENT-PLATFORM, decision 87)
    
    /// On the profile's load and once the person's own agents are known, until
    /// a read succeeds: after a failed one the next trigger reads again.
    private func loadAgentBlocksIfOffered() {
        guard state.agentBlocksRead != .read else { return }
        readAgentBlocksIfOffered()
    }
    
    /// A trigger's read, also on reappearing, under the erase's rule; none while a read is out.
    private func readAgentBlocksIfOffered() {
        guard let agentBlocks, state.showEraseAssistantMemorySection, state.agentBlocksRead != .reading else { return }
        state.agentBlocksRead = .reading
        Task { await readAgentBlocks(with: agentBlocks) }
    }
    
    /// Only the latest read's answer counts: one that went out before an Unblock's
    /// 204 can land after the read that followed it. A failed read keeps what is
    /// shown: a blip never passes for "not blocked".
    private func readAgentBlocks(with agentBlocks: AgentBlocks) async {
        agentBlocksReadGeneration += 1
        let generation = agentBlocksReadGeneration
        agentBlocksReadsInFlight += 1
        state.agentBlocksRead = .reading
        let blocks = await agentBlocks.blocks(ofContact: state.userID)
        agentBlocksReadsInFlight -= 1
        if generation == agentBlocksReadGeneration {
            if let blocks {
                state.agentBlocks = blocks
            }
            latestAgentBlocksOutcome = blocks == nil ? .failed : .read
        }
        if agentBlocksReadsInFlight == 0 {
            state.agentBlocksRead = latestAgentBlocksOutcome
        }
    }
    
    private func confirmUnblock(agentID: String) {
        guard let agentBlocks, state.unblockingAgentID == nil,
              let block = state.agentBlocks.first(where: { $0.agentID == agentID }) else { return }
        let contactName = state.memberDetails?.name ?? state.userID
        state.bindings.alertInfo = agentBlocks.confirmation(id: .unblockAgent, block: block, contactName: contactName) { [weak self] in
            Task { await self?.unblock(block) }
        }
    }
    
    private func unblock(_ block: AgentContactBlock) async {
        guard let agentBlocks else { return }
        state.unblockingAgentID = block.agentID
        defer { state.unblockingAgentID = nil }
        guard await agentBlocks.unblock(block, contactMXID: state.userID) else { return }
        state.agentBlocks.removeAll { $0.agentID == block.agentID }
        // Even with a read out: this one starts after the 204, so its answer wins.
        await readAgentBlocks(with: agentBlocks)
    }
    
    // MARK: - Private
    
    private func loadMember() async {
        switch await roomProxy.getMember(userID: state.userID) {
        case .success(let member):
            roomMemberProxy = member
            state.memberDetails = RoomMemberDetails(withProxy: member)
            state.isOwnMemberDetails = member.userID == roomProxy.ownUserID
            loadAgentBlocksIfOffered() // AGENT-PLATFORM (decision 87)
            switch userSession.clientProxy.directRoomForUserID(member.userID) {
            case .success(let roomID):
                state.dmRoomID = roomID
            case .failure:
                break
            }
        case .failure(let error):
            MXLog.warning("Failed to find member: \(error)")
            // As we didn't find a member with the specified user ID in this room we instead
            // fall back to showing a generic user profile screen as the source is likely
            // a message containing a permalink to someone who's not in this room.
            actionsSubject.send(.openUserProfile)
        }
        
        if case let .success(.some(identity)) = await userSession.clientProxy.userIdentity(for: state.userID, fallBackToServer: true) {
            state.verificationState = identity.verificationState
        } else {
            MXLog.error("Failed to find the member's identity.")
        }
    }
    
    private func ignoreUser() async {
        guard let roomMemberProxy else {
            fatalError()
        }
        
        state.isProcessingIgnoreRequest = true
        let result = await userSession.clientProxy.ignoreUser(roomMemberProxy.userID)
        state.isProcessingIgnoreRequest = false
        switch result {
        case .success:
            var details = state.memberDetails
            details?.isIgnored = true
            state.memberDetails = details
            
            updateMembers()
        case .failure:
            state.bindings.alertInfo = .init(id: .unknown)
        }
    }
    
    private func unignoreUser() async {
        guard let roomMemberProxy else {
            fatalError()
        }
        
        state.isProcessingIgnoreRequest = true
        let result = await userSession.clientProxy.unignoreUser(roomMemberProxy.userID)
        state.isProcessingIgnoreRequest = false
        switch result {
        case .success:
            var details = state.memberDetails
            details?.isIgnored = false
            state.memberDetails = details
            
            updateMembers()
        case .failure:
            state.bindings.alertInfo = .init(id: .unknown)
        }
    }
    
    private func updateMembers() {
        Task {
            await self.roomProxy.updateMembers()
        }
    }
    
    private func displayFullScreenAvatar(_ url: URL) async {
        guard let roomMemberProxy else {
            fatalError()
        }
        
        let loadingIndicatorIdentifier = "roomMemberAvatarLoadingIndicator"
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier, type: .modal, title: L10n.commonLoading, persistent: true))
        defer { userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier) }
        
        // We don't actually know the mime type here, assume it's an image.
        if let mediaSource = try? MediaSourceProxy(url: url, mimeType: "image/jpeg"),
           case let .success(file) = await userSession.mediaProvider.loadFileFromSource(mediaSource) {
            state.bindings.mediaPreviewItem = MediaPreviewItem(file: file, title: roomMemberProxy.displayName)
        }
    }
    
    private func openDirectChat() {
        guard let roomMemberProxy else { fatalError() }
        
        let loadingIndicatorIdentifier = "openDirectChatLoadingIndicator"
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
        defer { userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier) }
        
        switch userSession.clientProxy.directRoomOrPendingInviteForUserID(roomMemberProxy.userID) {
        case .success(let roomID):
            if let roomID {
                actionsSubject.send(.openDirectChat(roomID: roomID))
            } else if roomProxy.details.historySharingState != RoomHistorySharingState.hidden {
                Task {
                    let identity = await self.userSession.clientProxy.userIdentity(for: roomMemberProxy.userID, fallBackToServer: false)
                    let user: UserProfile = .init(userID: roomMemberProxy.userID, displayName: roomMemberProxy.displayName, avatarURL: roomMemberProxy.avatarURL)
                    let isUnknown = if case .success(let identity) = identity {
                        identity == nil
                    } else {
                        true
                    }
                    self.state.bindings.inviteConfirmationUser = .init(user: user, isUnknown: isUnknown)
                }
            } else {
                state.bindings.inviteConfirmationUser = .init(user: .init(userID: roomMemberProxy.userID, displayName: roomMemberProxy.displayName, avatarURL: roomMemberProxy.avatarURL), isUnknown: false)
            }
        case .failure:
            state.bindings.alertInfo = .init(id: .failedOpeningDirectChat)
        }
    }
    
    private func createDirectChat() async {
        guard let roomMemberProxy else { fatalError() }
        
        let loadingIndicatorIdentifier = "createDirectChatLoadingIndicator"
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(200))
        defer { userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier) }
        
        switch await userSession.clientProxy.createDirectRoom(with: roomMemberProxy.userID, expectedRoomName: roomMemberProxy.displayName) {
        case .success(let roomID):
            analytics.trackCreatedRoom(isDM: true)
            actionsSubject.send(.openDirectChat(roomID: roomID))
        case .failure:
            state.bindings.alertInfo = .init(id: .failedOpeningDirectChat)
        }
    }
    
    private func startCall(roomID: String, isVoiceCall: Bool) async {
        guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
            showErrorIndicator()
            return
        }
        await NativeCallConfiguration.awaitFirstMembers(of: roomProxy) // AGENT-PLATFORM: a fresh proxy's members decide the call's scope.
        actionsSubject.send(.startCall(roomProxy: roomProxy, isVoiceCall: isVoiceCall))
    }
    
    // MARK: User Indicators
    
    private var loadingIndicatorIdentifier: String {
        "\(Self.self)-Loading"
    }
    
    private var statusIndicatorIdentifier: String {
        "\(Self.self)-Status"
    }
    
    private func showMemberLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: true),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(100))
    }
    
    private func hideMemberLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier)
    }
    
    private func showErrorIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorIdentifier,
                                                              type: .toast,
                                                              title: L10n.errorUnknown,
                                                              icon: \.close))
    }
}
