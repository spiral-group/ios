//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct RoomSelectionScreen: View {
    @ObservedObject var context: RoomSelectionScreenViewModel.Context
    
    var body: some View {
        Form {
            if let emptyState = context.viewState.emptyState, context.viewState.showsEmptyState { // AGENT-PLATFORM
                emptySection(emptyState)
            }
            Section {
                ForEach(context.viewState.rooms) { room in
                    RoomSelectionListRow(room: room,
                                         isSelected: context.viewState.selectedRoomID == room.id,
                                         context: context)
                }
                // Replace these with ScrollView's `scrollPosition` when dropping iOS 16.
            } header: {
                emptyRectangle
                    .onAppear {
                        context.send(viewAction: .reachedTop)
                    }
            } footer: {
                emptyRectangle
                    .onAppear {
                        context.send(viewAction: .reachedBottom)
                    }
            }
        }
        .compoundList()
        .navigationTitle(L10n.screenRoomlistMainSpaceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionCancel) {
                    context.send(viewAction: .cancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(context.viewState.confirmTitle) { // AGENT-PLATFORM (decision 111)
                    context.send(viewAction: .confirm)
                }
                .disabled(context.viewState.selectedRoomID == nil)
                .accessibilityIdentifier(A11yIdentifiers.roomSelectionScreen.confirm) // AGENT-PLATFORM (decision 146)
            }
        }
        .searchController(query: $context.searchQuery, showsCancelButton: false)
        .compoundSearchField()
        .disableAutocorrection(true)
    }
    
    private func emptySection(_ emptyState: RoomSelectionScreenEmptyState) -> some View {
        Section {
            VStack(spacing: 8) {
                Text(emptyState.title)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Text(emptyState.message)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 40)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
    
    /// The greedy size of Rectangle can create an issue with the navigation bar when the search is highlighted, so is best to use a fixed frame instead of hidden() or EmptyView()
    private var emptyRectangle: some View {
        Rectangle()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

private struct RoomSelectionListRow: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    
    let room: RoomSelectionRoom
    let isSelected: Bool
    let context: RoomSelectionScreenViewModel.Context
    
    var body: some View {
        ListRow(label: .avatar(title: room.title,
                               description: room.description,
                               icon: avatar),
                kind: .selection(isSelected: isSelected) {
                    context.send(viewAction: .selectRoom(roomID: room.id))
                })
                .accessibilityIdentifier(A11yIdentifiers.roomSelectionScreen.room(room.title)) // AGENT-PLATFORM (decision 146)
    }
    
    @ViewBuilder
    var avatar: some View {
        if dynamicTypeSize < .accessibility3 {
            RoomAvatarImage(avatar: room.avatar,
                            avatarSize: .room(on: .roomSelection),
                            mediaProvider: context.mediaProvider)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Previews

struct RoomSelectionScreen_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        let summaryProvider = RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))
        let viewModel = RoomSelectionScreenViewModel(userSession: UserSessionMock(.init()),
                                                     roomSummaryProvider: summaryProvider)
        
        ElementNavigationStack {
            RoomSelectionScreen(context: viewModel.context)
        }
        
        // AGENT-PLATFORM: «В чат» with no chat an agent can join.
        let noChatsViewModel = RoomSelectionScreenViewModel(userSession: UserSessionMock(.init()),
                                                            roomSummaryProvider: summaryProvider,
                                                            roomFilter: { _ in false },
                                                            emptyState: .init(title: "No chats to add it to",
                                                                              message: "An agent joins a group chat you're in."))
        ElementNavigationStack {
            RoomSelectionScreen(context: noChatsViewModel.context)
        }
        .previewDisplayName("No chats")
    }
}
