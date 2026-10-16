//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//


import Combine
import SwiftUI

typealias InviteWelcomeScreenViewModelType = StateStoreViewModelV2<InviteWelcomeScreenViewState, InviteWelcomeScreenViewAction>

/// AGENT-PLATFORM (Brief 0073): the first screen after a registration that
/// came through an invitation — who invited you, and a way to write to them.
class InviteWelcomeScreenViewModel: InviteWelcomeScreenViewModelType, InviteWelcomeScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    
    private let actionsSubject: PassthroughSubject<InviteWelcomeScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InviteWelcomeScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(inviterUserID: String, clientProxy: ClientProxyProtocol, mediaProvider: MediaProviderProtocol?) {
        self.clientProxy = clientProxy
        super.init(initialViewState: .init(inviterUserID: inviterUserID), mediaProvider: mediaProvider)
        
        Task { await loadProfile() }
    }
    
    override func process(viewAction: InviteWelcomeScreenViewAction) {
        switch viewAction {
        case .message:
            Task { await openDirectChat() }
        case .later:
            actionsSubject.send(.dismiss)
        }
    }
    
    // MARK: - Private
    
    private func loadProfile() async {
        switch await clientProxy.profile(for: state.inviterUserID) {
        case .success(let profile):
            state.inviterProfile = profile
        case .failure(let error):
            MXLog.error("Failed loading the inviter's profile: \(error)")
        }
    }
    
    /// The button is the consent, so no upstream «send invite?» confirmation.
    private func openDirectChat() async {
        guard !state.isOpeningChat else { return }
        state.isOpeningChat = true
        defer { state.isOpeningChat = false }
        
        let userID = state.inviterUserID
        switch clientProxy.directRoomOrPendingInviteForUserID(userID) {
        case .success(.some(let roomID)):
            actionsSubject.send(.openDirectChat(roomID: roomID))
        case .success(.none):
            switch await clientProxy.createDirectRoom(with: userID, expectedRoomName: state.inviterProfile?.displayName) {
            case .success(let roomID):
                actionsSubject.send(.openDirectChat(roomID: roomID))
            case .failure:
                state.bindings.alertInfo = .init(id: .failedOpeningChat, title: L10n.commonError, message: L10n.screenStartChatErrorStartingChat)
            }
        case .failure:
            state.bindings.alertInfo = .init(id: .failedOpeningChat, title: L10n.commonError, message: L10n.screenStartChatErrorStartingChat)
        }
    }
}
