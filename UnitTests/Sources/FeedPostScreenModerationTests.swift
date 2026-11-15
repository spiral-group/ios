//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B4 on the post screen: Report
// for someone else's post and comment only, and the banner of the author's
// held or removed post with the statement from their notices, which a failed
// read never turns into "no reasons".
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedPostScreenModerationTests {
    private let service = FeedServiceMock()
    private let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))

    private static let removed = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000203", author: FeedPreviewData.ann, minutesAgo: 60,
                                                      text: "Removed", state: .removed, isAuthor: true)
    private static let removedNotice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000102", kind: .removed, isRead: true,
                                                              postID: removed.id,
                                                              statement: FeedPreviewData.statement(restriction: .removed, trigger: .reports, rule: "spam",
                                                                                                   ruleTitle: "Spam", moderatorComment: "Same link",
                                                                                                   appealContact: "support@spiral.md"))
    /// About a comment under the same post: not the post's statement.
    private static let commentNotice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000103", kind: .removed, isRead: true,
                                                              postID: removed.id, commentID: "01933f2b-0000-7000-8000-000000000009",
                                                              statement: FeedPreviewData.statement(restriction: .removed))

    init() {
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        service.noticesUnreadPublisher = Empty().eraseToAnyPublisher()
        service.activityUnreadPublisher = Empty().eraseToAnyPublisher()
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [], nextCursor: nil))
    }

    private func viewModel(_ post: FeedPost) -> FeedPostScreenViewModel {
        service.postIdReturnValue = .success(post)
        return FeedPostScreenViewModel(postID: post.id,
                                       post: nil,
                                       feedService: service,
                                       engagement: FeedEngagementController.make(service, userIndicatorController: UserIndicatorControllerMock()),
                                       clientProxy: clientProxy,
                                       mediaProvider: MediaProviderMock(.init()),
                                       userIndicatorController: UserIndicatorControllerMock(),
                                       language: "uk")
    }

    private func settled(_ viewModel: FeedPostScreenViewModel) async throws {
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.isSettled)) { $0 }
        try await settled.fulfill()
    }

    @Test
    func theStatementOfTheRemovedPostIsShownFromTheNotices() async throws {
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [Self.commentNotice, Self.removedNotice], nextCursor: nil, unread: 0))
        let viewModel = viewModel(Self.removed)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.authorStatement == .loaded(FeedNoticeContent(notice: Self.removedNotice)))
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.language == "uk")
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.limit == FeedPostScreenViewModel.statementSearchLimit)
    }

    /// A failed read never becomes "no reasons": it says so, with Retry.
    @Test
    func aFailedReadOfTheNoticesIsNotNoReasons() async throws {
        service.noticesCursorLimitLanguageReturnValue = .failure(.transport)
        let viewModel = viewModel(Self.removed)
        try await settled(viewModel)
        #expect(viewModel.context.viewState.authorStatement == .failed)

        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [Self.removedNotice], nextCursor: nil, unread: 0))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.authorStatement)) { if case .loaded = $0 { true } else { false } }
        viewModel.context.send(viewAction: .retryStatement)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.authorStatement == .loaded(FeedNoticeContent(notice: Self.removedNotice)))
    }

    /// The notice outside the latest page is no statement, not a failure: the banner still shows the way to the notices.
    @Test
    func aNoticeOutsideTheLatestPageIsLoadedWithoutAStatement() async throws {
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [Self.commentNotice], nextCursor: "older", unread: 0))
        let viewModel = viewModel(Self.removed)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.authorStatement == .loaded(nil))

        var opened = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .openNotices = $0 { opened += 1 } }
        viewModel.context.send(viewAction: .openNotices)
        #expect(opened == 1)
        _ = cancellable
    }

    /// Only the author's held or removed post reads the notices.
    /// Decision 278: the author's post the filter marked sensitive at publish
    /// has a banner with the `sensitive` notice, and no Delete in it (the menu has one).
    @Test
    func theAuthorsSensitivePostShowsTheFiltersNotice() async throws {
        let post = FeedPreviewData.post(id: "01933f2a-0000-7000-8000-000000000204", author: FeedPreviewData.ann, minutesAgo: 1,
                                        text: "Marked", isSensitive: true, isAuthor: true)
        let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000104", kind: .sensitive, isRead: false, postID: post.id,
                                            statement: FeedPreviewData.statement(restriction: .sensitive, trigger: .filter, isAutomated: true,
                                                                                 isDetectedByAutomatedMeans: true,
                                                                                 rule: "sexual_content", ruleTitle: "Sexual content"))
        service.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [notice], nextCursor: nil, unread: 1))
        let viewModel = viewModel(post)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.authorNotice == UntranslatedL10n.screenFeedPostSensitiveNotice)
        #expect(viewModel.context.viewState.authorNoticeOffersDelete == false)
        #expect(viewModel.context.viewState.authorStatement == .loaded(FeedNoticeContent(notice: notice)))
    }

    /// Someone else's sensitive post has no banner and reads no notices.
    @Test
    func someoneElsesSensitivePostReadsNoNotices() async throws {
        let viewModel = viewModel(FeedPreviewData.sensitivePost)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.authorNotice == nil)
        #expect(viewModel.context.viewState.authorStatement == .none)
        #expect(!service.noticesCursorLimitLanguageCalled)
    }

    @Test
    func aVisiblePostReadsNoNotices() async throws {
        let viewModel = viewModel(FeedPreviewData.textPost)
        try await settled(viewModel)

        #expect(viewModel.context.viewState.authorStatement == .none)
        #expect(service.noticesCursorLimitLanguageCallsCount == 0)
    }

    @Test
    func someoneElsesPostAndCommentAreReported() async throws {
        let theirs = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000001", author: FeedPreviewData.bob, minutesAgo: 2, text: "Theirs")
        let mine = FeedPreviewData.comment(id: "01933f2b-0000-7000-8000-000000000002", author: FeedPreviewData.ann, minutesAgo: 1, text: "Mine", isAuthor: true)
        service.commentsPostIDCursorLimitReturnValue = .success(FeedCommentPage(items: [theirs, mine], nextCursor: nil))
        let viewModel = viewModel(FeedPreviewData.textPost)
        try await settled(viewModel)
        var targets: [FeedReportTarget] = []
        let cancellable = viewModel.actionsPublisher.sink { if case .report(let target) = $0 { targets.append(target) } }

        #expect(viewModel.context.viewState.canReport)
        viewModel.context.send(viewAction: .report)
        viewModel.context.send(viewAction: .card(.report))
        viewModel.context.send(viewAction: .reportComment(commentID: theirs.id))
        viewModel.context.send(viewAction: .reportComment(commentID: mine.id))

        #expect(targets == [.post(id: FeedPreviewData.textPost.id), .post(id: FeedPreviewData.textPost.id), .comment(id: theirs.id)])
        _ = cancellable
    }

    @Test
    func theAuthorDoesNotReportTheirOwnPost() async throws {
        let viewModel = viewModel(FeedPreviewData.post(id: FeedPreviewData.textPost.id, author: FeedPreviewData.ann, minutesAgo: 1, text: "Mine", isAuthor: true))
        try await settled(viewModel)
        var reported = false
        let cancellable = viewModel.actionsPublisher.sink { if case .report = $0 { reported = true } }

        #expect(!viewModel.context.viewState.canReport)
        viewModel.context.send(viewAction: .report)

        #expect(!reported)
        _ = cancellable
    }
}
