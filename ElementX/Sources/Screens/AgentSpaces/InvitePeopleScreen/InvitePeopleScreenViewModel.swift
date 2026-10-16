//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Combine
import SwiftUI

typealias InvitePeopleScreenViewModelType = StateStoreViewModelV2<InvitePeopleScreenViewState, InvitePeopleScreenViewAction>

/// The caller's personal invite link: share it, see the seats left, and
/// see who came through it. Ten seats, for good — no re-issue (the
/// operator, 2026-10-06).
class InvitePeopleScreenViewModel: InvitePeopleScreenViewModelType, InvitePeopleScreenViewModelProtocol {
    private let userSession: UserSessionProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let actionsSubject: PassthroughSubject<InvitePeopleScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InvitePeopleScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(userSession: UserSessionProtocol, userIndicatorController: UserIndicatorControllerProtocol) {
        self.userSession = userSession
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: InvitePeopleScreenViewState(), mediaProvider: userSession.mediaProvider)
        
        Task { await load() }
    }
    
    override func process(viewAction: InvitePeopleScreenViewAction) {
        switch viewAction {
        case .copyLink:
            guard let invite = state.invite else { return }
            UIPasteboard.general.url = invite.link.webURL
            userIndicatorController.submitIndicator(UserIndicator(title: L10n.commonCopiedToClipboard, icon: \.check))
        case .openUser(let user):
            actionsSubject.send(.openUser(userID: user.id))
        case .retry:
            Task { await load() }
        }
    }
    
    // MARK: - Private
    
    private func load() async {
        guard let service = userSession.agentPlatformService else {
            state.isLoading = false
            return
        }
        state.isLoading = true
        defer { state.isLoading = false }
        
        switch await service.fetchMyInvite() {
        case .success(let invite):
            state.invite = invite
        case .failure(let error):
            MXLog.error("Failed loading the invite link: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .loadFailed,
                                                 title: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in self?.process(viewAction: .retry) },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
            return
        }
        
        switch await service.fetchMyInviteJoined() {
        case .success(let joined):
            // The backend knows only MXIDs. Show them at once; names and
            // avatars come from the homeserver, all lookups in parallel —
            // one by one the list arrived seconds late (Brief 0073 re-run).
            state.joined = joined.map { UserProfile(userID: $0.userID) }
            let lookups = joined.map { entry in
                Task { await self.fetchProfile(userID: entry.userID) }
            }
            var profiles: [UserProfile] = []
            for lookup in lookups {
                profiles.append(await lookup.value)
            }
            state.joined = profiles
        case .failure(let error):
            MXLog.error("Failed loading who joined through the invite link: \(error)")
        }
    }
    
    private func fetchProfile(userID: String) async -> UserProfile {
        switch await userSession.clientProxy.profile(for: userID) {
        case .success(let profile): profile
        case .failure: UserProfile(userID: userID)
        }
    }
}
