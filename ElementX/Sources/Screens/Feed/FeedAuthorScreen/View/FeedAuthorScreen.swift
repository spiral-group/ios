//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Combine
import Compound
import SpiralTokens
import SwiftUI

struct FeedAuthorScreen: View {
    /// The band's height, running under the bar.
    private static let bandHeight = CompoundDesignTokens.space40X

    @Bindable var context: FeedAuthorScreenViewModel.Context

    /// The bar's title stays empty until the name has scrolled under it, as on the Portrait page.
    @State private var isTitleInBar = false
    @ScaledMetric(relativeTo: .body) private var menuSide = CompoundDesignTokens.space8X
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var author: FeedAuthor {
        context.viewState.author
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                top
                Divider()
                    .padding(.top, CompoundDesignTokens.space4X)
                posts
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea(.container, edges: .top) // The band runs under the bar.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.bandHeight
        } action: { _, isPastBand in
            isTitleInBar = isPastBand
        }
        .feedSoftTopEdge()
        .feedSyncStatus(context.viewState.syncStatus)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.actionClose) { context.send(viewAction: .dismiss) }
                    // iOS 18 draws it bare on the band, where the accent reads too faintly.
                    .tint(Compound.supportsGlass ? nil : .compound.textPrimary)
            }
            if isTitleInBar {
                FeedBarTitle(title: author.displayName, isOverContent: true)
            }
        }
        .environment(\.shouldAutomaticallyLoadImages, !context.viewState.hidesMedia)
        .interactiveQuickLook(item: $context.mediaPreviewItem, allowEditing: false)
        .alert(item: $context.alertInfo)
        .onAppear { context.send(viewAction: .appeared) }
        .onDisappear { context.send(viewAction: .disappeared) }
    }

    /// VoiceOver reads who this is before what can be done: the actions are drawn first, on the band.
    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            band
            header
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
    }

    /// The Portrait page's field as a band (344), which doesn't stretch: a pull moves the sheet. The photo sits on its lower
    /// edge at the leading margin, the actions opposite.
    private var band: some View {
        ZStack(alignment: .bottomLeading) {
            NativeCallBackdrop(photoURL: author.avatarURL, contentID: author.userID, mediaProvider: context.mediaProvider, tone: .wash)
                .frame(height: Self.bandHeight)
                .clipped()
                .padding(.bottom, SpiralAvatarSize.large / 2)
            HStack(alignment: .bottom, spacing: CompoundDesignTokens.space2X) {
                LoadableAvatarImage(url: author.avatarURL,
                                    name: author.displayName,
                                    contentID: author.userID,
                                    avatarSize: .custom(SpiralAvatarSize.large),
                                    mediaProvider: context.mediaProvider)
                    .dynamicTypeSize(.large) // The words below carry the scaling.
                    .padding(CompoundDesignTokens.space1X)
                    .background(.compound.bgCanvasDefault, in: .circle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if !context.viewState.isOwnProfile, !dynamicTypeSize.isAccessibilitySize {
                    actions
                }
            }
            // The photo's ring takes the last 4 pt of the margin; the actions keep all of theirs.
            .padding(.leading, CompoundDesignTokens.space3X)
            .padding(.trailing, CompoundDesignTokens.space4X)
        }
        .frame(height: Self.bandHeight + SpiralAvatarSize.large / 2)
    }

    /// Message opposite the photo; Report and Block behind "…", a tap further from a stranger's page.
    /// The official account has Report alone.
    private var actions: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            if context.viewState.isBlocked {
                Text(UntranslatedL10n.screenFeedAuthorBlocked)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textSecondary)
            }
            if context.viewState.canMessage {
                Button(L10n.actionMessage) { context.send(viewAction: .message) }
                    .buttonStyle(.compound(.primary, size: .small))
                    .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.message)
            }
            Menu {
                Button { context.send(viewAction: .report) } label: {
                    Label(L10n.actionReport, icon: \.chatProblem)
                }
                .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.report)
                if context.viewState.canBlock, !context.viewState.isBlocked {
                    Button(role: .destructive) { context.send(viewAction: .block) } label: {
                        Label(UntranslatedL10n.screenFeedAuthorBlock, icon: \.block)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.block)
                } else if context.viewState.canBlock {
                    // One blocked elsewhere keeps the way back here too.
                    Button { context.send(viewAction: .unblock) } label: {
                        Label(L10n.screenDmDetailsUnblockAlertAction, icon: \.block)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.unblock)
                }
            } label: {
                CompoundIcon(\.overflowHorizontal, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconPrimary)
                    .frame(width: menuSide, height: menuSide)
                    .background(.compound.bgSubtleSecondary, in: .circle)
                    .padding(CompoundDesignTokens.space1_5X)
                    .contentShape(.rect)
                    .accessibilityLabel(UntranslatedL10n.screenProfileActionMore)
            }
            .padding(-CompoundDesignTokens.space1_5X)
            .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.more)
        }
        .padding(.bottom, CompoundDesignTokens.space1X)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            Text(author.displayName)
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let userID = author.shownUserID {
                Text(userID)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            if author.isOfficial {
                FeedOfficialLabel()
            }
            if let bio = author.bio, !bio.isEmpty {
                // Plain text: links in a bio are not tappable (255).
                Text(verbatim: bio)
                    .font(.compound.bodyLG)
                    .foregroundStyle(.compound.textPrimary)
                    .padding(.top, CompoundDesignTokens.space2X)
                    .accessibilityIdentifier(A11yIdentifiers.feedAuthorScreen.bio)
            }
            // At accessibility sizes the row has no room beside the photo.
            if !context.viewState.isOwnProfile, dynamicTypeSize.isAccessibilitySize {
                actions
                    .padding(.top, CompoundDesignTokens.space2X)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.top, CompoundDesignTokens.space3X)
    }

    @ViewBuilder
    private var posts: some View {
        switch context.viewState.postsState {
        case .loading:
            FeedPostsPreloader(count: 2)
        case .notAvailable:
            FeedNoticeBox(text: UntranslatedL10n.screenFeedAuthorNotAvailable)
                .padding(CompoundDesignTokens.space4X)
        case .unavailable:
            FeedNoticeBox(text: UntranslatedL10n.screenFeedUnavailableTitle)
                .padding(CompoundDesignTokens.space4X)
        case .failed:
            VStack(spacing: 8) {
                Text(UntranslatedL10n.screenFeedAuthorPostsLoadFailed)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                Button(L10n.actionRetry) { context.send(viewAction: .retry) }
                    .buttonStyle(.compound(.secondary, size: .small))
            }
            .padding(.vertical, 24)
        case .loaded where context.viewState.isEmpty:
            Text(UntranslatedL10n.screenFeedAuthorNoPosts)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
                .padding(.vertical, 24)
        case .loaded(let items, _):
            ForEach(items) { item in
                let label = Self.ownStateLabel(item.post)
                FeedPostListCell {
                    if let label {
                        FeedPostMarker(title: label, icon: \.time)
                    }
                    FeedPostCard(model: item.card,
                                 isRevealed: context.viewState.revealedPostIDs.contains(item.id),
                                 mediaProvider: context.mediaProvider,
                                 showsLikers: false,
                                 isMarked: label != nil) { action in
                        context.send(viewAction: .card(postID: item.id, action))
                    }
                }
            }
            if let sentinel = context.viewState.sentinel {
                switch sentinel {
                case .failed:
                    Button(UntranslatedL10n.screenAgentActivityLoadMoreFailed) { context.send(viewAction: .loadMore) }
                        .buttonStyle(.compound(.tertiary, size: .medium))
                        .padding(.vertical, 16)
                case .idle where context.viewState.isReadOnPaused:
                    Button(L10n.actionLoadMore) { context.send(viewAction: .loadMore) }
                        .buttonStyle(.compound(.tertiary, size: .medium))
                        .padding(.vertical, 16)
                default:
                    ProgressView()
                        .padding(.vertical, 16)
                        .onAppear { context.send(viewAction: .loadMore) }
                }
            }
        }
    }
}

