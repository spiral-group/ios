//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: Activity behind the feed's bell.
//

import Combine
import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct FeedActivityScreen: View {
    @Bindable var context: FeedActivityScreenViewModel.Context

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if context.viewState.showsFromSpiral {
                    FeedFromSpiralRow(unread: context.viewState.unreadNotices ?? 0) { context.send(viewAction: .openNotices) }
                    FeedActivitySeparator()
                }
                content
            }
        }
        .feedSoftTopEdge()
        // No pull to refresh: the sync reads it again (decision 289).
        .feedSyncStatus(context.viewState.syncStatus)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .feedBarTitle(UntranslatedL10n.screenFeedActivityTitle)
        .onAppear { context.send(viewAction: .appeared) }
        .onDisappear { context.send(viewAction: .disappeared) }
    }

    @ViewBuilder
    private var content: some View {
        switch context.viewState.listState {
        case .loading:
            // Decision 330: the activity's rows as placeholders, after a short delay.
            SpiralPreloader(label: L10n.commonLoading) {
                SpiralPlaceholderRows(count: 5, leading: .avatar(Avatars.Size.user(on: .timeline).value))
            }
        case .unavailable:
            SpiralEmptyState(symbol: .wifiSlash,
                             title: UntranslatedL10n.screenFeedUnavailableTitle,
                             message: UntranslatedL10n.screenFeedUnavailableMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .padding(.vertical, 48)
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenFeedActivityLoadFailedTitle,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .padding(.vertical, 48)
                .accessibilityIdentifier(A11yIdentifiers.feedActivityScreen.error)
        case .loaded:
            if context.viewState.isEmpty {
                SpiralEmptyState(symbol: .faceSmiling,
                                 title: UntranslatedL10n.screenFeedActivityEmptyTitle,
                                 message: UntranslatedL10n.screenFeedActivityEmptyMessage)
                    .padding(.vertical, 48)
                    .accessibilityIdentifier(A11yIdentifiers.feedActivityScreen.empty)
            }
            ForEach(context.viewState.items) { item in
                FeedActivityRow(item: item,
                                isRevealed: context.viewState.revealedEntryIDs.contains(item.id),
                                mediaProvider: context.mediaProvider,
                                open: { context.send(viewAction: .open(entryID: item.id)) },
                                reveal: { context.send(viewAction: .reveal(entryID: item.id)) })
                if item.id != context.viewState.items.last?.id {
                    FeedActivitySeparator()
                }
            }
            if let sentinel = context.viewState.sentinel {
                sentinelView(sentinel)
            }
        }
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

/// iOS's hairline between two rows, inset to where the rows' text starts after the marker column and the avatar.
private struct FeedActivitySeparator: View {
    @ScaledMetric(relativeTo: .subheadline) private var markerSize = 10.0

    var body: some View {
        SpiralCardSeparator(leadingInset: CompoundDesignTokens.space1_5X + min(markerSize, 14) + CompoundDesignTokens.space2X
            + SpiralAvatarSize.small + CompoundDesignTokens.space3X)
    }
}

/// The moderation notices, a tap away: Spiral's decisions about the person's posts and their reports.
private struct FeedFromSpiralRow: View {
    let unread: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 0) {
                HomeScreenRoomUnreadMarker(isShown: false, isHighlighted: false)
                CompoundIcon(\.notifications, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconSecondary)
                    .frame(width: SpiralAvatarSize.small, height: SpiralAvatarSize.small)
                    .background(.compound.bgSubtleSecondary, in: .circle)
                    .padding(.trailing, CompoundDesignTokens.space3X)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(UntranslatedL10n.screenFeedFromSpiralTitle)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                    Text(UntranslatedL10n.screenFeedFromSpiralSubtitle)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                Spacer(minLength: CompoundDesignTokens.space2X)
                if unread > 0 {
                    // Brief 0083: the count on Chats' tinted badge (decision 333), where it was Element's red.
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.compound.bodySMSemibold)
                        .foregroundStyle(.compound.textBadgeAccent)
                        .padding(.horizontal, CompoundDesignTokens.space2X)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(.compound.bgBadgeAccent, in: .capsule)
                        .accessibilityLabel(UntranslatedL10n.a11yFeedNoticesUnread(unread))
                }
                CompoundIcon(\.chevronRight, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconTertiary)
                    .padding(.leading, CompoundDesignTokens.space2X)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yIdentifiers.feedActivityScreen.fromSpiral)
    }
}

