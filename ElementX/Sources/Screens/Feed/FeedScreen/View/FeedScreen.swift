//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Combine
import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct FeedScreen: View {
    @Bindable var context: FeedScreenViewModel.Context

    private static let topID = "feed-top"

    var body: some View {
        content
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .feedBarTitle(UntranslatedL10n.screenHomeTabFeed, pill: newPostsPill)
            .environment(\.shouldAutomaticallyLoadImages, !context.viewState.hidesMedia)
            .interactiveQuickLook(item: $context.mediaPreviewItem, allowEditing: false)
            .toolbar { toolbar }
            .onAppear { context.send(viewAction: .appeared) }
            .onDisappear { context.send(viewAction: .disappeared) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { context.send(viewAction: .openActivity) } label: {
                FeedBellToolbarIcon(unread: context.viewState.bellUnread)
            }
            .accessibilityLabel(context.viewState.bellAccessibilityLabel)
            .accessibilityIdentifier(A11yIdentifiers.feedNoticesScreen.toolbarButton)
        }
        ToolbarItem(placement: .primaryAction) {
            Button { context.send(viewAction: .compose) } label: {
                CompoundIcon(\.compose)
                    .accessibilityLabel(UntranslatedL10n.screenFeedComposerTitle)
            }
            .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.compose)
        }
        // Brief 0083, decision 349: this leads, as Chats' filter does: with three buttons at the trailing end the system moves
        // the centred title to the leading edge to keep it clear of them.
        ToolbarItem(placement: .topBarLeading) {
            Button { context.send(viewAction: .openOwnPosts) } label: {
                FeedOwnPhotoLabel(profile: context.viewState.ownProfile, mediaProvider: context.mediaProvider)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(UntranslatedL10n.screenFeedOwnPosts)
            .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.ownPosts)
        }
        // The bar's shared glass is a lozenge round a custom label; the label's own circle matches Back and "…".
        .backportSharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder
    private var content: some View {
        switch context.viewState.listState {
        case .loading:
            FeedPostsPreloader(showsPinned: context.viewState.expectsPinned)
                .frame(maxHeight: .infinity, alignment: .top)
        case .unavailable:
            SpiralEmptyState(symbol: .wifiSlash,
                             title: UntranslatedL10n.screenFeedUnavailableTitle,
                             message: UntranslatedL10n.screenFeedUnavailableMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .refresh) })
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.unavailable)
                .centredInScrollView()
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenFeedLoadFailedTitle,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .refresh) })
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.error)
                .centredInScrollView()
        case .loaded, .offline:
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topID)

                    if context.viewState.isOffline {
                        offlineBanner
                    }

                    if let pinned = context.viewState.visiblePinned {
                        // Concept A: its own card, set off by space rather than a hairline.
                        card(pinned, style: .pinned)
                            .accessibilityIdentifier(A11yIdentifiers.feedScreen.pinnedPost)
                            .padding(CompoundDesignTokens.space2X)
                    }

                    ForEach(context.viewState.pendingPosts) { pending in
                        FeedPostListCell {
                            FeedPendingPostRow(pending: pending,
                                               profile: context.viewState.ownProfile,
                                               mediaProvider: context.mediaProvider) {
                                context.send(viewAction: .retryPost(pending.key))
                            } discard: {
                                context.send(viewAction: .discardPost(pending.key))
                            }
                        }
                    }

                    if context.viewState.isEmpty {
                        SpiralEmptyState(symbol: .squareAndPencil,
                                         title: UntranslatedL10n.screenFeedEmptyTitle,
                                         message: UntranslatedL10n.screenFeedEmptyMessage)
                            .padding(.vertical, 48)
                            .accessibilityIdentifier(A11yIdentifiers.feedScreen.empty)
                    }

                    ForEach(context.viewState.visibleItems) { item in
                        FeedPostListCell {
                            card(item)
                        }
                    }

                    if let sentinel = context.viewState.sentinel {
                        sentinelView(sentinel)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .feedSoftTopEdge()
            // Latest is the one list with pull to refresh: "show new posts" (decision 289).
            .refreshable { context.send(viewAction: .refresh) }
            .feedSyncStatus(context.viewState.syncStatus)
            .onChange(of: context.viewState.scrollToTopRequest) {
                withAnimation { proxy.scrollTo(Self.topID, anchor: .top) }
            }
        }
    }

    private func card(_ item: FeedItem, style: FeedPostCard.Style = .list) -> some View {
        FeedPostCard(model: item.card,
                     isRevealed: context.viewState.revealedPostIDs.contains(item.id),
                     mediaProvider: context.mediaProvider,
                     style: style) { action in
            context.send(viewAction: .card(postID: item.id, action))
        }
    }

    private var offlineBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            CompoundIcon(\.offline, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(UntranslatedL10n.screenFeedOfflineBanner)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                Button(L10n.actionRetry) { context.send(viewAction: .refresh) }
                    .buttonStyle(.compound(.secondary, size: .small, isRaised: true)) // On the banner's grey (decision 329).
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.compound.bgSubtleSecondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.offlineBanner)
    }

    /// Brief 0083: the pill takes the title's place in the bar, while the list is what's showing.
    private var newPostsPill: FeedBarPill? {
        guard let title = context.viewState.newPostsPillTitle else { return nil }
        switch context.viewState.listState {
        case .loaded, .offline:
            let count = context.viewState.newPostsCount
            return FeedBarPill(title: title,
                               count: count >= FeedScreenViewModel.headCap ? "99+" : count.formatted()) { context.send(viewAction: .showNewPosts) }
        case .loading, .unavailable, .failed:
            return nil
        }
    }

    @ViewBuilder
    private func sentinelView(_ state: LoadMoreState) -> some View {
        switch state {
        case .failed:
            Button(UntranslatedL10n.screenAgentActivityLoadMoreFailed) { context.send(viewAction: .loadMore) }
                .buttonStyle(.compound(.tertiary, size: .medium))
                .padding(.vertical, 16)
        case .idle where context.viewState.isReadOnPaused:
            // The sentinel already appeared and would not ask again.
            Button(L10n.actionLoadMore) { context.send(viewAction: .loadMore) }
                .buttonStyle(.compound(.tertiary, size: .medium))
                .padding(.vertical, 16)
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(UntranslatedL10n.screenAgentActivityLoadMore)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .onAppear { context.send(viewAction: .loadMore) }
        }
    }
}

