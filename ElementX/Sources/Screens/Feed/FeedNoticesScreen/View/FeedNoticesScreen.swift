//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082).
//

import Compound
import SpiralComponents
import SwiftUI

struct FeedNoticesScreen: View {
    @Bindable var context: FeedNoticesScreenViewModel.Context

    var body: some View {
        content
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .feedSyncStatus(context.viewState.syncStatus)
            .feedBarTitle(UntranslatedL10n.screenFeedFromSpiralTitle)
            .onAppear { context.send(viewAction: .appeared) }
            .onDisappear { context.send(viewAction: .disappeared) }
    }

    @ViewBuilder
    private var content: some View {
        switch context.viewState.listState {
        case .loading:
            // Decision 330: the notices' rows as placeholders, after a short delay.
            SpiralPreloader(label: L10n.commonLoading) {
                SpiralPlaceholderRows(count: 4, leading: .icon)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .unavailable:
            SpiralEmptyState(symbol: .wifiSlash,
                             title: UntranslatedL10n.screenFeedUnavailableTitle,
                             message: UntranslatedL10n.screenFeedUnavailableMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .centredInScrollView()
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenFeedNoticesLoadFailedTitle,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .accessibilityIdentifier(A11yIdentifiers.feedNoticesScreen.error)
                .centredInScrollView()
        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if context.viewState.isEmpty {
                    SpiralEmptyState(symbol: .bell,
                                     title: UntranslatedL10n.screenFeedNoticesEmptyTitle,
                                     message: UntranslatedL10n.screenFeedNoticesEmptyMessage)
                        .padding(.vertical, 48)
                        .accessibilityIdentifier(A11yIdentifiers.feedNoticesScreen.empty)
                }
                ForEach(context.viewState.items) { item in
                    FeedNoticeRow(item: item) { postID in
                        context.send(viewAction: .openPost(postID: postID))
                    }
                    .onAppear { context.send(viewAction: .noticeAppeared(noticeID: item.id)) }
                    if item.id != context.viewState.items.last?.id {
                        FeedNoticeSeparator()
                    }
                }
                if let sentinel = context.viewState.sentinel {
                    sentinelView(sentinel)
                }
            }
        }
        .feedSoftTopEdge()
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

/// Brief 0083: iOS's hairline between two notices, inset to their text after Chats' marker column (6 + the marker,
/// which scales from 10 to 14 pt, + 8 pt).
private struct FeedNoticeSeparator: View {
    @ScaledMetric(relativeTo: .subheadline) private var markerSize = 10.0

    var body: some View {
        SpiralCardSeparator(leadingInset: CompoundDesignTokens.space1_5X + min(markerSize, 14) + CompoundDesignTokens.space2X)
    }
}

/// One notice in full: its title, when, and the statement. Brief 0083: the unread dot leads in Chats' marker column
/// (decision 333), and the notice's text keeps one column whether or not it is read.
private struct FeedNoticeRow: View {
    @ScaledMetric(relativeTo: .body) private var titleCapHeight = 12.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: FeedNoticeItem
    let openPost: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HomeScreenRoomUnreadMarker(isShown: !item.notice.isRead, isHighlighted: true)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + titleCapHeight / 2 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
                header
                FeedNoticeStatementView(content: item.content)
                if let postID = item.content.postID {
                    Button(UntranslatedL10n.screenFeedNoticeViewPost) { openPost(postID) }
                        .buttonStyle(.compound(.secondary, size: .small))
                        .padding(.top, CompoundDesignTokens.space1X)
                }
            }
        }
        .padding(.trailing, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space3X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yIdentifiers.feedNoticesScreen.notice)
    }

    private var header: some View {
        // Brief 0083: what happened and when on one line, as on Activity; at accessibility sizes the time goes under it.
        FeedTitleAndTime(isStacked: dynamicTypeSize.isAccessibilitySize) {
            Text(item.content.title)
                .font(item.notice.isRead ? .compound.bodyLG : .compound.bodyLGSemibold)
                .foregroundStyle(.compound.textPrimary)
        } time: {
            FeedShortTime(date: item.notice.createdAt)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(item.notice.isRead ? "" : UntranslatedL10n.a11yFeedNoticeUnread)
    }
}

// MARK: - Previews

struct FeedNoticesScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadedViewModel = makeViewModel(.success(FeedNoticePage(items: FeedPreviewData.notices, nextCursor: nil, unread: 2)))
    static let emptyViewModel = makeViewModel(.success(FeedNoticePage(items: [], nextCursor: nil, unread: 0)))
    static let failedViewModel = makeViewModel(.failure(.transport))
    static let unavailableViewModel = makeViewModel(.failure(.unavailable))

    static var previews: some View {
        preview(loadedViewModel, name: "Notices")
        preview(loadedViewModel, name: "Notices AX5")
            .dynamicTypeSize(.accessibility5)
        preview(emptyViewModel, name: "Empty")
        preview(failedViewModel, name: "Failed")
        preview(unavailableViewModel, name: "Unavailable")
    }

    private static func preview(_ viewModel: FeedNoticesScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            FeedNoticesScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<FeedNoticePage, FeedError>) -> FeedNoticesScreenViewModel {
        let service = FeedServiceMock()
        service.noticesCursorLimitLanguageReturnValue = result
        // Previews keep their unread dots: the read is never answered.
        service.markNoticeReadIdReturnValue = .failure(.transport)
        return FeedNoticesScreenViewModel(feedService: service,
                                          store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          language: "en")
    }
}