/// One entry: who, what, about which post, when; a tap opens the post (at the comment).
private struct FeedActivityRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: FeedActivityItem
    let isRevealed: Bool
    let mediaProvider: MediaProviderProtocol?
    let open: () -> Void
    let reveal: () -> Void

    private var showsPreviews: Bool {
        !item.entry.isSensitive || isRevealed
    }

    /// Brief 0083: the unread dot leads in Chats' marker column (decision 333), beside the avatar; it trailed the row.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(spacing: 0) {
                HomeScreenRoomUnreadMarker(isShown: item.entry.isUnread, isHighlighted: true)
                avatar
            }
            .padding(.trailing, CompoundDesignTokens.space3X)
            VStack(alignment: .leading, spacing: 2) {
                // Brief 0083: what happened and when on one line, the time as quiet as on a post. At accessibility
                // sizes the time goes under it, as in Chats, so the words aren't crushed to a letter a line.
                FeedTitleAndTime(isStacked: dynamicTypeSize.isAccessibilitySize) {
                    Text(showsPreviews ? item.title : item.hiddenTitle)
                        .font(item.entry.isUnread ? .compound.bodyLGSemibold : .compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(3)
                } time: {
                    FeedShortTime(date: item.entry.at)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                if let context = item.context {
                    Text(context)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                if showsPreviews {
                    Text(item.entry.postPreview)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 8) {
                        Text(UntranslatedL10n.screenFeedSensitiveTitle)
                            .font(.compound.bodySM)
                            .foregroundStyle(.compound.textSecondary)
                        Button(UntranslatedL10n.screenFeedSensitiveShow, action: reveal)
                            .buttonStyle(.compound(.tertiary, size: .small))
                    }
                }
            }
        }
        .padding(.trailing, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel(isRevealed: isRevealed))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityActions {
            if !showsPreviews {
                Button(UntranslatedL10n.screenFeedSensitiveShow, action: reveal)
            }
        }
        .accessibilityIdentifier(A11yIdentifiers.feedActivityScreen.entry)
    }

    private var avatar: some View {
        let actor = item.entry.actors.first
        return LoadableAvatarImage(url: actor?.avatarURL,
                                   name: actor?.displayName,
                                   contentID: actor?.userID ?? item.id,
                                   avatarSize: .user(on: .timeline),
                                   mediaProvider: mediaProvider)
            .overlay(alignment: .bottomTrailing) { kindBadge.offset(x: 6, y: 6) } // Brief 0083: clear of the monogram's letter.
            .accessibilityHidden(true)
    }

    private var kindBadge: some View {
        Group {
            switch item.entry.kind {
            case .like:
                // Compound has no heart; a like reads as one everywhere else.
                Image(systemName: "heart.fill")
                    // swiftlint:disable:next spiral_raw_font - predates the rule
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.compound.iconOnSolidPrimary)
                    .frame(width: 18, height: 18)
                    .background(.compound.iconCriticalPrimary, in: .circle)
            case .comment, .reply:
                CompoundIcon(\.chatSolid, size: .custom(11), relativeTo: .compound.bodyXS)
                    .foregroundStyle(.compound.iconOnSolidPrimary)
                    .frame(width: 18, height: 18)
                    .background(.compound.iconAccentPrimary, in: .circle)
            }
        }
        .overlay { Circle().stroke(.compound.bgCanvasDefault, lineWidth: 2) }
    }
}

// MARK: - Previews

struct FeedActivityScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadedViewModel = makeViewModel(.success(FeedActivityPage(items: FeedPreviewData.activity, nextCursor: nil, unread: 2)), unreadNotices: 1)
    static let emptyViewModel = makeViewModel(.success(FeedActivityPage(items: [], nextCursor: nil, unread: 0)))
    static let failedViewModel = makeViewModel(.failure(.transport))
    static let unavailableViewModel = makeViewModel(.failure(.unavailable))

    static var previews: some View {
        preview(loadedViewModel, name: "Activity")
        preview(loadedViewModel, name: "Activity AX5")
            .dynamicTypeSize(.accessibility5)
        preview(emptyViewModel, name: "Empty")
        preview(failedViewModel, name: "Failed")
        preview(unavailableViewModel, name: "Unavailable")
    }

    private static func preview(_ viewModel: FeedActivityScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedActivityScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<FeedActivityPage, FeedError>, unreadNotices: Int = 0) -> FeedActivityScreenViewModel {
        let service = FeedServiceMock()
        service.activityCursorLimitReturnValue = result
        // The seen mark is never answered in a preview: its dots stay.
        service.markActivitySeenUpToReturnValue = .failure(.transport)
        service.noticesUnreadPublisher = Just(unreadNotices).eraseToAnyPublisher()
        let notices = unreadNotices > 0 ? Array(FeedPreviewData.notices.prefix(1)) : []
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: notices, nextCursor: nil, unread: unreadNotices))
        return FeedActivityScreenViewModel(feedService: service,
                                           store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                           mediaProvider: MediaProviderMock(.init()),
                                           userIndicatorController: UserIndicatorControllerMock())
    }
}
