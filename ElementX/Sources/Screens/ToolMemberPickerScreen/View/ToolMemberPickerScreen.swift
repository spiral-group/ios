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
import SpiralComponents
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

    // Decision 330: the members' rows as placeholders, after a short delay.
    private var skeletonSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 4, leading: .icon, hasSubtitle: false)
                }
            })
        }
    }

    private var emptySection: some View {
        Section {
            if context.searchQuery.isEmpty {
                SpiralEmptyState(symbol: .person2, title: UntranslatedL10n.screenToolMemberPickerEmpty)
                    .listRowBackground(Color.clear)
            } else {
                SpiralEmptyState(symbol: .magnifyingglass, title: L10n.commonNoResults, message: UntranslatedL10n.screenToolMemberPickerEmpty)
                    .listRowBackground(Color.clear)
            }
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
    static let noResultsViewModel = {
        let viewModel = makeViewModel(members: .allMembers, selected: [])
        viewModel.context.searchQuery = "Zed"
        return viewModel
    }()

    static var previews: some View {
        // Decision 330: without the wait, the snapshot caught the first load's blank 250 ms.
        ElementNavigationStack {
            ToolMemberPickerScreen(context: loadedViewModel.context, mediaProvider: MediaProviderMock(.init()))
        }
        .snapshotPreferences(expect: loadedViewModel.context.observe(\.viewState.isLoading).map { !$0 })
        .previewDisplayName("Loaded")

        ElementNavigationStack {
            ToolMemberPickerScreen(context: loadingViewModel.context, mediaProvider: MediaProviderMock(.init()))
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")

        ElementNavigationStack {
            ToolMemberPickerScreen(context: noResultsViewModel.context, mediaProvider: MediaProviderMock(.init()))
        }
        .snapshotPreferences(expect: noResultsViewModel.context.observe(\.viewState.isLoading).map { !$0 })
        .previewDisplayName("No results")
    }

    private static func makeViewModel(members: [RoomMemberProxyMock], selected: [String]) -> ToolMemberPickerScreenViewModel {
        ToolMemberPickerScreenViewModel(roomProxy: JoinedRoomProxyMock(.init(members: members)),
                                        agentMatrixUserID: nil,
                                        preselectedMemberIDs: selected)
    }
}
