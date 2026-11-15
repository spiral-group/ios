//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import MatrixRustSDK
import SwiftUI

typealias UserProfileScreenViewModelType = StateStoreViewModelV2<UserProfileScreenViewState, UserProfileScreenViewAction>

class UserProfileScreenViewModel: UserProfileScreenViewModelType, UserProfileScreenViewModelProtocol {
    private let userSession: UserSessionProtocol
    private let analytics: AnalyticsServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private var actionsSubject: PassthroughSubject<UserProfileScreenViewModelAction, Never> = .init()
    // AGENT-PLATFORM (Brief 0072, ADR-0083)
    private var presenceObservation: PresenceObservation?
    private var agentCardObservation: AgentCardObservation? // AGENT-PLATFORM (Brief 0083, question 359)
    // AGENT-PLATFORM (Brief 0078, ADR-0019 P5)
    private let assistantMemoryEraser: AssistantMemoryEraser?
    // AGENT-PLATFORM (decision 87)
    private let agentBlocks: AgentBlocks?
    /// Only the latest read's answer counts, and `.reading` lasts while any read is out.
    private var agentBlocksReadGeneration = 0
    private var agentBlocksReadsInFlight = 0
    private var latestAgentBlocksOutcome = AgentBlocksRead.notRead
    var actionsPublisher: AnyPublisher<UserProfileScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userID: String,
         isPresentedModally: Bool,
         userSession: UserSessionProtocol,
         analytics: AnalyticsServiceProtocol,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.userSession = userSession
        self.analytics = analytics
        self.userIndicatorController = userIndicatorController
        assistantMemoryEraser = userSession.agentPlatformService.map { // AGENT-PLATFORM (Brief 0078)
            AssistantMemoryEraser(agentPlatformService: $0, userIndicatorController: userIndicatorController)
        }
        agentBlocks = userSession.agentPlatformService.map { // AGENT-PLATFORM (decision 87)
            AgentBlocks(agentPlatformService: $0, userIndicatorController: userIndicatorController)
        }
        
        var initialViewState = UserProfileScreenViewState(userID: userID,
                                                          isOwnUser: userID == userSession.clientProxy.userID,
                                                          isPresentedModally: isPresentedModally,
                                                          bindings: .init())
        initialViewState.canEraseAssistantMemory = assistantMemoryEraser != nil // AGENT-PLATFORM (Brief 0078)
        
        super.init(initialViewState: userSession.userHooks.userProfileScreenHook.update(initialViewState),
                   mediaProvider: userSession.mediaProvider)
        
        // AGENT-PLATFORM (Brief 0083, question 359): first, so that the page has its shape before it's pushed.
        agentCardObservation = AgentCardObservation(userID: userID, store: userSession.agentsStore) { [weak self] ownership in
            self?.state.agentOwnership = ownership
            self?.loadAgentBlocksIfOffered()
        }

