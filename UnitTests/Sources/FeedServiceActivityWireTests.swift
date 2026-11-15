//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). Lane I5 on B6's contract, through the
// generated client: the activity page (a kind newer than this build skipped),
// the seen mark, who liked and the push settings per kind with a newer value
// kept as it is — and that the badge's count moves only on an answer.
//

import AgentPlatformClient
import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct FeedServiceActivityWireTests {
    private let testID = UUID().uuidString
    private let service: FeedService
    private var unreadValues: [Int] {
        unreadRecorder.values
    }

    private let unreadRecorder = Recorder()

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = FeedService(client: client, cacheDirectory: nil)
        unreadRecorder.cancellable = service.activityUnreadPublisher.sink { [unreadRecorder] in unreadRecorder.values.append($0) }
    }

    // MARK: - Activity

    @Test
    func anActivityPageDecodesAndSkipsAKindNewerThanThisBuild() async throws {
        stub(status: 200, body: Self.activityPage)

        let page = try await service.activity(cursor: nil, limit: 20).get()

        #expect(page.items.map(\.kind) == [.like, .reply])
        #expect(page.unread == 3)
        #expect(page.nextCursor == "c2")
        let like = try #require(page.items.first)
        #expect(like.id == "like:\(Self.postID):2026-10-30")
        #expect(like.postID == Self.postID)
        #expect(like.actors.map(\.displayName) == ["Тарас", "olena"])
        #expect(like.total == 4)
        #expect(like.othersCount == 3)
        #expect(like.isUnread)
        let reply = page.items[1]
        #expect(reply.commentID == Self.commentID)
        #expect(reply.preview == "так!")
        #expect(reply.isSensitive)
        #expect(unreadValues == [3])

        let request = try #require(lastRequest)
        #expect(request.method == "GET")
        #expect(request.path == "/api/v1/feed/activity")
        #expect(request.query?.contains("limit=20") == true)
    }

    /// A failed read is not "no activity": the badge keeps the last count the server gave.
    @Test
    func aFailedReadLeavesTheBadge() async throws {
        stub(status: 200, body: Self.activityPage)
        _ = try await service.activity(cursor: nil, limit: 20).get()

        stub(status: 503, body: Self.problem(status: 503, type: FeedError.temporarilyUnavailableType), headers: ["Retry-After": "5"])
        let result = await service.activity(cursor: nil, limit: 20)

        #expect(result.failureValue == .temporarilyUnavailable(retryAfterSeconds: 5))
        #expect(unreadValues == [3])
    }

    /// An entry of a kind this build skips is still seen: the page's newest time is its.
    @Test
    func theNewestTimeCountsASkippedKind() async throws {
        stub(status: 200, body: Data(#"""
        {"items":[
          {"id":"mention:01933f2c-0000-7000-8000-000000000009","kind":"mention","at":"2026-10-30T09:13:00Z","post_id":"\#(Self.postID)",
           "actors":[{"mxid":"@taras:spiral.md","official":false}],"total":1,"post_preview":"x","sensitive":false,"unread":true},
          {"id":"like:\#(Self.postID):2026-10-30","kind":"like","at":"2026-10-30T09:12:00Z","post_id":"\#(Self.postID)",
           "actors":[{"mxid":"@taras:spiral.md","official":false}],"total":1,"post_preview":"x","sensitive":false,"unread":true}
        ],"unread":2}
        """#.utf8))

        let page = try await service.activity(cursor: nil, limit: 20).get()

        #expect(page.items.map(\.kind) == [.like])
        let newest = try Self.date("2026-10-30T09:13:00Z")
        #expect(page.newestAt == newest)
    }

    @Test
    func anOldActivityCursorIsInvalid() async {
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))
        #expect(await service.activity(cursor: "old", limit: 20).failureValue == .invalidCursor)
    }

    @Test
    func theSeenMarkSendsTheNewestEntryAndTheAnswerIsTheBadge() async throws {
        stub(status: 200, body: Data(#"{"unread":0}"#.utf8))
        let newest = try Self.date("2026-10-30T09:12:00Z")

        let unread = try await service.markActivitySeen(upTo: newest).get()

        #expect(unread == 0)
        #expect(unreadValues == [0])
        let request = try #require(lastRequest)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/feed/activity/seen")
        let json = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect((json["at"] as? String)?.hasPrefix("2026-10-30T09:12:00") == true)
    }

    @Test
    func aFailedSeenMarkLeavesTheBadge() async {
        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType))
        #expect(await service.markActivitySeen(upTo: nil).failureValue == .unavailable)
        #expect(unreadValues.isEmpty)
    }

    // MARK: - Who liked

    @Test
    func theLikersDecodeNewestFirst() async throws {
        stub(status: 200, body: Data(#"""
        {"items":[{"author":{"mxid":"@taras:spiral.md","name":"Тарас","official":false},"liked_at":"2026-10-30T09:12:00Z"},
                  {"author":{"mxid":"@spiral:spiral.md","name":"Spiral","official":true},"liked_at":"2026-10-30T09:00:00Z"}],
         "next_cursor":"l2"}
        """#.utf8))

        let page = try await service.likers(postID: Self.postID, cursor: nil, limit: 30).get()

        #expect(page.items.map(\.author.userID) == ["@taras:spiral.md", "@spiral:spiral.md"])
        #expect(page.items[1].author.isOfficial)
        #expect(page.nextCursor == "l2")
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)/likes")
    }

    @Test
    func thePostNotThereIsNotFound() async {
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))
        #expect(await service.likers(postID: Self.postID, cursor: nil, limit: 30).failureValue == .notFound)
    }

    // MARK: - Push settings

    /// A value newer than this build is kept as it is, and sent back as it is with a change to another kind.
    @Test
    func theSettingsPerKindAreReadAndStoredAsTheServerAnswers() async throws {
        stub(status: 200, body: Data(#"{"likes":"following","comments":"everyone","replies":"off"}"#.utf8))
        let settings = try await service.notificationSettings().get()
        #expect(settings == FeedNotificationSettings(likes: .other("following"), comments: .everyone, replies: .off))

        stub(status: 200, body: Data(#"{"likes":"following","comments":"off","replies":"off"}"#.utf8))
        let stored = try await service.setNotificationSettings(FeedNotificationSettings(likes: .other("following"), comments: .off, replies: .off)).get()
        #expect(stored.comments == .off)
        let request = try #require(lastRequest)
        #expect(request.method == "PUT")
        #expect(request.path == "/api/v1/feed/me/notification-settings")
        let json = try #require(request.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: String] })
        #expect(json == ["likes": "following", "comments": "off", "replies": "off"])

        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType))
        #expect(await service.setNotificationSettings(stored).failureValue == .unavailable)
    }

    // MARK: - Helpers

    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"
    private static let commentID = "01933f2c-7c2e-7b44-9a51-3f1e2d4c5b01"

    private static let activityPage = Data(#"""
    {"items":[
      {"id":"like:\#(postID):2026-10-30","kind":"like","at":"2026-10-30T09:12:00Z","post_id":"\#(postID)",
       "actors":[{"mxid":"@taras:spiral.md","name":"Тарас","official":false},{"mxid":"@olena:spiral.md","official":false}],
       "total":4,"post_preview":"Добраніч, Spiral","sensitive":false,"unread":true},
      {"id":"mention:01933f2c-0000-7000-8000-000000000009","kind":"mention","at":"2026-10-30T09:11:00Z","post_id":"\#(postID)",
       "actors":[{"mxid":"@taras:spiral.md","official":false}],"total":1,"post_preview":"x","sensitive":false,"unread":true},
      {"id":"reply:\#(commentID)","kind":"reply","at":"2026-10-30T09:10:00Z","post_id":"\#(postID)","comment_id":"\#(commentID)",
       "actors":[{"mxid":"@olena:spiral.md","name":"Олена","official":false}],"total":1,"preview":"так!",
       "post_preview":"Добраніч, Spiral","sensitive":true,"unread":false,"something_newer":1}
    ],"next_cursor":"c2","unread":3}
    """#.utf8)

    private func stub(status: Int, body: Data, headers: [String: String] = [:], contentType: String? = nil) {
        FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body, headers: headers, contentType: contentType) }
    }

    private var lastRequest: FeedURLProtocol.Recorded? {
        FeedURLProtocol.requests.withLock { $0[testID]?.last }
    }

    private static func problem(status: Int, type: String) -> Data {
        Data(#"{"type":"\#(type)","title":"x","status":\#(status),"detail":"x"}"#.utf8)
    }

    private static func date(_ string: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: string))
    }

    private final class Recorder {
        var values: [Int] = []
        var cancellable: AnyCancellable?
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
