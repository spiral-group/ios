//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: who liked a post.
//

import Combine
import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct FeedLikersScreen: View {
    @Bindable var context: FeedLikersScreenViewModel.Context
    let dismiss: () -> Void

    var body: some View {
        content
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .feedSyncStatus(context.viewState.syncStatus)
            .feedBarTitle(UntranslatedL10n.screenFeedLikersTitle)
            .onAppear { context.send(viewAction: .appeared) }
            .onDisappear { context.send(viewAction: .disappeared) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionClose, action: dismiss)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch context.viewState.listState {
        case .loading:
            // Decision 330: the likers' rows as placeholders, after a short delay.
            SpiralPreloader(label: L10n.commonLoading) {
                SpiralPlaceholderRows(count: 6, leading: .avatar(Avatars.Size.user(on: .timeline).value), hasSubtitle: false)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .notAvailable:
            SpiralEmptyState(symbol: .eyeSlash,
                             title: UntranslatedL10n.screenFeedPostNotAvailableTitle,
                             message: UntranslatedL10n.screenFeedPostNotAvailableMessage)
                .centredInScrollView()
        case .unavailable:
            SpiralEmptyState(symbol: .wifiSlash,
                             title: UntranslatedL10n.screenFeedUnavailableTitle,
                             message: UntranslatedL10n.screenFeedUnavailableMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .centredInScrollView()
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenFeedLikersLoadFailedTitle,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .accessibilityIdentifier(A11yIdentifiers.feedLikersScreen.error)
                .centredInScrollView()
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if context.viewState.isEmpty {
                    SpiralEmptyState(symbol: .faceSmiling,
                                     title: UntranslatedL10n.screenFeedLikersEmptyTitle,
                                     message: UntranslatedL10n.screenFeedLikersEmptyMessage)
                        .padding(.vertical, 48)
                        .accessibilityIdentifier(A11yIdentifiers.feedLikersScreen.empty)
                }
                ForEach(context.viewState.likers) { liker in
                    row(liker)
                    if liker.id != context.viewState.likers.last?.id {
                        // Brief 0083: iOS's hairline, inset to where the name starts.
                        SpiralCardSeparator(leadingInset: CompoundDesignTokens.space4X + SpiralAvatarSize.small + CompoundDesignTokens.space3X)
                    }
                }
                if let sentinel = context.viewState.sentinel {
                    sentinelView(sentinel)
                }
            }
        }
        .feedSoftTopEdge()
    }

    private func row(_ liker: FeedLiker) -> some View {
        Button { context.send(viewAction: .openAuthor(userID: liker.author.userID)) } label: {
            HStack(spacing: CompoundDesignTokens.space3X) {
                LoadableAvatarImage(url: liker.author.avatarURL,
                                    name: liker.author.displayName,
                                    contentID: liker.author.userID,
                                    avatarSize: .user(on: .timeline),
                                    mediaProvider: context.mediaProvider)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: CompoundDesignTokens.space2X) {
                        Text(liker.author.displayName)
                            .font(.compound.bodyLG)
                            .foregroundStyle(.compound.textPrimary)
                            .lineLimit(1)
                        if liker.author.isOfficial {
                            FeedOfficialLabel()
                        }
                    }
                    if let userID = liker.author.shownUserID {
                        Text(userID)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yIdentifiers.feedLikersScreen.liker)
    }

    @ViewBuilder
    private func sentinelView(_ state: LoadMoreState) -> some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .failed:
            Button(UntranslatedL10n.screenAgentActivityLoadMoreFailed) { context.send(viewAction: .loadMore) }
                .buttonStyle(.compound(.tertiary, size: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        case .idle, .exhausted:
            Color.clear
                .frame(height: 1)
                .onAppear { context.send(viewAction: .loadMore) }
        }
    }
}

// MARK: - Previews

struct FeedLikersScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadedViewModel = makeViewModel(.success(FeedLikersPage(items: FeedPreviewData.likers, nextCursor: nil)))
    static let emptyViewModel = makeViewModel(.success(FeedLikersPage(items: [], nextCursor: nil)))
    static let failedViewModel = makeViewModel(.failure(.transport))
    static let notAvailableViewModel = makeViewModel(.failure(.notFound))

    static var previews: some View {
        preview(loadedViewModel, name: "Likers")
        preview(emptyViewModel, name: "Empty")
        preview(failedViewModel, name: "Failed")
        preview(notAvailableViewModel, name: "Not available")
    }

    private static func preview(_ viewModel: FeedLikersScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedLikersScreen(context: viewModel.context) { }
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<FeedLikersPage, FeedError>) -> FeedLikersScreenViewModel {
        let service = FeedServiceMock()
        service.likersPostIDCursorLimitReturnValue = result
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        return FeedLikersScreenViewModel(postID: FeedPreviewData.textPost.id,
                                         feedService: service,
                                         store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                         clientProxy: clientProxy,
                                         mediaProvider: MediaProviderMock(.init()),
                                         userIndicatorController: UserIndicatorControllerMock())
    }
}