        showLoadingIndicator(allowsInteraction: true)
        Task {
            await loadProfile()
            hideLoadingIndicator()
        }
        
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        presenceObservation = PresenceObservation(userID: userID,
                                                  ownUserID: userSession.clientProxy.userID,
                                                  service: userSession.presenceObserverService,
                                                  agentsStore: userSession.agentsStore) { [weak self] presence in
            self?.state.presence = presence
        }
    }
    
    // MARK: - Public
    
    func stop() {
        // Work around QLPreviewController dismissal issues, see the InteractiveQuickLookModifier.
        state.bindings.mediaPreviewItem = nil
        
        hideLoadingIndicator()
        // AGENT-PLATFORM (Brief 0072, ADR-0083)
        presenceObservation?.cancel()
        agentCardObservation?.cancel() // AGENT-PLATFORM (Brief 0083, question 359)
    }
    
    override func process(viewAction: UserProfileScreenViewAction) {
        switch viewAction {
        case .displayAvatar(let url):
            Task { await displayFullScreenAvatar(url) }
        case .openDirectChat:
            openDirectChat()
        case .createDirectChat:
            Task { await createDirectChat() }
        case .startCall(let roomID, let isVoiceCall):
            Task { await startCall(roomID: roomID, isVoiceCall: isVoiceCall) }
        case .dismiss:
            actionsSubject.send(.dismiss)
        case .eraseAssistantMemory: // AGENT-PLATFORM (Brief 0078)
            confirmEraseAssistantMemory()
        case .unblockAgent(let agentID): // AGENT-PLATFORM (decision 87)
            confirmUnblock(agentID: agentID)
        case .appeared: // AGENT-PLATFORM (decision 87)
            agentCardObservation?.readAgainIfUnknown()
            readAgentBlocksIfOffered()
        case .openAgentRow(let row): // AGENT-PLATFORM (Brief 0083, question 359)
            guard let card = state.agentProfile?.ownCard else { return }
            actionsSubject.send(.openAgentRow(row, card: card))
        }
    }
    
    // MARK: - Assistant memory (AGENT-PLATFORM, Brief 0078, ADR-0019 P5)
    
    private func confirmEraseAssistantMemory() {
        guard let assistantMemoryEraser, !state.isErasingAssistantMemory else { return }
        let contactName = state.userProfile?.displayName ?? state.userID
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
        let contactName = state.userProfile?.displayName ?? state.userID
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
    
    // The proxies aren't Sendable, fetch through these helpers so that
    // they never leave the main actor when running calls in parallel.
    
    private func fetchProfile() async -> Result<UserProfile, ClientProxyError> {
        await userSession.clientProxy.profile(for: state.userID)
    }
    
    private func fetchUserIdentity() async -> Result<UserIdentityProxyProtocol?, ClientProxyError> {
        await userSession.clientProxy.userIdentity(for: state.userID, fallBackToServer: true)
    }
    
    private func loadProfile() async {
        async let profileResult = fetchProfile()
        async let identityResult = fetchUserIdentity()
        
        switch await profileResult {
        case .success(let userProfile):
            state.userProfile = userProfile
            loadAgentBlocksIfOffered() // AGENT-PLATFORM (decision 87)
            // AGENT-PLATFORM (Brief 0060): spiral.md smart link.
            state.permalink = SpiralLink(userID: state.userID)?.webURL
            
            switch userSession.clientProxy.directRoomForUserID(userProfile.id) {
            case .success(let roomID):
                state.dmRoomID = roomID
            case .failure:
                break
            }
        case .failure(let error):
            state.bindings.alertInfo = .init(id: .unknown)
            MXLog.error("Failed to find user profile: \(error)")
        }
        
        if case let .success(.some(identity)) = await identityResult {
            state.isIdentityKnown = true
            state.isVerified = identity.verificationState == .verified
        } else {
            state.isIdentityKnown = false
            MXLog.error("Failed to find the user's identity.")
        }
    }
    
    private func displayFullScreenAvatar(_ url: URL) async {
        guard let userProfile = state.userProfile else { fatalError() }
        
        showLoadingIndicator(allowsInteraction: false)
        defer { hideLoadingIndicator() }
        
        state.bindings.mediaPreviewItem = await MediaPreviewItem.load(from: url, title: userProfile.displayName, using: userSession.mediaProvider)
    }
    
    private func openDirectChat() {
        guard let userProfile = state.userProfile else { fatalError() }
        
        showLoadingIndicator(allowsInteraction: false)
        defer { hideLoadingIndicator() }
        
        switch userSession.clientProxy.directRoomOrPendingInviteForUserID(userProfile.id) {
        case .success(let roomID):
            if let roomID {
                actionsSubject.send(.openDirectChat(roomID: roomID))
            } else {
                Task {
                    let isUnknown = if case let .success(identity) = await userSession.clientProxy.userIdentity(for: userProfile.id, fallBackToServer: false) {
                        identity == nil
                    } else {
                        true
                    }
                    state.bindings.inviteConfirmationUser = .init(user: userProfile, isUnknown: isUnknown)
                }
            }
        case .failure:
            state.bindings.alertInfo = .init(id: .failedOpeningDirectChat)
        }
    }
    
    private func createDirectChat() async {
        guard let userProfile = state.userProfile else { fatalError() }
        
        showLoadingIndicator(allowsInteraction: false)
        defer { hideLoadingIndicator() }
        
        switch await userSession.clientProxy.createDirectRoom(with: userProfile.id, expectedRoomName: userProfile.displayName) {
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
    
    private func showLoadingIndicator(allowsInteraction: Bool) {
        userIndicatorController.submitIndicator(UserIndicator(id: loadingIndicatorIdentifier,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: false, allowsInteraction: allowsInteraction),
                                                              title: L10n.commonLoading,
                                                              persistent: true),
                                                delay: .milliseconds(100))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(loadingIndicatorIdentifier)
    }
    
    private func showErrorIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: statusIndicatorIdentifier,
                                                              type: .toast,
                                                              title: L10n.errorUnknown,
                                                              icon: \.close))
    }
}