/// The person's own photo, or their monogram: the same one as the tab's and Settings', in a 44 pt circle of glass.
private struct FeedOwnPhotoLabel: View {
    let profile: UserProfile?
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        if Compound.supportsGlass {
            avatar
                .spiralGlass(in: Circle(), isInteractive: true)
        } else {
            avatar
        }
    }

    private var avatar: some View {
        LoadableAvatarImage(url: profile?.avatarURL,
                            name: profile?.displayName,
                            contentID: profile?.id ?? "",
                            avatarSize: .custom(SpiralAvatarSize.small),
                            mediaProvider: mediaProvider)
            .dynamicTypeSize(.large)
            .frame(width: CompoundDesignTokens.space11X, height: CompoundDesignTokens.space11X)
            .contentShape(.circle)
            .accessibilityHidden(true)
    }
}

/// The bell of Activity, with the unread activity and notices over it while there are some.
private struct FeedBellToolbarIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let unread: Int

    /// In dark the bar's glass lifts what it carries by about 25 in each channel: the critical fill (#D14545) showed as
    /// #E75B5B, 3.47:1 under the white count (step 5's audit). The red ramp's next darker step in dark shows as #BC2A3B,
    /// 5.94:1. Light keeps the critical fill (4.66:1 as shown).
    private var badgeFill: Color {
        colorScheme == .dark ? CompoundCoreColorTokens.red700 : .compound.bgCriticalPrimary
    }

    var body: some View {
        CompoundIcon(\.notifications)
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.compound.bodyXSSemibold)
                        .foregroundStyle(.compound.textOnSolidPrimary)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(badgeFill, in: .capsule)
                        .fixedSize()
                        .offset(x: 8, y: -6)
                }
            }
    }
}

// MARK: - Previews

