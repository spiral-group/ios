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

struct FeedPostScreen: View {
    @Bindable var context: FeedPostScreenViewModel.Context

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var isCommentFieldFocused: Bool
    /// The focused comment is scrolled to once, when it is first read.
    @State private var hasScrolledToFocusedComment = false

    var body: some View {
        content
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .feedSyncStatus(context.viewState.syncStatus)
            .feedBarTitle(UntranslatedL10n.screenFeedPostTitle)
            // As a room hides it, on compact only: the comment field is this page's bar.
            .toolbarVisibility(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
            .environment(\.shouldAutomaticallyLoadImages, !context.viewState.hidesMedia)
            .interactiveQuickLook(item: $context.mediaPreviewItem, allowEditing: false)
            .toolbar { toolbar }
            .alert(item: $context.alertInfo)
            // An alert waiting on the sheet shows only after it has closed.
            .sheet(isPresented: $context.isPresentingRules,
                   onDismiss: { context.send(viewAction: .rulesSheetDismissed) },
                   content: {
                       FeedRulesSheet(isAccepting: context.viewState.isAcceptingRules,
                                      acceptFailed: context.viewState.rulesAcceptFailed,
                                      accept: { context.send(viewAction: .acceptRules) },
                                      decline: { context.send(viewAction: .declineRules) },
                                      agreeTitle: UntranslatedL10n.screenFeedRulesAgreeComment)
                   })
            .onChange(of: context.viewState.focusCommentFieldRequest) { isCommentFieldFocused = true }
            .onAppear { context.send(viewAction: .appeared) }
            .onDisappear { context.send(viewAction: .disappeared) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let state = context.viewState
        if state.canDelete || state.canHide || state.canToggleComments || state.canReport {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if state.canToggleComments, let post = state.post {
                        Button { context.send(viewAction: .setCommentsEnabled(!post.commentsEnabled)) } label: {
                            Label(post.commentsEnabled ? UntranslatedL10n.screenFeedCommentsTurnOff : UntranslatedL10n.screenFeedCommentsTurnOn,
                                  icon: \.chat)
                        }
                    }
                    if state.canHide {
                        Button { context.send(viewAction: .hide) } label: {
                            Label(UntranslatedL10n.screenFeedHideAction, icon: \.visibilityOff)
                        }
                    }
                    if state.canReport {
                        Button { context.send(viewAction: .report) } label: {
                            Label(UntranslatedL10n.screenFeedReportPostAction, icon: \.chatProblem)
                        }
                        .accessibilityIdentifier(A11yIdentifiers.feedScreen.report)
                    }
                    if state.canDelete {
                        Button(role: .destructive) { context.send(viewAction: .delete) } label: {
                            Label(UntranslatedL10n.screenFeedPostDelete, icon: \.delete)
                        }
                        .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.deletePost)
                    }
                } label: {
                    CompoundIcon(\.overflowHorizontal)
                        .accessibilityLabel(UntranslatedL10n.a11yFeedPostOptions)
                }
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.postMenu)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch context.viewState.visibleLoadState {
        case .loading:
            FeedPostsPreloader(count: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded(let item):
            ScrollViewReader { proxy in
                comments(item)
                    .onChange(of: context.viewState.visibleComments.map(\.id), initial: true) { _, ids in
                        guard !hasScrolledToFocusedComment, let focused = context.viewState.focusedCommentID, ids.contains(focused) else { return }
                        hasScrolledToFocusedComment = true
                        withAnimation { proxy.scrollTo(focused, anchor: .center) }
                    }
            }
        case .notAvailable:
            SpiralEmptyState(symbol: .eyeSlash,
                             title: UntranslatedL10n.screenFeedPostNotAvailableTitle,
                             message: UntranslatedL10n.screenFeedPostNotAvailableMessage)
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.postNotAvailable)
                .centredInScrollView()
        case .unavailable:
            SpiralEmptyState(symbol: .wifiSlash,
                             title: UntranslatedL10n.screenFeedUnavailableTitle,
                             message: UntranslatedL10n.screenFeedUnavailableMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .centredInScrollView()
        case .failed:
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenFeedPostLoadFailedTitle,
                             message: UntranslatedL10n.screenFeedLoadFailedMessage,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retry) })
                .centredInScrollView()
        }
    }

    private func comments(_ item: FeedItem) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if context.viewState.isHidden {
                    FeedHiddenNoticeBox { context.send(viewAction: .unhide) }
                        .padding([.horizontal, .top], 16)
                }
                if let notice = context.viewState.authorNotice {
                    FeedAuthorNoticeBox(text: notice,
                                        statement: context.viewState.authorStatement,
                                        retryStatement: { context.send(viewAction: .retryStatement) },
                                        openNotices: { context.send(viewAction: .openNotices) },
                                        delete: context.viewState.authorNoticeOffersDelete ? { context.send(viewAction: .delete) } : nil)
                        .padding([.horizontal, .top], 16)
                }
                FeedPostCard(model: item.card,
                             isRevealed: context.viewState.isRevealed,
                             mediaProvider: context.mediaProvider,
                             style: .opened) { action in
                    context.send(viewAction: .card(action))
                }
                if context.viewState.showsComments {
                    Divider()
                    FeedCommentsSection(context: context)
                }
            }
        }
        .feedSoftEdges()
        .scrollDismissesKeyboard(.interactively)
        .backportSafeAreaBar(edge: .bottom, spacing: 0) { commentField }
    }

    @ViewBuilder private var commentField: some View {
        if context.viewState.canComment {
            FeedCommentComposer(context: context, isFocused: $isCommentFieldFocused)
        }
    }
}

