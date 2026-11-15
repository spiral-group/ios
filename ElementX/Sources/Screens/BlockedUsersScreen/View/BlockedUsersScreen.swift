//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct BlockedUsersScreen: View {
    @Bindable var context: BlockedUsersScreenViewModel.Context
    
    var body: some View {
        content
            .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(L10n.commonBlockedUsers)
            .alert(item: $context.alertInfo)
            .disabled(context.viewState.processingUserID != nil)
    }
    
    // MARK: - Private
    
    @ViewBuilder
    private var content: some View {
        if context.viewState.blockedUsers.isEmpty {
            // AGENT-PLATFORM (Brief 0083, lane settings): Spiral's empty state, as the agents' blocked list; was a grey line.
            SpiralEmptyState(symbol: .nosign, title: L10n.screenBlockedUsersEmpty)
                .centredInScrollView()
        } else {
            Form {
                ForEach(context.viewState.blockedUsers, id: \.self) { user in
                    ListRow(label: .avatar(title: user.displayName ?? user.id,
                                           description: user.displayName != nil ? user.id : nil,
                                           icon: avatar(for: user)),
                            details: .isWaiting(context.viewState.processingUserID == user.id),
                            kind: .button { context.send(viewAction: .unblockUser(user)) })
                        .accessibilityIdentifier(A11yIdentifiers.blockedUsersScreen.user(user.id)) // AGENT-PLATFORM (decision 146)
                        .contextMenu {
                            Button {
                                context.send(viewAction: .copyUserID(user))
                            } label: {
                                Label(L10n.actionCopy, icon: \.copy)
                            }
                        }
                }
            }
        }
    }
    
    private func avatar(for user: UserProfile) -> some View {
        LoadableAvatarImage(url: user.avatarURL,
                            name: user.displayName,
                            contentID: user.id,
                            avatarSize: .user(on: .blockedUsers),
                            mediaProvider: context.mediaProvider)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

// AGENT-PLATFORM (Brief 0083, lane settings): gated, with the empty state as a state of its own.
struct BlockedUsersScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = BlockedUsersScreenViewModel(hideProfiles: true,
                                                       userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: RoomMemberProxyMock.mockMe.userID)))),
                                                       userIndicatorController: UserIndicatorControllerMock())
    static let emptyViewModel = makeEmptyViewModel()
    
    static var previews: some View {
        ElementNavigationStack {
            BlockedUsersScreen(context: viewModel.context)
        }
        .previewDisplayName("Blocked")
        
        ElementNavigationStack {
            BlockedUsersScreen(context: emptyViewModel.context)
        }
        .previewDisplayName("Empty")
    }
    
    static func makeEmptyViewModel() -> BlockedUsersScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: RoomMemberProxyMock.mockMe.userID))
        clientProxy.ignoredUsersPublisher = .init([])
        return BlockedUsersScreenViewModel(hideProfiles: true,
                                           userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                           userIndicatorController: UserIndicatorControllerMock())
    }
}
