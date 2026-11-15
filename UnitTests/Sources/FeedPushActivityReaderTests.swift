//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5: the NSE's words for a like,
// comment or reply push — read from the activity entry the push names with
// the session's token, read once more with a fresh one after a `401` — and the
// generic words on every failure: no fresh token, an entry not on the newest
// page, a sensitive one, a kind it does not know.
//

import Foundation
@testable import Spiral
import Synchronization
import Testing
import UserNotifications

@MainActor
struct FeedPushActivityReaderTests {
    private let testID = UUID().uuidString
    private let urlSession: URLSession
    private let refreshes = Refreshes()
    private let reader: FeedPushActivityReader

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        urlSession = URLSession(configuration: configuration)
        let refreshes = refreshes
        reader = FeedPushActivityReader(baseURL: "https://platform.test", accessToken: "mat_test",
                                        refreshAccessToken: { await refreshes.refresh($0) }, urlSession: urlSession)
    }

    @Test
    func aLikePushNamesTheNewestLikerAndTheRest() async throws {
        stub(status: 200)

        let words = await reader.words(for: subject(kind: "feed_like", id: Self.postID, group: "2026-10-30"))

        #expect(words == .init(body: "Taras and 2 others liked your post", subtitle: nil))
        let request = try #require(FeedURLProtocol.requests.withLock { $0[testID]?.last })
        #expect(request.path == "/api/v1/feed/activity")
        #expect(request.query == "limit=50")
        #expect(request.headers["Authorization"] == "Bearer mat_test")
    }

    @Test
    func aCommentPushQuotesWhoAndWhat() async {
        stub(status: 200)

        let words = await reader.words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID))

        #expect(words == .init(body: "Olena: so true", subtitle: UntranslatedL10n.screenFeedActivityCommentContext))
    }

    @Test
    func aReplyPushWithAWithheldNameStaysNeutral() async {
        stub(status: 200)

        let words = await reader.words(for: subject(kind: "feed_reply", id: Self.replyID, post: Self.postID))

        #expect(words == .init(body: "\(UntranslatedL10n.screenFeedAuthorWithheldName): agreed", subtitle: UntranslatedL10n.screenFeedActivityReplyContext))
    }

    /// Any failure keeps the generic words: none of these is "nothing happened".
    @Test
    func everyFailureKeepsTheGenericWords() async {
        stub(status: 200)
        #expect(await reader.words(for: subject(kind: "feed_comment", id: "01933f2c-0000-7000-8000-0000000000ff", post: Self.postID)) == nil)
        #expect(await reader.words(for: subject(kind: "feed_comment", id: Self.sensitiveID, post: Self.postID)) == nil)
        #expect(await reader.words(for: subject(kind: "feed_like", id: Self.postID)) == nil)
        #expect(await reader.words(for: subject(kind: "feed_notice", id: "n1")) == nil)

        stub(status: 401)
        #expect(await reader.words(for: subject(kind: "feed_like", id: Self.postID, group: "2026-10-30")) == nil)
    }

    /// An idle phone's token is stale: the SDK's fresh one reads the entry, once.
    @Test
    func aStaleTokenIsRefreshedAndTheReadTriedOnce() async {
        stub(status: 401)
        let testID = testID
        let page = Self.page
        let refreshes = Refreshes { _ in
            FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: 200, body: page) }
            return "mat_fresh"
        }

        let words = await makeReader(refreshes: refreshes).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID))

        #expect(words == .init(body: "Olena: so true", subtitle: UntranslatedL10n.screenFeedActivityCommentContext))
        #expect(refreshes.rejected.withLock { $0 } == ["mat_test"])
        let tokens = FeedURLProtocol.requests.withLock { $0[testID]?.map { $0.headers["Authorization"] } }
        #expect(tokens == ["Bearer mat_test", "Bearer mat_fresh"])
    }

    @Test
    func aRefreshThatFailsOrIsRefusedAgainKeepsTheGenericWords() async {
        stub(status: 401)
        #expect(await reader.words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID)) == nil, "no fresh token")
        #expect(FeedURLProtocol.requests.withLock { $0[testID]?.count } == 1)

        let refusedAgain = Refreshes { _ in "mat_fresh" }
        #expect(await makeReader(refreshes: refusedAgain).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID)) == nil)
        #expect(refusedAgain.rejected.withLock { $0 } == ["mat_test"], "one refresh, not a loop")
        #expect(FeedURLProtocol.requests.withLock { $0[testID]?.count } == 3)
    }

    /// H2: a refresh is never cut short, so it starts only while 12 s of the push's 20 s remain.
    @Test(arguments: [(8, true), (9, false)])
    func aRefreshStartsOnlyWithTimeForIt(elapsedSeconds: Int, refreshes expected: Bool) async {
        stub(status: 401)
        let clock = TestClock()
        clock.elapsed(.seconds(elapsedSeconds))

        _ = await makeReader(refreshes: refreshes, budget: clock.budget).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID))

        #expect(refreshes.rejected.withLock { $0 } == (expected ? ["mat_test"] : []))
    }

    /// H2: a started refresh is awaited to its end; the read after it still keeps the deadline.
    @Test
    func aRefreshRunsToItsEndAndNoReadFollowsPastTheDeadline() async {
        stub(status: 401)
        let clock = TestClock()
        let refreshes = Refreshes { _ in
            clock.elapsed(.seconds(21))
            return "mat_fresh"
        }

        let words = await makeReader(refreshes: refreshes, budget: clock.budget).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID))

        #expect(words == nil)
        #expect(refreshes.rejected.withLock { $0 } == ["mat_test"])
        #expect(FeedURLProtocol.requests.withLock { $0[testID]?.count } == 1)
    }

    @Test
    func pastTheDeadlineNothingIsRead() async {
        stub(status: 200)
        let clock = TestClock()
        clock.elapsed(.seconds(20))

        #expect(await makeReader(refreshes: refreshes, budget: clock.budget).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID)) == nil)
        #expect(FeedURLProtocol.requests.withLock { $0[testID] } == nil)
    }

    /// A server slower than the time left: the deadline ends the read, the generic words stay.
    @Test
    func aReadSlowerThanTheTimeLeftEndsAtTheDeadline() async {
        FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: 200, body: Self.page, hangs: true) }
        let clock = TestClock()
        clock.elapsed(.milliseconds(19800))
        let started = ContinuousClock.now

        let words = await makeReader(refreshes: refreshes, budget: clock.budget).words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID))

        #expect(words == nil)
        #expect(ContinuousClock.now - started < .seconds(5), "the hanging read is not awaited")
        #expect(FeedURLProtocol.requests.withLock { $0[testID]?.count } == 1)
    }

    /// Only a `401` is about the token: any other failure builds no session.
    @Test
    func anotherFailureAsksForNoFreshToken() async {
        stub(status: 503)

        #expect(await reader.words(for: subject(kind: "feed_comment", id: Self.commentID, post: Self.postID)) == nil)
        #expect(refreshes.rejected.withLock { $0 }.isEmpty)
    }

    /// One `URLSession` for the process: a session per push was never released.
    @Test
    func everyReaderSharesOneSession() {
        let first = FeedPushActivityReader(baseURL: "https://platform.test", accessToken: "a") { _ in nil }
        let second = FeedPushActivityReader(baseURL: "https://platform.test", accessToken: "b") { _ in nil }

        #expect(first.urlSession === second.urlSession)
        #expect(first.urlSession === FeedPushActivityReader.sharedSession)
    }

    @Test
    func theWordsGoIntoTheGenericContent() {
        let generic = UNMutableNotificationContent()
        generic.body = UntranslatedL10n.notificationFeedCommentBody

        let worded = FeedPushActivityReader.applying(.init(body: "Olena: so true", subtitle: "Comment on your post"), to: generic)
        #expect(worded.body == "Olena: so true")
        #expect(worded.subtitle == "Comment on your post")

        #expect(FeedPushActivityReader.applying(nil, to: generic).body == UntranslatedL10n.notificationFeedCommentBody)
    }

    // MARK: - Helpers

    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"
    private static let commentID = "01933f2c-0000-7000-8000-000000000001"
    private static let replyID = "01933f2c-0000-7000-8000-000000000002"
    private static let sensitiveID = "01933f2c-0000-7000-8000-000000000003"

    private func makeReader(refreshes: Refreshes, budget: FeedPushBudget = FeedPushBudget(start: .now)) -> FeedPushActivityReader {
        FeedPushActivityReader(baseURL: "https://platform.test", accessToken: "mat_test", budget: budget,
                               refreshAccessToken: { await refreshes.refresh($0) }, urlSession: urlSession)
    }

    /// The push's clock, moved by the test.
    private final nonisolated class TestClock: Sendable {
        private let start = ContinuousClock.now
        private let offset = Mutex<Duration>(.zero)

        var budget: FeedPushBudget {
            FeedPushBudget(start: start) { [self] in start.advanced(by: offset.withLock { $0 }) }
        }

        func elapsed(_ duration: Duration) {
            offset.withLock { $0 = duration }
        }
    }

    /// The tokens the reader called stale, and what each refresh answers.
    private final class Refreshes: Sendable {
        let rejected = Mutex<[String]>([])
        private let answer: @Sendable (String) -> String?

        init(answer: @escaping @Sendable (String) -> String? = { _ in nil }) {
            self.answer = answer
        }

        func refresh(_ token: String) async -> String? {
            rejected.withLock { $0.append(token) }
            return answer(token)
        }
    }

    private func subject(kind: String, id: String, post: String? = nil, group: String? = nil) -> SpiralPushContentBuilder.Subject {
        SpiralPushContentBuilder.Subject(kind: kind, id: id, reason: nil, post: post, group: group)
    }

    private func stub(status: Int) {
        let body = status == 200 ? Self.page : Data(#"{"type":"/errors/unauthorized","title":"x","status":\#(status)}"#.utf8)
        FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body) }
    }

    private static let page = Data(#"""
    {"items":[
      {"id":"like:\#(postID):2026-10-30","kind":"like","at":"2026-10-30T09:12:00Z","post_id":"\#(postID)",
       "actors":[{"mxid":"@taras:spiral.md","name":"Taras","official":false},{"mxid":"@ann:spiral.md","official":false}],
       "total":3,"post_preview":"Good night","sensitive":false,"unread":true},
      {"id":"comment:\#(commentID)","kind":"comment","at":"2026-10-30T09:11:00Z","post_id":"\#(postID)","comment_id":"\#(commentID)",
       "actors":[{"mxid":"@olena:spiral.md","name":"Olena","official":false}],"total":1,"preview":"so true",
       "post_preview":"Good night","sensitive":false,"unread":true},
      {"id":"reply:\#(replyID)","kind":"reply","at":"2026-10-30T09:10:00Z","post_id":"\#(postID)","comment_id":"\#(replyID)",
       "actors":[{"mxid":"@x:spiral.md","name":"Slur","name_withheld":true,"official":false}],"total":1,"preview":"agreed",
       "post_preview":"Good night","sensitive":false,"unread":true},
      {"id":"comment:\#(sensitiveID)","kind":"comment","at":"2026-10-30T09:09:00Z","post_id":"\#(postID)","comment_id":"\#(sensitiveID)",
       "actors":[{"mxid":"@olena:spiral.md","name":"Olena","official":false}],"total":1,"preview":"upsetting",
       "post_preview":"Good night","sensitive":true,"unread":true}
    ],"unread":4}
    """#.utf8)
}