/// What only the author sees on a held, removed or sensitive post: what
/// happened, the statement of reasons from their notices (lane I3 on B4), and
/// Delete on a post only they see (lane I2).
private struct FeedAuthorNoticeBox: View {
    /// Brief 0083: a small tertiary button's label sits this far into its capsule; pulled back by it, the label
    /// lines up with "Why?" and the text above.
    static let tertiaryInset = CompoundDesignTokens.space4X
    /// `bgSubtleSecondary`'s grey in light. In dark it's one step lower: on `bgSubtleSecondary`, "Why?" read 3.82:1 and Delete 3.99:1.
    static let fill = Color.compound.bgCanvasDisabled

    let text: String
    let statement: FeedPostStatementState
    let retryStatement: () -> Void
    let openNotices: () -> Void
    let delete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
                .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.heldNotice)
            statementView
            if let delete {
                Button(role: .destructive, action: delete) {
                    Text(UntranslatedL10n.screenFeedPostDelete)
                }
                .buttonStyle(.compound(.tertiary, size: .small))
                .padding(.leading, -Self.tertiaryInset)
                .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.deletePost)
                // 12 pt from a small button above it (Open notices, Retry): each tap area reaches 6 pt past its capsule.
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CompoundDesignTokens.space3X)
        .background(FeedAuthorNoticeBox.fill, in: .rect(cornerRadius: SpiralRadius.block))
    }

    @ViewBuilder
    private var statementView: some View {
        switch statement {
        case .none:
            EmptyView()
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded(let content):
            // No statement among the latest notices is not "no reasons": the notices screen still holds them.
            if let content {
                FeedNoticeStatementView(content: content)
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.postStatement)
            }
            Button(UntranslatedL10n.screenFeedNoticesOpen, action: openNotices)
                .buttonStyle(.compound(.tertiary, size: .small))
                .padding(.leading, -Self.tertiaryInset)
        case .failed:
            HStack(spacing: 8) {
                Text(UntranslatedL10n.screenFeedPostStatementLoadFailed)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                Button(L10n.actionRetry, action: retryStatement)
                    .buttonStyle(.compound(.tertiary, size: .small))
            }
        }
    }
}

/// A post the person hid: still readable here, left out of their lists (lane I3).
private struct FeedHiddenNoticeBox: View {
    let unhide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UntranslatedL10n.screenFeedHiddenNotice)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)
            Button(UntranslatedL10n.screenFeedUnhideAction, action: unhide)
                .buttonStyle(.compound(.tertiary, size: .small))
                .padding(.leading, -FeedAuthorNoticeBox.tertiaryInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CompoundDesignTokens.space3X)
        .background(FeedAuthorNoticeBox.fill, in: .rect(cornerRadius: SpiralRadius.block))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.hiddenNotice)
    }
}

