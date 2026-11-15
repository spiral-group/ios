//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I3 on B4's contract, through the
// generated client: a report's receipt (and the open one answered again),
// its refusals, the notices with newer values degrading, the unread count
// that only an answer moves, and a withheld name.
//

import AgentPlatformClient
import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedServiceModerationWireTests {
    private let testID = UUID().uuidString
    private let service: FeedService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = FeedService(client: client, cacheDirectory: nil)
    }

    // MARK: - Reports

    @Test(arguments: [
        (FeedReportTarget.post(id: "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"), "/api/v1/feed/posts/01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01/report"),
        (FeedReportTarget.comment(id: "01933f2b-7c2e-7b44-9a51-3f1e2d4c5b01"), "/api/v1/feed/comments/01933f2b-7c2e-7b44-9a51-3f1e2d4c5b01/report"),
        (FeedReportTarget.author(userID: "@ann:spiral.md"), "/api/v1/feed/authors/@ann:spiral.md/report")
    ])
    func aReportIsFiledAndAnswersItsReceipt(target: FeedReportTarget, path: String) async throws {
        stub(status: 201, body: Self.receipt)

        let receipt = try await service.report(target, reason: .harassment, detail: "Keeps insulting me").get()

        #expect(try receipt == FeedReportReceipt(reportID: Self.reportID, deadline: Self.date("2026-10-28T10:00:00Z"), isExisting: false))
        let request = try #require(lastRequest)
        #expect(request.method == "POST")
        #expect(request.path?.removingPercentEncoding == path)
        let json = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(json["reason"] as? String == "harassment")
        #expect(json["detail"] as? String == "Keeps insulting me")
    }

    /// The wire code of the regulated-goods rule, with the others in the server's order.
    @Test
    func aRegulatedGoodsReportSendsItsCode() async throws {
        stub(status: 201, body: Self.receipt)

        _ = try await service.report(.post(id: Self.postID), reason: .regulatedGoods, detail: nil).get()

        let request = try #require(lastRequest)
        let json = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(json["reason"] as? String == "regulated_goods")
        #expect(FeedReportReason.allCases.map(\.rawValue) == ["child_safety", "threat_to_life", "private_information", "illegal", "regulated_goods",
                                                              "sexual_content", "harassment", "hate", "violence", "impersonation", "spam", "malware", "other"])
    }

    /// A second report while the first is open answers that receipt: not an error.
    @Test
    func anOpenReportAnswersItsReceiptAgain() async throws {
        stub(status: 200, body: Self.receipt)

        let receipt = try await service.report(.post(id: Self.postID), reason: .spam, detail: nil).get()

        #expect(receipt.isExisting)
        #expect(receipt.reportID == Self.reportID)
        let json = try #require(lastRequest?.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(json["detail"] == nil || json["detail"] is NSNull)
    }

    @Test
    func theDailyCapCarriesRetryAfter() async {
        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "7200"])

        #expect(await service.report(.post(id: Self.postID), reason: .spam, detail: nil).failureValue == .rateLimited(retryAfterSeconds: 7200))
    }

    /// Decision 276: a person suspended from the feed cannot report; nothing was filed.
    @Test
    func aSuspendedReporterIsRefused() async {
        stub(status: 403, body: Self.problem(status: 403, type: FeedError.suspendedType))

        #expect(await service.report(.post(id: Self.postID), reason: .spam, detail: nil).failureValue == .suspended)
        #expect(await service.report(.comment(id: Self.commentID), reason: .spam, detail: nil).failureValue == .suspended)
        #expect(await service.report(.author(userID: "@ann:spiral.md"), reason: .spam, detail: nil).failureValue == .suspended)
    }

    /// Only the feed's own 404 means "not there"; the router's means no feed at all.
    @Test
    func onlyTheFeedsOwn404IsNotThere() async {
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))
        #expect(await service.report(.comment(id: Self.commentID), reason: .hate, detail: nil).failureValue == .notFound)

        stub(status: 404, body: Self.problem(status: 404, type: FeedError.routeNotFoundType))
        #expect(await service.report(.comment(id: Self.commentID), reason: .hate, detail: nil).failureValue == .unavailable, "A backend without the feed")
    }

    @Test
    func aRefusedReportIsAFailureNeverAReceipt() async {
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))
        #expect(await service.report(.author(userID: "@ann:spiral.md"), reason: .other, detail: nil).failureValue == .server(status: 400))

        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType))
        #expect(await service.report(.author(userID: "@ann:spiral.md"), reason: .other, detail: nil).failureValue == .unavailable)
    }

    // MARK: - Notices

    @Test
    func noticesDecodeTheStatementAndSendTheAppsLanguage() async throws {
        stub(status: 200, body: Self.noticePage(items: [Self.removedNotice], unread: 3, nextCursor: "c1"))

        let page = try await service.notices(cursor: nil, limit: 20, language: "uk").get()

        #expect(page.unread == 3)
        #expect(page.nextCursor == "c1")
        let notice = try #require(page.items.first)
        #expect(notice.kind == .removed)
        #expect(!notice.isRead)
        #expect(notice.postID == Self.postID)
        #expect(notice.commentID == nil)
        #expect(notice.statement == FeedNoticeStatement(restriction: .removed, until: nil, tier: nil, trigger: .report, isAutomated: false,
                                                        isDetectedByAutomatedMeans: false, rule: "hate", ruleTitle: "Ненависть", ruleExplanation: "Напади на людей.",
                                                        moderatorComment: "Second paragraph.", legalGround: nil, appealContact: "support@spiral.md",
                                                        targetKind: nil, deadline: nil, outcome: nil))
        let request = try #require(lastRequest)
        #expect(request.path == "/api/v1/feed/notices")
        #expect(request.headers["Accept-Language"] == "uk")
        #expect(request.query?.contains("limit=20") == true)
    }

    /// What detected the content and who decided come apart on the wire (Art. 17(3)(c)); absent is `false`.
    @Test(arguments: [
        // The filter at publish.
        (#""trigger":"filter","automated":true,"detected_by_automated_means":true"#, true, true),
        // A moderator's decision on filtered content.
        (#""trigger":"moderator","automated":false,"detected_by_automated_means":true"#, true, false),
        // The reports' threshold, on content the filter did not flag.
        (#""trigger":"reports","automated":true,"detected_by_automated_means":false"#, false, true),
        // Another moderator decision: the field is absent.
        (#""trigger":"moderator","automated":false"#, false, false)
    ])
    func noticesCarryWhatDetectedAndWhoDecided(fields: String, detected: Bool, automated: Bool) async throws {
        stub(status: 200, body: Self.noticePage(items: [#"""
        {"id":"0199d0a1-0000-7000-8000-00000000a003","kind":"held","created_at":"2026-10-27T10:00:00Z","read":false,
         "statement":{"restriction":"held",\#(fields),"rule":"regulated_goods","rule_title":"Regulated goods"}}
        """#], unread: 1))

        let notice = try #require(try await service.notices(cursor: nil, limit: 20, language: nil).get().items.first)

        #expect(notice.statement.isDetectedByAutomatedMeans == detected)
        #expect(notice.statement.isAutomated == automated)
        #expect(notice.statement.rule == "regulated_goods")
        #expect(notice.statement.ruleTitle == "Regulated goods")
    }

    /// Decision 96: a kind, trigger or outcome newer than this build is a value, not a failed page.
    @Test
    func newerNoticeValuesDegrade() async throws {
        stub(status: 200, body: Self.noticePage(items: [#"""
        {"id":"0199d0a1-0000-7000-8000-00000000a002","kind":"appeal_decided","created_at":"2026-10-27T10:00:00Z","read":true,
         "statement":{"automated":false,"trigger":"community","outcome":"partly","target_kind":"poll","restriction":"muted","extra":1}}
        """#], unread: 0))

        let notice = try #require(try await service.notices(cursor: nil, limit: 20, language: nil).get().items.first)

        #expect(notice.kind == .other("appeal_decided"))
        #expect(notice.statement.trigger == .other("community"))
        #expect(notice.statement.outcome == .other("partly"))
        #expect(notice.statement.targetKind == .other("poll"))
        #expect(notice.statement.restriction == .other("muted"))
        #expect(FeedNoticeContent(notice: notice).title == UntranslatedL10n.screenFeedNoticeUnsupported)
    }

    /// A failure is not an answer: a failed read never becomes "0 unread".
    @Test
    func onlyAnAnswerMovesTheUnreadCount() async throws {
        var counts: [Int] = []
        let cancellable = service.noticesUnreadPublisher.sink { counts.append($0) }

        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType))
        #expect(await service.notices(cursor: nil, limit: 1, language: nil).failureValue == .unavailable)
        #expect(counts.isEmpty)

        stub(status: 200, body: Self.noticePage(items: [Self.removedNotice], unread: 2))
        _ = try await service.notices(cursor: nil, limit: 1, language: nil).get()
        #expect(counts == [2])

        stub(status: 500, body: Self.problem(status: 500, type: "/errors/internal"))
        #expect(await service.markNoticeRead(id: "0199d0a1-0000-7000-8000-00000000a001").failureValue == .server(status: 500))
        #expect(counts == [2])

        // Marked read, the badge is what the server counts next, not the old count minus one.
        let readPath = "/api/v1/feed/notices/0199d0a1-0000-7000-8000-00000000a001/read"
        stub(status: 204, body: Data(), path: readPath)
        stub(status: 200, body: Self.noticePage(items: [Self.removedNotice], unread: 5), path: "/api/v1/feed/notices")
        try await service.markNoticeRead(id: "0199d0a1-0000-7000-8000-00000000a001").get()
        #expect(counts == [2, 5])
        let requests = FeedURLProtocol.requests.withLock { $0[testID] ?? [] }
        #expect(requests.suffix(2).map(\.path) == [readPath, "/api/v1/feed/notices"])
        #expect(requests.suffix(2).map(\.method) == ["POST", "GET"])
        #expect(requests.last?.query?.contains("limit=1") == true)
        _ = cancellable
    }

    /// Decision 278: what the filter holds or marks at publish has a notice that is
    /// not pushed, so the badge is read again; an ordinary publish reads nothing.
    @Test
    func aPublishTheFilterFlaggedReadsTheBadgeAgain() async throws {
        var counts: [Int] = []
        let cancellable = service.noticesUnreadPublisher.sink { counts.append($0) }
        stub(status: 200, body: Self.noticePage(items: [], unread: 3), path: "/api/v1/feed/notices")

        stub(status: 201, body: Self.ownPost(state: "visible", sensitive: false), path: "/api/v1/feed/posts")
        _ = try await service.createPost(text: "Hello", idempotencyKey: UUID()).get()
        #expect(counts.isEmpty)

        stub(status: 201, body: Self.ownPost(state: "held", sensitive: false), path: "/api/v1/feed/posts")
        _ = try await service.createPost(text: "Held", idempotencyKey: UUID()).get()
        #expect(counts == [3])

        stub(status: 201, body: Self.ownPost(state: "visible", sensitive: true), path: "/api/v1/feed/posts")
        _ = try await service.createPost(text: "Marked", idempotencyKey: UUID()).get()
        #expect(counts == [3, 3])

        stub(status: 200, body: Self.noticePage(items: [], unread: 4), path: "/api/v1/feed/notices")
        stub(status: 201, body: Data(#"""
        {"id":"\#(Self.commentID)","post_id":"\#(Self.postID)","author":{"mxid":"@me:spiral.md","official":false},
         "text":"Held","created_at":"2026-10-27T10:05:00Z","state":"held","held_reason":"filter",
         "viewer":{"is_author":true,"can_delete":true}}
        """#.utf8), path: "/api/v1/feed/posts/\(Self.postID)/comments")
        _ = try await service.createComment(postID: Self.postID, text: "Held", replyTo: nil, idempotencyKey: UUID()).get()
        #expect(counts == [3, 3, 4])
        _ = cancellable
    }

    /// A failed re-read after a mark-read leaves the last server value: never 0, never a local decrement.
    @Test
    func aFailedReReadAfterMarkReadLeavesTheLastCount() async throws {
        var counts: [Int] = []
        let cancellable = service.noticesUnreadPublisher.sink { counts.append($0) }
        stub(status: 200, body: Self.noticePage(items: [Self.removedNotice], unread: 1))
        _ = try await service.notices(cursor: nil, limit: 1, language: nil).get()
        #expect(counts == [1])

        let readPath = "/api/v1/feed/notices/0199d0a1-0000-7000-8000-00000000a001/read"
        stub(status: 204, body: Data(), path: readPath)
        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType), path: "/api/v1/feed/notices")
        try await service.markNoticeRead(id: "0199d0a1-0000-7000-8000-00000000a001").get()
        #expect(counts == [1])
        _ = cancellable
    }

    @Test
    func aMalformedNoticesCursorStartsAgain() async {
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))

        #expect(await service.notices(cursor: "old", limit: 20, language: nil).failureValue == .invalidCursor)
    }

    // MARK: - A withheld name

    /// The name is withheld: a neutral name, never the localpart, no MXID shown and no bio.
    @Test
    func aWithheldNameShowsANeutralNameAndNoBio() async throws {
        stub(status: 200, body: Data(#"""
        {"id":"\#(Self.postID)","created_at":"2026-10-27T10:00:00Z",
         "author":{"mxid":"@slur:spiral.md","official":false,"name_withheld":true,"bio":"never shown"},
         "content":{"kind":"text","text":"Hello","sensitive":false,"media":[]},
         "counts":{"likes":0,"comments":0,"shares":0},"viewer":{"liked":false,"hidden":false,"is_author":false},
         "state":"visible","comments_enabled":true}
        """#.utf8))

        let author = try await service.post(id: Self.postID).get().author

        #expect(author.isNameWithheld)
        #expect(author.displayName == UntranslatedL10n.screenFeedAuthorWithheldName)
        #expect(!author.displayName.contains("slur"))
        #expect(author.shownUserID == nil)
        #expect(author.bio == nil)
        #expect(try await FeedPostCardModel(post: service.post(id: Self.postID).get()).authorName == UntranslatedL10n.screenFeedAuthorWithheldName)
    }

    /// Additive fields may be absent: an author without `name_withheld` is shown by name.
    @Test
    func anAuthorWithoutTheFlagIsShownByName() async throws {
        stub(status: 200, body: Data(#"""
        {"id":"\#(Self.postID)","created_at":"2026-10-27T10:00:00Z","author":{"mxid":"@ann:spiral.md","official":false},
         "content":{"kind":"text","text":"Hello","sensitive":false,"media":[]},
         "counts":{"likes":0,"comments":0,"shares":0},"viewer":{"liked":false,"hidden":false,"is_author":false},
         "state":"visible","comments_enabled":true}
        """#.utf8))

        let author = try await service.post(id: Self.postID).get().author

        #expect(!author.isNameWithheld)
        #expect(author.displayName == "ann")
        #expect(author.shownUserID == "@ann:spiral.md")
    }

    // MARK: - Helpers

    private static func ownPost(state: String, sensitive: Bool) -> Data {
        let heldReason = state == "held" ? #","held_reason":"filter""# : ""
        return Data(#"""
        {"id":"\#(postID)","created_at":"2026-10-27T10:00:00Z","author":{"mxid":"@me:spiral.md","official":false},
         "content":{"kind":"text","text":"Hello","sensitive":\#(sensitive),"media":[]},
         "counts":{"likes":0,"comments":0,"shares":0},"viewer":{"liked":false,"hidden":false,"is_author":true},
         "state":"\#(state)"\#(heldReason),"comments_enabled":true}
        """#.utf8)
    }

    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"
    private static let commentID = "01933f2b-7c2e-7b44-9a51-3f1e2d4c5b01"
    private static let reportID = "01933f2c-7c2e-7b44-9a51-3f1e2d4c5b01"

    private static let receipt = Data(#"{"report_id":"01933F2C-7C2E-7B44-9A51-3F1E2D4C5B01","deadline_at":"2026-10-28T10:00:00Z"}"#.utf8)

    private static let removedNotice = #"""
    {"id":"0199d0a1-0000-7000-8000-00000000a001","kind":"removed","created_at":"2026-10-27T10:00:00Z","read":false,
     "post_id":"\#(postID)",
     "statement":{"restriction":"removed","trigger":"report","automated":false,"rule":"hate","rule_title":"Ненависть",
                  "rule_explanation":"Напади на людей.","moderator_comment":"Second paragraph.","appeal_contact":"support@spiral.md"}}
    """#

    private static func noticePage(items: [String], unread: Int, nextCursor: String? = nil) -> Data {
        var fields = [#""items":[\#(items.joined(separator: ","))]"#, #""unread":\#(unread)"#]
        if let nextCursor { fields.append(#""next_cursor":"\#(nextCursor)""#) }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private static func problem(status: Int, type: String) -> Data {
        Data(#"{"type":"\#(type)","title":"x","status":\#(status),"detail":"x"}"#.utf8)
    }

    private static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private func stub(status: Int, body: Data, headers: [String: String] = [:], path: String? = nil) {
        if let path {
            FeedURLProtocol.pathStubs.withLock { $0[testID, default: [:]][path] = .init(status: status, body: body, headers: headers) }
        } else {
            FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body, headers: headers) }
        }
    }

    private var lastRequest: FeedURLProtocol.Recorded? {
        FeedURLProtocol.requests.withLock { $0[testID]?.last }
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
