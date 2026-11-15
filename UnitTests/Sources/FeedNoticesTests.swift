//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The notices (lane I3 on B4): what each
// says, that a failed read is never "no notices", that a notice is read once
// the server says so, and the badge on the Feed tab.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedNoticeContentTests {
    /// "Why" turns a chevron VoiceOver does not see: the state is said in words.
    @Test
    func theWhyButtonSaysWhetherItIsOpen() {
        #expect(FeedNoticeStatementView.accessibilityValue(isExpanded: true) == UntranslatedL10n.a11yFeedExpanded)
        #expect(FeedNoticeStatementView.accessibilityValue(isExpanded: false) == UntranslatedL10n.a11yFeedCollapsed)
        #expect(UntranslatedL10n.a11yFeedExpanded != UntranslatedL10n.a11yFeedCollapsed)
    }

    /// The six elements, in order, with the moderator's comment after the rule's texts (decision 271).
    @Test
    func anAuthorsNoticeCarriesTheStatementOfReasons() throws {
        let notice = try #require(FeedPreviewData.notices.first { $0.kind == .removed })

        let content = FeedNoticeContent(notice: notice)

        #expect(content.title == UntranslatedL10n.screenFeedNoticeRemovedPostTitle)
        #expect(content.postID == FeedPreviewData.textPost.id)
        #expect(content.lines == [
            .text(UntranslatedL10n.screenFeedNoticeTriggerReport),
            .text(UntranslatedL10n.screenFeedNoticeByModerator),
            .rule(title: "Hate", explanation: "Attacking people for who they are: their origin, religion, gender, sexuality or disability."),
            .moderatorComment("The second paragraph targets a group of people."),
            .text(UntranslatedL10n.screenFeedNoticeLegalGround("DSA Art. 16")),
            .appeal("support@spiral.md")
        ])
    }

    /// Decision 270: a lowered tier is a restriction with its new limits.
    /// Decision 287: what happened shows at once; every other element of the statement sits under "Why?".
    @Test
    func whatHappenedShowsAndTheReasonsSitUnderWhy() throws {
        let removed = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .removed }))
        #expect(removed.summary.isEmpty)
        #expect(removed.reasons.first == .text(UntranslatedL10n.screenFeedNoticeTriggerReport))
        #expect(removed.reasons.last == .appeal("support@spiral.md"))

        let suspended = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .suspended }))
        #expect(suspended.summary.count == 1)
        #expect(suspended.reasons.first == .text(UntranslatedL10n.screenFeedNoticeTriggerModerator))

        let limited = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .limited }))
        #expect(limited.summary == [.text(UntranslatedL10n.screenFeedNoticeTierNew)])

        let received = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .reportReceived }))
        #expect(received.reasons.isEmpty)

        let decided = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .reportDecided }))
        #expect(decided.summary == [.text(UntranslatedL10n.screenFeedNoticeOutcomeNoAction)])
    }

    @Test
    func aLimitingNamesTheNewLimits() throws {
        let notice = try #require(FeedPreviewData.notices.first { $0.kind == .limited })

        let content = FeedNoticeContent(notice: notice)

        #expect(content.title == UntranslatedL10n.screenFeedNoticeLimitedTitle)
        #expect(content.lines.first == .text(UntranslatedL10n.screenFeedNoticeTierNew))
        #expect(content.postID == nil)
    }

    @Test
    func aCommentsNoticeSaysComment() throws {
        let notice = try #require(FeedPreviewData.notices.first { $0.kind == .held })

        let content = FeedNoticeContent(notice: notice)

        #expect(content.title == UntranslatedL10n.screenFeedNoticeHeldCommentTitle)
        #expect(content.lines.contains(.text(UntranslatedL10n.screenFeedNoticeTriggerSla)))
        #expect(content.lines.contains(.text(UntranslatedL10n.screenFeedNoticeDecidedAutomatically)))
    }

    /// Decision 278: the filter's notice at publish says automated means detected
    /// the content, and no moderator has decided anything yet.
    @Test
    func aFilterNoticeAtPublishSaysAutomatedMeansDetectedIt() throws {
        for kind in [FeedNoticeKind.held, .sensitive] {
            let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000201", kind: kind, isRead: false, postID: FeedPreviewData.textPost.id,
                                                statement: FeedPreviewData.statement(restriction: kind, trigger: .filter, isAutomated: true,
                                                                                     isDetectedByAutomatedMeans: true,
                                                                                     rule: "sexual_content", ruleTitle: "Sexual content",
                                                                                     appealContact: "support@spiral.md"))

            let content = FeedNoticeContent(notice: notice)

            #expect(content.title == (kind == .held ? UntranslatedL10n.screenFeedNoticeHeldPostTitle : UntranslatedL10n.screenFeedNoticeSensitivePostTitle))
            #expect(content.lines == [
                .text(UntranslatedL10n.screenFeedNoticeTriggerFilter),
                .text(UntranslatedL10n.screenFeedNoticeAutomatedDetected),
                .text(UntranslatedL10n.screenFeedNoticeDecidedAutomatically),
                .rule(title: "Sexual content", explanation: nil),
                .appeal("support@spiral.md")
            ])
        }
    }

    /// A moderator's decision on what the filter flagged: detected by automated
    /// means, decided by a person; and the legal ground when given.
    @Test
    func aModeratorsDecisionOnFilteredContentSaysBoth() {
        let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000202", kind: .removed, isRead: false, postID: FeedPreviewData.textPost.id,
                                            statement: FeedPreviewData.statement(restriction: .removed, trigger: .filter, isAutomated: false,
                                                                                 isDetectedByAutomatedMeans: true,
                                                                                 rule: "illegal", ruleTitle: "Illegal content",
                                                                                 legalGround: "Criminal Code art. 307: an offer to sell drugs"))

        let content = FeedNoticeContent(notice: notice)

        #expect(content.lines == [
            .text(UntranslatedL10n.screenFeedNoticeTriggerFilter),
            .text(UntranslatedL10n.screenFeedNoticeAutomatedDetected),
            .text(UntranslatedL10n.screenFeedNoticeModeratorDecided),
            .rule(title: "Illegal content", explanation: nil),
            .text(UntranslatedL10n.screenFeedNoticeLegalGround("Criminal Code art. 307: an offer to sell drugs"))
        ])
    }

    /// With `detected_by_automated_means` the notice says both facts as the server
    /// gives them: what detected the content, and who decided.
    @Test(arguments: [
        // A filter hold at publish.
        (true, true, [UntranslatedL10n.screenFeedNoticeAutomatedDetected, UntranslatedL10n.screenFeedNoticeDecidedAutomatically]),
        // A moderator's decision on what the filter detected.
        (true, false, [UntranslatedL10n.screenFeedNoticeAutomatedDetected, UntranslatedL10n.screenFeedNoticeModeratorDecided]),
        // A hold by the reports' threshold.
        (false, true, [UntranslatedL10n.screenFeedNoticeDecidedAutomatically]),
        // A moderator alone.
        (false, false, [UntranslatedL10n.screenFeedNoticeByModerator])
    ])
    func bothAutomatedFactsAreSaidWhenTheServerGivesThem(detected: Bool, automated: Bool, expected: [String]) {
        let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000204", kind: .held, isRead: false,
                                            statement: FeedPreviewData.statement(restriction: .held, isAutomated: automated,
                                                                                 isDetectedByAutomatedMeans: detected))

        #expect(FeedNoticeContent(notice: notice).lines == expected.map(FeedNoticeContent.Line.text))
    }

    /// DSA Art. 17(3)(f), lane L H5: the redress names the courts as well as the email.
    @Test
    func theAppealLineNamesJudicialRedress() {
        #expect(UntranslatedL10n.screenFeedNoticeAppeal("support@spiral.md") == "If you disagree, write to support@spiral.md. You can also go to court.")
    }

    /// Without a legal ground nothing stands under its label.
    @Test
    func noLegalGroundIsNoLine() {
        let notice = FeedPreviewData.notice(id: "01933f2d-0000-7000-8000-000000000203", kind: .removed, isRead: false,
                                            statement: FeedPreviewData.statement(restriction: .removed, trigger: .report, legalGround: "  "))

        #expect(FeedNoticeContent(notice: notice).lines == [.text(UntranslatedL10n.screenFeedNoticeTriggerReport),
                                                            .text(UntranslatedL10n.screenFeedNoticeByModerator)])
    }

    /// The reporter's notices: the receipt with its deadline, then the outcome; never the author of a profile report's post.
    @Test
    func aReportersNoticesSayWhatCameOfTheReport() throws {
        let received = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .reportReceived }))
        #expect(received.title == UntranslatedL10n.screenFeedNoticeReportReceivedTitle)
        #expect(received.lines.first == .text(UntranslatedL10n.screenFeedNoticeReportedPost))
        #expect(received.lines.count == 2)

        let decided = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.first { $0.kind == .reportDecided }))
        #expect(decided.title == UntranslatedL10n.screenFeedNoticeReportDecidedTitle)
        #expect(decided.lines == [.text(UntranslatedL10n.screenFeedNoticeOutcomeNoAction)])
        #expect(decided.postID == nil)
    }

    /// Decision 96: a kind newer than this build says to update, and shows nothing else.
    @Test
    func anUnknownKindSaysToUpdate() throws {
        let content = try FeedNoticeContent(notice: #require(FeedPreviewData.notices.last))

        #expect(content.title == UntranslatedL10n.screenFeedNoticeUnsupported)
        #expect(content.lines.isEmpty)
        #expect(content.postID == nil)
    }
}

