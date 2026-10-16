//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias ToolMemberPickerScreenViewModelType = StateStoreViewModelV2<ToolMemberPickerScreenViewState, ToolMemberPickerScreenViewAction>

/// Drives `ToolMemberPickerScreen`. Reads the room's own joined/invited
/// members from `roomProxy.membersPublisher`, filtering out the agent
/// itself and every other platform agent in the room (a tool scopes people
/// who write messages; re-walk R4) so the owner only picks real
/// counterparts. Returns the chosen MXIDs to
/// the arm form via a coordinator action.
class ToolMemberPickerScreenViewModel: ToolMemberPickerScreenViewModelType, ToolMemberPickerScreenViewModelProtocol {
    private let roomProxy: JoinedRoomProxyProtocol
    /// The agent's Matrix user id — excluded from the candidate list.
    private let agentMatrixUserID: String?

    private let actionsSubject: PassthroughSubject<ToolMemberPickerScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ToolMemberPickerScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomProxy: JoinedRoomProxyProtocol,
         agentMatrixUserID: String?,
         preselectedMemberIDs: [String]) {
        self.roomProxy = roomProxy
        self.agentMatrixUserID = agentMatrixUserID

        var bindings = ToolMemberPickerScreenViewStateBindings()
        bindings.selectedMemberIDs = preselectedMemberIDs
        super.init(initialViewState: ToolMemberPickerScreenViewState(bindings: bindings))

        observeMembers()
    }

    // MARK: - Public

    override func process(viewAction: ToolMemberPickerScreenViewAction) {
        MXLog.info("ToolMemberPickerScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            Task { await roomProxy.updateMembers() }
        case .toggleMember(let userID):
            toggle(userID)
        case .confirm:
            actionsSubject.send(.confirm(members: state.bindings.selectedMemberIDs))
        }
    }

    // MARK: - Private

    private func toggle(_ userID: String) {
        if let index = state.bindings.selectedMemberIDs.firstIndex(of: userID) {
            state.bindings.selectedMemberIDs.remove(at: index)
        } else {
            state.bindings.selectedMemberIDs.append(userID)
        }
    }

    private func observeMembers() {
        roomProxy.membersPublisher
            // The proxy seeds an empty array before the first real load;
            // wait for the populated emission so we don't flash "no
            // members" over the skeleton. `.appeared` kicks `updateMembers`.
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] members in
                guard let self else { return }
                state.listState = .loaded(members: Self.projectMembers(members,
                                                                       excluding: agentMatrixUserID,
                                                                       ownUserID: roomProxy.ownUserID))
            }
            .store(in: &cancellables)
    }

    /// Project the room's members into pickable items — active people only,
    /// agents excluded, sorted by display name. Static so tests can exercise
    /// the projection without the SDK.
    static func projectMembers(_ members: [RoomMemberProxyProtocol],
                               excluding agentMatrixUserID: String?,
                               ownUserID: String) -> [ToolMemberPickerItem] {
        members
            .filter { member in
                member.isActive
                    && member.userID != agentMatrixUserID
                    && !SpiralAgentRoomGrants.isLocalAgent(member.userID, ownUserID: ownUserID)
            }
            .sorted { $0.sortingName < $1.sortingName }
            .map { ToolMemberPickerItem(userID: $0.userID,
                                        displayName: $0.displayName,
                                        avatarURL: $0.avatarURL) }
    }
}
