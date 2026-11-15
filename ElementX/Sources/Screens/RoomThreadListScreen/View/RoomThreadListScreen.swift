//
// Copyright 2025 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents
import SwiftUI

struct RoomThreadListScreen: View {
    @Bindable var context: RoomThreadListScreenViewModel.Context
    
    var body: some View {
        content
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationTitle(L10n.commonThreads)
            .navigationBarTitleDisplayMode(.inline)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 357): the page was blank until it had a thread, whatever had happened.
    @ViewBuilder
    private var content: some View {
        switch context.viewState.content {
        case .loading:
            SpiralPreloader(label: L10n.commonLoading) {
                SpiralPlaceholderRows(count: 6, leading: .avatar(Avatars.Size.user(on: .threadList).value))
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .empty:
            SpiralEmptyState(symbol: .textBubble,
                             title: UntranslatedL10n.screenRoomThreadListEmptyTitle,
                             message: UntranslatedL10n.screenRoomThreadListEmptyMessage)
                .centredInScrollView()
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenRoomThreadListLoadFailed,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .centredInScrollView()
        case .list:
            list
        }
    }
    
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(context.viewState.items) { item in
                    Button {
                        context.send(viewAction: .tappedThread(threadRootEventID: item.id))
                    } label: {
                        RoomThreadListCell(item: item, mediaProvider: context.mediaProvider)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(ThreadCellButtonStyle())
                }
                
                footer
            }
        }
    }
    
    private var footer: some View {
        // Needs to be wrapped in a LazyStack otherwise appearance calls don't trigger
        LazyVStack(spacing: 0) {
            // AGENT-PLATFORM (Brief 0083, decision 357): older threads that failed to load aren't the list's end.
            if context.viewState.hasFailedToLoad {
                SpiralEmptyState(symbol: .exclamationmarkCircle,
                                 title: UntranslatedL10n.screenRoomThreadListLoadFailed,
                                 action: .init(L10n.actionRetry) { context.send(viewAction: .retry) },
                                 size: .compact)
                    .padding()
            } else {
                ProgressView()
                    .padding()
                    .opacity(context.viewState.isPaginating ? 1 : 0)
            }
            
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.compound.bgCanvasDefault)
                .onAppear {
                    context.send(viewAction: .oldestItemDidAppear)
                }
                .onDisappear {
                    context.send(viewAction: .oldestItemDidDisappear)
                }
        }
    }
}

private struct RoomThreadListCell: View {
    let item: RoomThreadListItem
    let mediaProvider: MediaProviderProtocol?
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            LoadableAvatarImage(url: item.rootMessageDetails.sender.avatarURL,
                                name: item.rootMessageDetails.sender.displayName,
                                contentID: item.rootMessageDetails.sender.id,
                                avatarSize: .user(on: .threadList),
                                mediaProvider: mediaProvider)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 16) {
                    creatorDetails
                    Spacer()
                    timestamp
                }
                
                rootMessageDetails
                latestMessageDetails
            }
        }
    }
    
    private var creatorDetails: some View {
        Text(item.rootMessageDetails.sender.disambiguatedDisplayName ?? item.rootMessageDetails.sender.id)
            .font(.compound.bodyLGSemibold)
            .foregroundColor(.compound.textPrimary)
            .lineLimit(1)
    }
    
    @ViewBuilder
    private var rootMessageDetails: some View {
        if let message = item.rootMessageDetails.message {
            Text(message)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private var latestMessageDetails: some View {
        if let latestMessageDetails = item.latestMessageDetails {
            HStack(alignment: .center, spacing: 8) {
                Label {
                    Text("\(item.numberOfReplies)")
                        .font(.compound.bodySMSemibold)
                        .foregroundColor(.compound.textSecondary)
                } icon: {
                    CompoundIcon(\.threads, size: .small, relativeTo: .compound.bodySMSemibold)
                        .foregroundColor(.compound.iconSecondary)
                }
                .labelStyle(.custom(spacing: 4, alignment: .center, iconLayout: .trailing))
                
                LoadableAvatarImage(url: latestMessageDetails.sender.avatarURL,
                                    name: latestMessageDetails.sender.displayName,
                                    contentID: latestMessageDetails.sender.id,
                                    avatarSize: .user(on: .threadSummary),
                                    mediaProvider: mediaProvider)
                    .accessibilityHidden(true)
                
                if let message = latestMessageDetails.message {
                    Text(message)
                        .font(.compound.bodySM)
                        .foregroundColor(.compound.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private var timestamp: some View {
        if let latestMessageDetails = item.latestMessageDetails {
            Text(latestMessageDetails.timestamp.formattedMinimal())
                .font(.compound.bodySM)
                .foregroundColor(.compound.textSecondary)
        } else {
            Text(item.rootMessageDetails.timestamp.formattedTime())
                .font(.compound.bodySM)
                .foregroundColor(.compound.textSecondary)
        }
    }
}

private struct ThreadCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.compound.bgSubtleSecondary : Color.compound.bgCanvasDefault)
            .contentShape(Rectangle())
    }
}

// MARK: - Previews

struct RoomThreadListScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    // AGENT-PLATFORM (Brief 0083, decision 357)
    static let loadingViewModel = makeViewModel(.init(items: [], paginationState: .loading))
    static let emptyViewModel = makeViewModel(.init(items: []))
    static let failedViewModel = makeFailedViewModel(items: [])
    static let failedOlderViewModel = makeFailedViewModel(items: .mocks)
    
    static var previews: some View {
        RoomThreadListScreen(context: viewModel.context)
        
        RoomThreadListScreen(context: loadingViewModel.context)
            .environment(\.spiralPreloaderDelay, .zero)
            .previewDisplayName("Loading")
        
        RoomThreadListScreen(context: emptyViewModel.context)
            .previewDisplayName("Empty")
        
        RoomThreadListScreen(context: failedViewModel.context)
            .previewDisplayName("Failed")
        
        RoomThreadListScreen(context: failedOlderViewModel.context)
            .previewDisplayName("Older threads failed")
    }
    
    static func makeFailedViewModel(items: [RoomThreadListItem]) -> RoomThreadListScreenViewModel {
        let viewModel = makeViewModel(.init(items: items, paginationState: .idle(endReached: false)))
        viewModel.state.hasFailedToLoad = true
        return viewModel
    }
    
    static func makeViewModel(_ configuration: RoomThreadListProxyMockConfiguration = .init()) -> RoomThreadListScreenViewModel {
        RoomThreadListScreenViewModel(threadListServiceProxy: RoomThreadListServiceProxyMock(configuration),
                                      mediaProvider: MediaProviderMock(.init()))
    }
}