@MainActor
struct FeedNoticesScreenViewModelTests {
    private let service = FeedServiceMock()
    private static let unread = FeedPreviewData.notices[0]

    private func loadedViewModel(_ result: Result<FeedNoticePage, FeedError>) async throws -> FeedNoticesScreenViewModel {
        service.noticesCursorLimitLanguageReturnValue = result
        let viewModel = FeedNoticesScreenViewModel(feedService: service,
                                                   store: FeedStore(feedService: service, currentUserID: "@me:spiral.md"),
                                                   userIndicatorController: UserIndicatorControllerMock(),
                                                   language: "ru")
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loading = $0 { false } else { true } }
        try await settled.fulfill()
        return viewModel
    }

    /// A failed read never becomes "no notices".
    @Test
    func aFailedReadIsNotAnEmptyList() async throws {
        let viewModel = try await loadedViewModel(.failure(.transport))

        #expect(viewModel.context.viewState.listState == .failed)
        #expect(!viewModel.context.viewState.isEmpty)

        let unavailable = try await loadedViewModel(.failure(.unavailable))
        #expect(unavailable.context.viewState.listState == .unavailable)
    }

    @Test
    func theNoticesAreReadInTheAppsLanguage() async throws {
        let viewModel = try await loadedViewModel(.success(FeedNoticePage(items: [], nextCursor: nil, unread: 0)))

        #expect(viewModel.context.viewState.isEmpty)
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.language == "ru")
    }

    /// One request per notice, and read only once the server says so.
    @Test
    func aNoticeIsMarkedReadOnceAndOnlyOnTheServersWord() async throws {
        let viewModel = try await loadedViewModel(.success(FeedNoticePage(items: [Self.unread], nextCursor: nil, unread: 1)))
        var readWhileAsking: Bool?
        service.markNoticeReadIdClosure = { _ in
            readWhileAsking = viewModel.context.viewState.items.first?.notice.isRead
            await viewModel.markRead(Self.unread.id)
            return .success(())
        }

        await viewModel.markRead(Self.unread.id)

        #expect(readWhileAsking == false)
        #expect(service.markNoticeReadIdCallsCount == 1)
        #expect(viewModel.context.viewState.items.first?.notice.isRead == true)

        await viewModel.markRead(Self.unread.id)
        #expect(service.markNoticeReadIdCallsCount == 1)
    }

    @Test
    func aFailedMarkLeavesItUnread() async throws {
        let viewModel = try await loadedViewModel(.success(FeedNoticePage(items: [Self.unread], nextCursor: nil, unread: 1)))
        service.markNoticeReadIdReturnValue = .failure(.server(status: 503))

        await viewModel.markRead(Self.unread.id)

        #expect(viewModel.context.viewState.items.first?.notice.isRead == false)
    }

    @Test
    func aNoticeOpensItsPost() async throws {
        let viewModel = try await loadedViewModel(.success(FeedNoticePage(items: [Self.unread], nextCursor: nil, unread: 1)))
        var opened: String?
        let cancellable = viewModel.actionsPublisher.sink { if case .openPost(let postID) = $0 { opened = postID } }

        viewModel.context.send(viewAction: .openPost(postID: FeedPreviewData.textPost.id))

        #expect(opened == FeedPreviewData.textPost.id)
        _ = cancellable
    }
}

