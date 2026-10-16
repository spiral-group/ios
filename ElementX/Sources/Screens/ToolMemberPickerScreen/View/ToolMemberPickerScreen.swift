//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//

import Compound
import SwiftUI

struct ToolMemberPickerScreen: View {
    @Bindable var context: ToolMemberPickerScreenViewModel.Context
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                skeletonSection
            case .loaded where context.viewState.visibleMembers.isEmpty:
                emptySection
            case .loaded:
                membersSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenToolMemberPickerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $context.searchQuery)
        .compoundSearchField()
        .toolbar { toolbar }
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Sections

    private var skeletonSection: some View {
        Section {
            ForEach(0..<4, id: \.self) { _ in
                ListRow(label: .default(title: "@placeholder:example.com", icon: \.userProfile),
                        kind: .label)
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
        .disabled(true)
        .accessibilityRepresentation { Text(L10n.commonLoading) }
    }

    private var emptySection: some View {
        Section {
            Text(UntranslatedL10n.screenToolMemberPickerEmpty)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
        }
    }

    private var membersSection: some View {
        Section {
            ForEach(context.viewState.visibleMembers) { member in
                UserProfileListRow(user: UserProfile(userID: member.userID,
                                                     displayName: member.displayName,
                                                     avatarURL: member.avatarURL),
                                   membership: .join,
                                   mediaProvider: mediaProvider,
                                   kind: .multiSelection(isSelected: context.viewState.isSelected(member.userID)) {
                                       context.send(viewAction: .toggleMember(userID: member.userID))
                                   })
            }
        } header: {
            Text(UntranslatedL10n.screenToolMemberPickerSectionTitle)
                .compoundListSectionHeader()
        }
    }

    // Pushed onto the flow's sheet stack — the system back button dismisses
    // it, so no explicit cancel item (that duplicates the "<").
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            ToolbarButton(role: .confirm(title: confirmTitle)) {
                context.send(viewAction: .confirm)
            }
            .disabled(!context.viewState.canConfirm)
        }
    }

    private var confirmTitle: String {
        let count = context.viewState.selectionCount
        return count > 0 ? UntranslatedL10n.screenToolMemberPickerConfirmCount(count) : L10n.actionConfirm
    }
}

// MARK: - Previews

struct ToolMemberPickerScreen_Previews: PreviewProvider, TestablePreview {
    static let loadedViewModel = makeViewModel(members: .allMembers, selected: ["@alice:example.com"])
    static let loadingViewModel = makeViewModel(members: [], selected: [])

    static var previews: some View {
        ElementNavigationStack {
            ToolMemberPickerScreen(context: loadedViewModel.context, mediaProvider: MediaProviderMock(.init()))
        }
        .previewDisplayName("Loaded")

        ElementNavigationStack {
            ToolMemberPickerScreen(context: loadingViewModel.context, mediaProvider: MediaProviderMock(.init()))
        }
        .previewDisplayName("Loading")
    }

    private static func makeViewModel(members: [RoomMemberProxyMock], selected: [String]) -> ToolMemberPickerScreenViewModel {
        ToolMemberPickerScreenViewModel(roomProxy: JoinedRoomProxyMock(.init(members: members)),
                                        agentMatrixUserID: nil,
                                        preselectedMemberIDs: selected)
    }
}