struct FeedScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadedViewModel = makeViewModel(.success(FeedPage(items: [FeedPreviewData.textPost,
                                                                         FeedPreviewData.imagePost(count: 2),
                                                                         FeedPreviewData.sensitivePost],
        nextCursor: "next",
        pinned: FeedPreviewData.welcomePost)),
                                               newPosts: 3,
                                               unreadNotices: 1,
                                               unreadActivity: 2)
    /// Brief 0083: the kinds of post a feed holds side by side, for the layout question (292).
    static let variedPosts = [FeedPreviewData.engagedPost,
                              FeedPreviewData.imagePost(count: 1).withCounts(likes: 4, comments: 2),
                              FeedPreviewData.unsupportedPost,
                              FeedPreviewData.sensitivePost]
    static let variedViewModel = makeViewModel(.success(FeedPage(items: variedPosts, nextCursor: nil, pinned: FeedPreviewData.welcomePost)))
    static let emptyViewModel = makeViewModel(.success(FeedPage(items: [], nextCursor: nil, pinned: nil)))
    static let offlineViewModel = makeViewModel(.failure(.transport), cached: FeedPage(items: [FeedPreviewData.textPost], nextCursor: nil, pinned: nil))
    static let failedViewModel = makeViewModel(.failure(.transport))
    static let unavailableViewModel = makeViewModel(.failure(.unavailable))
    static let loadingViewModel = makeViewModel(.failure(.transport), answers: false)
    static let pendingViewModel = makeViewModel(.success(FeedPage(items: [FeedPreviewData.textPost], nextCursor: nil, pinned: nil)),
                                                failedPost: "Morning walk by the river, the first frost of the year.",
                                                syncState: .waiting(attempt: 1, isOffline: true))

    static var previews: some View {
        preview(loadedViewModel, name: "Loaded", expect: loadedViewModel.context.observe(\.viewState.newPostsCount).map { $0 == 3 })
        preview(variedViewModel, name: "Varied posts")
        preview(emptyViewModel, name: "Empty")
        preview(offlineViewModel, name: "Offline")
        preview(failedViewModel, name: "Failed")
        // Decision 330 correction: at the largest sizes the state scrolls, and Retry stays above the tab bar.
        preview(failedViewModel, name: "Failed AX3")
            .dynamicTypeSize(.accessibility3)
        preview(unavailableViewModel, name: "Unavailable")
        preview(pendingViewModel, name: "Post not sent, no connection",
                expect: pendingViewModel.context.observe(\.viewState.pendingPosts).map { $0.first?.delivery == .failed(.transport) })

        // The first page never comes: the preloader, as a slow load shows it.
        ElementNavigationStack {
            FeedScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
    }

    @ViewBuilder
    private static func preview(_ viewModel: FeedScreenViewModel, name: String, expect: (any AsyncSequence<Bool, Never>)? = nil) -> some View {
        ElementNavigationStack {
            FeedScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: expect ?? viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<FeedPage, FeedError>,
                              cached: FeedPage? = nil,
                              newPosts: Int = 0,
                              unreadNotices: Int = 0,
                              unreadActivity: Int = 0,
                              failedPost: String? = nil,
                              syncState: PlatformSyncConnectionState = .live,
                              answers: Bool = true) -> FeedScreenViewModel {
        let service = FeedServiceMock()
        if answers {
            service.latestCursorLimitReturnValue = result
        } else {
            // Both snapshot suites share the view model in one run, which can outlast a minute.
            service.latestCursorLimitClosure = { _, _ in
                try? await Task.sleep(for: .seconds(24 * 3600))
                return result
            }
        }
        service.cachedFirstPageReturnValue = cached
        service.noticesUnreadPublisher = Just(unreadNotices).eraseToAnyPublisher()
        service.activityUnreadPublisher = Just(unreadActivity).eraseToAnyPublisher()
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: unreadNotices))
        // A waiting stream reads the badges itself.
        service.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: unreadActivity))
        service.createPostTextIdempotencyKeyReturnValue = .failure(.transport)
        service.draftReturnValue = nil
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        let store = FeedStore(feedService: service, currentUserID: "@me:spiral.md")
        store.connectionState = syncState
        let viewModel = FeedScreenViewModel(feedService: service,
                                            engagement: FeedEngagementController(store: store, userIndicatorController: UserIndicatorControllerMock()),
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()),
                                            userIndicatorController: UserIndicatorControllerMock())
        if newPosts > 0 || failedPost != nil {
            Task {
                await viewModel.loadFirstPage()
                store.apply((0..<newPosts).map { .postPublished(postID: "new-\($0)", authorID: "@olena:spiral.md") })
                if let failedPost {
                    await store.publishPost(text: failedPost, idempotencyKey: UUID())
                }
            }
        }
        return viewModel
    }
}