/// The badge on the Feed tab: the server's unread count, kept when a read fails.
@MainActor
struct FeedScreenNoticesBadgeTests {
    private let service = FeedServiceMock()
    private let unread = PassthroughSubject<Int, Never>()
    private let unreadActivity = PassthroughSubject<Int, Never>()

    init() {
        let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.ignoredUsersPublisher = CurrentValueSubject<[String]?, Never>([]).asCurrentValuePublisher()
        service.latestCursorLimitReturnValue = .success(FeedPage(items: [], nextCursor: nil, pinned: nil))
        service.cachedFirstPageReturnValue = nil
        service.noticesUnreadPublisher = unread.eraseToAnyPublisher()
        service.activityUnreadPublisher = unreadActivity.eraseToAnyPublisher()
        self.clientProxy = clientProxy
    }

    private let clientProxy: ClientProxyMock

    @Test
    func theBadgeFollowsTheServersCountAndAFailureLeavesIt() async throws {
        let engagement = FeedEngagementController.make(service)
        let viewModel = FeedScreenViewModel(feedService: service,
                                            engagement: engagement,
                                            clientProxy: clientProxy,
                                            mediaProvider: MediaProviderMock(.init()),
                                            userIndicatorController: UserIndicatorControllerMock())
        #expect(viewModel.context.viewState.unreadNotices == nil)

        let three = deferFulfillment(viewModel.context.observe(\.viewState.unreadNotices)) { $0 == 3 }
        unread.send(3)
        try await three.fulfill()
        #expect(viewModel.context.viewState.bellAccessibilityLabel == UntranslatedL10n.a11yFeedActivityUnread(3))

        // Lane I5: the bell counts the unread activity too.
        let five = deferFulfillment(viewModel.context.observe(\.viewState.bellUnread)) { $0 == 5 }
        unreadActivity.send(2)
        try await five.fulfill()
        #expect(viewModel.context.viewState.bellAccessibilityLabel == UntranslatedL10n.a11yFeedActivityUnread(5))

        // `feed.notice` reads the count again (one notice); a failed read sends nothing: the badge is not cleared.
        service.noticesCursorLimitLanguageReturnValue = .failure(.transport)
        engagement.store.apply([.notice])
        await engagement.store.settle()
        #expect(viewModel.context.viewState.unreadNotices == 3)
        #expect(service.noticesCursorLimitLanguageReceivedArguments?.limit == 1)

        let none = deferFulfillment(viewModel.context.observe(\.viewState.bellUnread)) { $0 == 0 }
        unread.send(0)
        unreadActivity.send(0)
        try await none.fulfill()
        #expect(viewModel.context.viewState.bellAccessibilityLabel == UntranslatedL10n.screenFeedActivityTitle)
    }
}