// MARK: - Previews

struct FeedPostScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadedViewModel = makeViewModel(.success(FeedPreviewData.imagePost(count: 3)))
    static let heldViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000201",
                                                                           author: FeedPreviewData.ann,
                                                                           minutesAgo: 2,
                                                                           text: "Waiting for a moderator",
                                                                           state: .held,
                                                                           heldReason: .filter,
                                                                           isAuthor: true)))
    static let ownViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000202",
                                                                          author: FeedPreviewData.ann,
                                                                          minutesAgo: 4,
                                                                          text: "My own post, which I can delete",
                                                                          isAuthor: true)))
    static let removedViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000203",
                                                                              author: FeedPreviewData.ann,
                                                                              minutesAgo: 60,
                                                                              text: "Removed by a moderator",
                                                                              state: .removed,
                                                                              isAuthor: true)))
    static let statementFailedViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000203",
                                                                                      author: FeedPreviewData.ann,
                                                                                      minutesAgo: 60,
                                                                                      text: "Removed by a moderator",
                                                                                      state: .removed,
                                                                                      isAuthor: true)),
                                                        notices: .failure(.transport))
    /// The notice is not among the latest ones: no statement, but the way to the notices.
    static let statementMissingViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000203",
                                                                                       author: FeedPreviewData.ann,
                                                                                       minutesAgo: 60,
                                                                                       text: "Removed by a moderator",
                                                                                       state: .removed,
                                                                                       isAuthor: true)),
                                                         notices: .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0)))
    /// Decision 278: the filter marked the author's post sensitive at publish.
    static let sensitiveViewModel = makeViewModel(.success(FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000204",
                                                                                author: FeedPreviewData.ann,
                                                                                minutesAgo: 1,
                                                                                text: "Marked as sensitive by the filter",
                                                                                isSensitive: true,
                                                                                isAuthor: true)))
    static let notAvailableViewModel = makeViewModel(.failure(.notFound))
    static let failedViewModel = makeViewModel(.failure(.transport))
    // Lane I3.
    static let commentsViewModel = makeViewModel(.success(FeedPreviewData.engagedPost), comments: .success(FeedPreviewData.commentPage))
    static let noCommentsViewModel = makeViewModel(.success(FeedPreviewData.textPost), comments: .success(FeedCommentPage(items: [], nextCursor: nil)))
    static let commentsOffViewModel = makeViewModel(.success(FeedPreviewData.engagedPost.withCommentsEnabled(false)))
    static let commentsFailedViewModel = makeViewModel(.success(FeedPreviewData.textPost), comments: .failure(.transport))
    static let hiddenViewModel = makeViewModel(.success(FeedPreviewData.hiddenPost), comments: .success(FeedCommentPage(items: [], nextCursor: nil)))
    static let replyingViewModel = makeViewModel(.success(FeedPreviewData.engagedPost), comments: .success(FeedPreviewData.commentPage), replyTo: 0)
    // Lane I5: opened from an Activity entry, at its comment.
    static let focusedCommentViewModel = makeViewModel(.success(FeedPreviewData.engagedPost), comments: .success(FeedPreviewData.commentPage),
                                                       focusedCommentID: FeedPreviewData.commentPage.items[1].id)

    // Decision 289: the person's comment that did not go, with Retry.
    static let commentNotSentViewModel = makeViewModel(.success(FeedPreviewData.engagedPost),
                                                       comments: .success(FeedCommentPage(items: Array(FeedPreviewData.commentPage.items.prefix(1)), nextCursor: nil)),
                                                       failedComment: "Same here, the frost came early.")

    static var previews: some View {
        preview(loadedViewModel, name: "Loaded")
        preview(ownViewModel, name: "Own post")
        preview(heldViewModel, name: "Held")
        preview(removedViewModel, name: "Removed")
        preview(sensitiveViewModel, name: "Sensitive")
        preview(statementFailedViewModel, name: "Removed, reasons not read")
        preview(statementMissingViewModel, name: "Removed, reasons not among the latest")
        preview(notAvailableViewModel, name: "Not available")
        preview(failedViewModel, name: "Failed")
        preview(commentsViewModel, name: "Comments")
        preview(commentsViewModel, name: "Comments AX5")
            .dynamicTypeSize(.accessibility5)
        preview(noCommentsViewModel, name: "No comments")
        preview(commentsOffViewModel, name: "Comments off")
        preview(commentsFailedViewModel, name: "Comments failed")
        preview(hiddenViewModel, name: "Hidden")
        preview(replyingViewModel, name: "Replying", waitsForReply: true)
        preview(focusedCommentViewModel, name: "Opened at a comment")
        preview(commentNotSentViewModel, name: "Comment not sent",
                expect: commentNotSentViewModel.context.observe(\.viewState.pendingComments).map { $0.first?.delivery == .failed(.transport) })
    }

    private static func preview(_ viewModel: FeedPostScreenViewModel, name: String, waitsForReply: Bool = false,
                                expect: (any AsyncSequence<Bool, Never>)? = nil) -> some View {
        ElementNavigationStack {
            FeedPostScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: expect ?? (waitsForReply
                ? viewModel.context.observe(\.viewState.replyingTo?.id).map { $0 != nil } as any AsyncSequence<Bool, Never>
                : viewModel.context.observe(\.viewState.isSettled)))
        .previewDisplayName(name)
    }

    /// The notices behind the held, the removed and the sensitive previews; the filter's at publish (decision 278).
    private static let statementNotices = [
        FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000101", kind: .held, isRead: true, postID: "01933f2a-0000-7000-8000-000000000201",
                               statement: FeedPreviewData.statement(restriction: .held, trigger: .filter, isAutomated: true, isDetectedByAutomatedMeans: true,
                                                                    rule: "hate", ruleTitle: "Hate",
                                                                    ruleExplanation: "Attacking people for who they are.", appealContact: "support@spiral.md")),
        FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000103", kind: .sensitive, isRead: true, postID: "01933f2a-0000-7000-8000-000000000204",
                               statement: FeedPreviewData.statement(restriction: .sensitive, trigger: .filter, isAutomated: true, isDetectedByAutomatedMeans: true,
                                                                    rule: "sexual_content",
                                                                    ruleTitle: "Sexual content", ruleExplanation: "Pornography and sexually explicit content.",
                                                                    appealContact: "support@spiral.md")),
        FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000102", kind: .removed, isRead: true, postID: "01933f2a-0000-7000-8000-000000000203",
                               statement: FeedPreviewData.statement(restriction: .removed, trigger: .reports, rule: "spam", ruleTitle: "Spam",
                                                                    ruleExplanation: "Posting the same thing again and again, or advertising.",
                                                                    moderatorComment: "The same link in every post.", appealContact: "support@spiral.md"))
    ]

    static func makeViewModel(_ result: Result<FeedPost, FeedError>,
                              comments: Result<FeedCommentPage, FeedError> = .success(FeedCommentPage(items: [], nextCursor: nil)),
                              notices: Result<FeedNoticePage, FeedError> = .success(FeedNoticePage(items: statementNotices, nextCursor: nil, unread: 0)),
                              replyTo: Int? = nil,
                              focusedCommentID: String? = nil,
                              failedComment: String? = nil) -> FeedPostScreenViewModel {
        let service = FeedServiceMock()
        service.postIdReturnValue = result
        service.commentsPostIDCursorLimitReturnValue = comments
        service.createCommentPostIDTextReplyToIdempotencyKeyReturnValue = .failure(.transport)
        service.noticesCursorLimitLanguageReturnValue = notices
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md", displayName: "Mira"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        let viewModel = FeedPostScreenViewModel(postID: "01933f2a-0000-7000-8000-000000000201",
                                                post: nil,
                                                focusedCommentID: focusedCommentID,
                                                feedService: service,
                                                engagement: FeedEngagementController(store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                                                                     userIndicatorController: UserIndicatorControllerMock()),
                                                clientProxy: clientProxy,
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                language: "en")
        if let failedComment {
            Task {
                await viewModel.load()
                viewModel.context.commentText = failedComment
                await viewModel.sendComment()
            }
        }
        if let replyTo, case .success(let page) = comments {
            Task {
                await viewModel.load()
                viewModel.context.send(viewAction: .reply(commentID: page.items[replyTo].id))
                viewModel.context.commentText = "I agree"
            }
        }
        return viewModel
    }
}