extension FeedAuthorScreen {
    /// On the person's own sheet, a post others can't see says so (lane I2).
    static func ownStateLabel(_ post: FeedPost) -> String? {
        guard post.viewer.isAuthor else { return nil }
        switch post.state {
        case .held: return UntranslatedL10n.screenFeedPostHeldLabel
        case .removed: return UntranslatedL10n.screenFeedPostRemovedLabel
        case .visible, .hiddenAuthor, .other: return nil
        }
    }
}

// MARK: - Previews

struct FeedAuthorScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let annViewModel = makeViewModel(author: FeedPreviewData.ann,
                                            result: .success(FeedPage(items: [FeedPreviewData.textPost, FeedPreviewData.imagePost(count: 1)], nextCursor: nil, pinned: nil)))
    static let officialViewModel = makeViewModel(author: FeedPreviewData.spiral,
                                                 result: .success(FeedPage(items: [FeedPreviewData.officialPost], nextCursor: nil, pinned: nil)))
    static let noPostsViewModel = makeViewModel(author: FeedPreviewData.bob, result: .success(FeedPage(items: [], nextCursor: nil, pinned: nil)))
    static let ownViewModel = makeViewModel(author: FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false),
                                            result: .success(FeedPage(items: [], nextCursor: nil, pinned: nil)))
    static let ownPostsViewModel = makeViewModel(author: me,
                                                 result: .success(FeedPage(items: [FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000301", author: me, minutesAgo: 3,
                                                                                                        text: "Waiting for a moderator", state: .held, heldReason: .filter, isAuthor: true),
                                                                                   FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000302", author: me, minutesAgo: 90,
                                                                                                        text: "Out in the feed", isAuthor: true)],
                                                                           nextCursor: nil, pinned: nil)))
    private static var me: FeedAuthor {
        FeedAuthor(userID: "@me:spiral.md", name: "Me", avatarURL: nil, bio: nil, isOfficial: false, isNameWithheld: false)
    }

    static let notAvailableViewModel = makeViewModel(author: FeedPreviewData.bob, result: .failure(.notFound))
    static let withheldViewModel = makeViewModel(author: FeedPreviewData.withheld,
                                                 result: .success(FeedPage(items: [FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000303",
                                                                                                        author: FeedPreviewData.withheld, minutesAgo: 8,
                                                                                                        text: "A post by someone whose name is withheld")],
                                                                           nextCursor: nil, pinned: nil)))

    static var previews: some View {
        preview(annViewModel, name: "Author")
        preview(officialViewModel, name: "Official")
        preview(noPostsViewModel, name: "No posts")
        preview(ownViewModel, name: "Own profile")
        preview(ownPostsViewModel, name: "Own posts")
        preview(notAvailableViewModel, name: "Not available")
        preview(withheldViewModel, name: "Name withheld")
    }

    private static func preview(_ viewModel: FeedAuthorScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedAuthorScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.postsState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(author: FeedAuthor, result: Result<FeedPage, FeedError>) -> FeedAuthorScreenViewModel {
        let service = FeedServiceMock()
        service.authorPostsUserIDCursorLimitReturnValue = result
        service.ownPostsCursorLimitReturnValue = result
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        return FeedAuthorScreenViewModel(author: author,
                                         feedService: service,
                                         engagement: FeedEngagementController(store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                                                              userIndicatorController: UserIndicatorControllerMock()),
                                         clientProxy: clientProxy,
                                         mediaProvider: MediaProviderMock(.init()),
                                         userIndicatorController: UserIndicatorControllerMock())
    }
}
