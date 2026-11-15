//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The feed's read routes against a stubbed
// transport, through the generated client: the wire shapes of lane B1a
// decode, newer values degrade instead of failing a page (decision 96), and
// every problem type maps to its `FeedError`.
//

import AgentPlatformClient
import Foundation
@testable import Spiral
import Synchronization
import Testing

@MainActor
struct FeedServiceWireTests {
    private let testID = UUID().uuidString
    private let cacheDirectory: URL
    private let service: FeedService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        cacheDirectory = URL.temporaryDirectory.appending(component: "feed-wire-\(testID)")
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        service = FeedService(client: client, cacheDirectory: cacheDirectory)
    }

    // MARK: - Latest

    @Test
    func aPageDecodesIntoTheAppsPosts() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)], nextCursor: "c1"))

        let page = try await service.latest(cursor: nil, limit: 20).get()

        #expect(page.nextCursor == "c1")
        let post = try #require(page.items.first)
        #expect(post.id == Self.postID)
        #expect(post.author == FeedAuthor(userID: "@ann:spiral.md", name: "Ann", avatarURL: URL(string: "mxc://spiral.md/avatar"),
                                          bio: "Gardener", isOfficial: false, isNameWithheld: false))
        #expect(post.content.kind == .textImages)
        #expect(post.content.text == "Hello https://example.org")
        #expect(post.content.isSensitive)
        #expect(post.content.media == [FeedMediaRef(id: "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02", mxcURL: URL(string: "mxc://spiral.md/a"),
                                                    mimeType: "image/jpeg", width: 2048, height: 1536,
                                                    blurhash: "LEHV6nWB2yk8pyo0adR*.7kCMdnj", altText: "A birch wood")])
        #expect(post.state == .visible)
        #expect(post.heldReason == nil)
        #expect(post.viewer == FeedViewer(liked: false, hidden: false, isAuthor: false))

        let request = try #require(lastRequest)
        #expect(request.method == "GET")
        #expect(request.path == "/api/v1/feed/latest")
        #expect(request.query?.contains("limit=20") == true)
        #expect(request.query?.contains("cursor") != true)
    }

    /// A kind, state or held reason newer than this build is a value, not a decode failure of the page.
    @Test
    func newerValuesDegradeWithoutFailingThePage() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID, kind: "poll", state: "archived", extra: #","poll":{"options":["a"]}"#),
                                                  Self.post(id: Self.otherPostID, state: "held", heldReason: "community_vote")]))

        let page = try await service.latest(cursor: nil, limit: 20).get()

        #expect(page.items.map(\.content.kind) == [.other("poll"), .textImages])
        #expect(page.items.map(\.state) == [.other("archived"), .held])
        #expect(page.items[1].heldReason == .other("community_vote"))
    }

    @Test
    func anAuthorWithoutANameOrBioDecodes() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID, author: #"{"mxid":"@bob:spiral.md","official":true}"#)]))

        let post = try #require(try await service.latest(cursor: nil, limit: 20).get().items.first)

        #expect(post.author.name == nil)
        #expect(post.author.bio == nil)
        #expect(post.author.avatarURL == nil)
        #expect(post.author.isOfficial)
        #expect(post.author.displayName == "bob")
    }

    /// An empty page with a cursor is not the end (every row the server scanned was filtered).
    @Test
    func anEmptyPageKeepsItsCursor() async throws {
        stub(status: 200, body: Self.page(items: [], nextCursor: "c2"))

        let page = try await service.latest(cursor: "c1", limit: 20).get()

        #expect(page.items.isEmpty)
        #expect(page.nextCursor == "c2")
        #expect(page.pinned == nil)
        #expect(lastRequest?.query?.contains("cursor=c1") == true)
    }

    /// The pinned rules post above the first page of Latest (D-P1); a plain
    /// optional `FeedPost` in the spec since backend 0b5dba81.
    @Test
    func thePinnedPostDecodes() async throws {
        stub(status: 200, body: Self.page(items: [], pinned: Self.post(id: Self.otherPostID)))

        let page = try await service.latest(cursor: nil, limit: 20).get()

        #expect(page.pinned?.id == Self.otherPostID)
        #expect(page.pinned?.author.name == "Ann")
    }

    @Test
    func aPageWithoutAPinnedPostHasNone() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)]))

        #expect(try await service.latest(cursor: nil, limit: 20).get().pinned == nil)
    }

    // MARK: - Problem types

    struct RefusedPage: CustomTestStringConvertible {
        let status: Int
        let type: String
        let expected: FeedError

        var testDescription: String {
            "\(status) \(type)"
        }
    }

    @Test(arguments: [
        RefusedPage(status: 503, type: FeedError.unavailableType, expected: .unavailable),
        RefusedPage(status: 503, type: FeedError.temporarilyUnavailableType, expected: .temporarilyUnavailable(retryAfterSeconds: nil)),
        RefusedPage(status: 503, type: FeedError.readOnlyType, expected: .readOnly),
        RefusedPage(status: 500, type: "/errors/internal", expected: .server(status: 500)),
        // The router's fallback: a backend without the feed's routes (a rollback).
        RefusedPage(status: 404, type: FeedError.routeNotFoundType, expected: .unavailable)
    ])
    func aRefusedPageIsAFailureNeverAnEmptyPage(refused: RefusedPage) async {
        stub(status: refused.status, body: Self.problem(status: refused.status, type: refused.type))

        let result = await service.latest(cursor: nil, limit: 20)

        #expect(result == .failure(refused.expected))
    }

    @Test
    func aTemporaryRefusalCarriesTheServersRetryAfter() async {
        stub(status: 503, body: Self.problem(status: 503, type: FeedError.temporarilyUnavailableType), headers: ["Retry-After": "7"])

        #expect(await service.latest(cursor: nil, limit: 20) == .failure(.temporarilyUnavailable(retryAfterSeconds: 7)))
        #expect(await service.post(id: Self.postID) == .failure(.temporarilyUnavailable(retryAfterSeconds: 7)))
    }

    /// The read window (30 reads per 10 s): a read over it is rate limited with
    /// the server's wait, never an empty page or "not there".
    @Test
    func aReadOverTheWindowIsRateLimited() async {
        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "4"])

        #expect(await service.latest(cursor: nil, limit: 20) == .failure(.rateLimited(retryAfterSeconds: 4)))
        #expect(await service.post(id: Self.postID) == .failure(.rateLimited(retryAfterSeconds: 4)))
        #expect(await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20) == .failure(.rateLimited(retryAfterSeconds: 4)))
        #expect(await service.ownPosts(cursor: nil, limit: 20) == .failure(.rateLimited(retryAfterSeconds: 4)))
        #expect(await service.standing() == .failure(.rateLimited(retryAfterSeconds: 4)))
    }

    /// A `Retry-After` that is not whole seconds (an HTTP date) is dropped, not a failed response.
    @Test
    func aRetryAfterThatIsNotSecondsIsLeftOut() async {
        stub(status: 503, body: Self.problem(status: 503, type: FeedError.temporarilyUnavailableType),
             headers: ["Retry-After": "Wed, 28 Oct 2026 07:28:00 GMT"])

        #expect(await service.latest(cursor: nil, limit: 20) == .failure(.temporarilyUnavailable(retryAfterSeconds: nil)))
    }

    /// Lane B5's read window: every feed `GET` may answer `429` with `Retry-After`,
    /// which is a failure carrying the wait, never an empty page or "not there".
    @Test
    func everyReadOverTheWindowIsRateLimitedWithItsRetryAfter() async {
        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "4"])
        let expected = FeedError.rateLimited(retryAfterSeconds: 4)

        #expect(await service.latest(cursor: nil, limit: 20) == .failure(expected))
        #expect(await service.post(id: Self.postID) == .failure(expected))
        #expect(await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20) == .failure(expected))
        #expect(await service.ownPosts(cursor: nil, limit: 20) == .failure(expected))
        #expect(await service.comments(postID: Self.postID, cursor: nil, limit: 20).failureValue == expected)
        #expect(await service.notices(cursor: nil, limit: 20, language: "en").failureValue == expected)
        #expect(await service.standing().failureValue == expected)
        #expect(await service.notificationSettings().failureValue == expected)
    }

    @Test
    func aMalformedCursorStartsAgain() async {
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))

        #expect(await service.latest(cursor: "stale", limit: 20) == .failure(.invalidCursor))
    }

    @Test
    func aTransportFailureIsNotAnswerData() async {
        stub(status: 200, body: Data("not json".utf8))

        #expect(await service.latest(cursor: nil, limit: 20) == .failure(.transport))
    }

    @Test
    func everyFrozenProblemTypeMapsToItsError() {
        let cases: [RefusedPage] = [
            .init(status: 404, type: FeedError.notFoundType, expected: .notFound),
            .init(status: 503, type: FeedError.unavailableType, expected: .unavailable),
            .init(status: 503, type: FeedError.readOnlyType, expected: .readOnly),
            .init(status: 503, type: FeedError.temporarilyUnavailableType, expected: .temporarilyUnavailable(retryAfterSeconds: nil)),
            .init(status: 422, type: FeedError.idempotencyKeyReusedType, expected: .idempotencyKeyReused),
            .init(status: 409, type: FeedError.rulesNotAcceptedType, expected: .rulesNotAccepted(currentVersion: nil)),
            .init(status: 422, type: FeedError.linkRefusedType, expected: .linkRefused),
            .init(status: 409, type: FeedError.duplicateType, expected: .duplicate),
            .init(status: 403, type: FeedError.suspendedType, expected: .suspended),
            .init(status: 429, type: FeedError.tooManyRequestsType, expected: .rateLimited(retryAfterSeconds: nil)),
            .init(status: 422, type: FeedError.mediaRefusedType, expected: .mediaRefused),
            .init(status: 503, type: FeedError.mediaCheckUnavailableType, expected: .mediaCheckUnavailable),
            .init(status: 403, type: "/errors/forbidden", expected: .forbidden),
            .init(status: 429, type: "/errors/something-newer", expected: .rateLimited(retryAfterSeconds: nil)),
            .init(status: 409, type: "/errors/something-newer", expected: .server(status: 409))
        ]
        for item in cases {
            #expect(FeedError(status: item.status, problemType: item.type) == item.expected, "\(item.testDescription)")
        }
    }

    // MARK: - Post, author

    @Test
    func aPostNotThereIsNotFound() async {
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))

        #expect(await service.post(id: Self.postID) == .failure(.notFound))
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)")
    }

    /// Only the feed's own 404 is final. The router's fallback is a backend
    /// without the feed's routes, "Feed is unavailable"; any other 404 (a
    /// proxy) is a failure with a Retry. Neither is "gone".
    @Test
    func anyOther404IsAFailureNotNotFound() async {
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.routeNotFoundType))

        #expect(await service.post(id: Self.postID) == .failure(.unavailable))
        #expect(await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20) == .failure(.unavailable))
        #expect(await service.ownPosts(cursor: nil, limit: 20) == .failure(.unavailable))

        stub(status: 404, body: Self.problem(status: 404, type: "about:blank"))

        #expect(await service.post(id: Self.postID) == .failure(.server(status: 404)))
        #expect(await service.latest(cursor: nil, limit: 20) == .failure(.server(status: 404)))
    }

    @Test
    func anAuthorNotThereIsNotFound() async {
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))

        #expect(await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20) == .failure(.notFound))
    }

    @Test
    func anAuthorsPostsAreReadByTheirMXID() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)]))

        _ = try await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20).get()

        let path = try #require(lastRequest?.path)
        #expect(path.removingPercentEncoding == "/api/v1/feed/authors/@ann:spiral.md/posts")
    }

    /// The reader's language goes with Latest and an author's posts, so an official post with translations is shown
    /// in the app's language (backend `feed.rs`). It is sent explicitly: the ephemeral session would otherwise send
    /// the device's language list, or nothing.
    @Test
    func latestAndAnAuthorsPostsSendTheAppsLanguage() async throws {
        let service = try makeService(language: "uk")
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)]))

        _ = try await service.latest(cursor: nil, limit: 20).get()
        #expect(lastRequest?.path == "/api/v1/feed/latest")
        #expect(lastRequest?.headers["Accept-Language"] == "uk")

        _ = try await service.authorPosts(userID: "@ann:spiral.md", cursor: nil, limit: 20).get()
        #expect(lastRequest?.path?.removingPercentEncoding == "/api/v1/feed/authors/@ann:spiral.md/posts")
        #expect(lastRequest?.headers["Accept-Language"] == "uk")
    }

    /// Unless told otherwise, the language is the app's own, as for the notices.
    @Test
    func theReadersLanguageIsTheAppsByDefault() async throws {
        let language = try #require(FeedAppLanguage.current)
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)]))

        _ = try await service.latest(cursor: nil, limit: 20).get()

        #expect(lastRequest?.headers["Accept-Language"] == language)
    }

    /// `400` for an invalid or non-local MXID: the author is not there, no crash and no retry loop.
    @Test
    func anAuthorTheServerRefusesIsNotAvailable() async {
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))

        #expect(await service.authorPosts(userID: "@ann:elsewhere.org", cursor: nil, limit: 20) == .failure(.notFound))
    }

    // MARK: - The offline first page

    @Test
    func theFirstPageIsKeptAndALaterPageIsNot() async throws {
        #expect(service.cachedFirstPage() == nil)

        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)], nextCursor: "c1"))
        _ = try await service.latest(cursor: nil, limit: 20).get()
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.otherPostID)]))
        _ = try await service.latest(cursor: "c1", limit: 20).get()

        let cached = try #require(service.cachedFirstPage())
        #expect(cached.items.map(\.id) == [Self.postID])
        #expect(cached.nextCursor == "c1")
    }

    @Test
    func aFailedFirstPageKeepsThePreviousOne() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID)]))
        _ = try await service.latest(cursor: nil, limit: 20).get()
        stub(status: 503, body: Self.problem(status: 503, type: FeedError.temporarilyUnavailableType))
        _ = await service.latest(cursor: nil, limit: 20)

        #expect(service.cachedFirstPage()?.items.map(\.id) == [Self.postID])
    }

    // MARK: - Writes (lane I2)

    @Test
    func aCreateSendsTheTextAndTheSessionsKey() async throws {
        stub(status: 201, body: Data(Self.post(id: Self.postID, state: "held", heldReason: "filter").utf8))
        let key = try #require(UUID(uuidString: "0199D0A1-7C2E-7B44-9A51-3F1E2D4C5B09"))

        let post = try await service.createPost(text: "Hello feed", idempotencyKey: key).get()

        #expect(post.state == .held)
        #expect(post.heldReason == .filter)
        // A held post's notice is not pushed: the badge is read after it (decision 278).
        let requests = FeedURLProtocol.requests.withLock { $0[testID] ?? [] }
        #expect(requests.map(\.path) == ["/api/v1/feed/posts", "/api/v1/feed/notices"])
        let request = try #require(requests.first)
        #expect(request.method == "POST")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["idempotency_key"] as? String == "0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b09")
        let content = try #require(json["content"] as? [String: Any])
        #expect(content["kind"] as? String == "text")
        #expect(content["text"] as? String == "Hello feed")
        #expect(content["sensitive"] == nil)
    }

    /// A retry of a create that already succeeded answers the post it made.
    @Test
    func aReplayedCreateIsThePost() async throws {
        stub(status: 200, body: Data(Self.post(id: Self.postID).utf8))

        let post = try await service.createPost(text: "Hello feed", idempotencyKey: UUID()).get()

        #expect(post.id == Self.postID)
    }

    /// B1b's refusals are told apart by their problem type, not the status they share.
    @Test(arguments: [
        RefusedPage(status: 409, type: FeedError.rulesNotAcceptedType, expected: .rulesNotAccepted(currentVersion: nil)),
        RefusedPage(status: 409, type: FeedError.duplicateType, expected: .duplicate),
        RefusedPage(status: 403, type: FeedError.suspendedType, expected: .suspended),
        RefusedPage(status: 422, type: FeedError.linkRefusedType, expected: .linkRefused),
        RefusedPage(status: 422, type: FeedError.idempotencyKeyReusedType, expected: .idempotencyKeyReused),
        RefusedPage(status: 503, type: FeedError.readOnlyType, expected: .readOnly),
        RefusedPage(status: 422, type: FeedError.unprocessableType, expected: .unprocessable),
        RefusedPage(status: 409, type: "/errors/something-newer", expected: .server(status: 409)),
        RefusedPage(status: 403, type: "/errors/forbidden", expected: .forbidden)
    ])
    func aRefusedCreateIsItsProblemType(refused: RefusedPage) async {
        stub(status: refused.status, body: Self.problem(status: refused.status, type: refused.type))

        let result = await service.createPost(text: "Hello feed", idempotencyKey: UUID())

        #expect(result == .failure(refused.expected))
    }

    @Test
    func aRateLimitedCreateCarriesRetryAfter() async {
        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "42"])

        let result = await service.createPost(text: "Hello feed", idempotencyKey: UUID())

        #expect(result == .failure(.rateLimited(retryAfterSeconds: 42)))
    }

    @Test
    func theStandingDecodes() async throws {
        stub(status: 200, body: Data(#"""
        {"rules_version":"2026-10-27","rules_accepted":true,"posts_per_day":30,"posts_today":2,
         "comments_per_day":200,"comments_today":7,"suspended_until":null,"something_newer":1}
        """#.utf8))

        let standing = try await service.standing().get()

        #expect(standing.rulesVersion == "2026-10-27")
        #expect(standing.rulesAccepted)
        #expect(standing.postsPerDay == 30)
        #expect(standing.commentsPerDay == 200)
        #expect(standing.commentsToday == 7)
        #expect(standing.postsToday == 2)
        #expect(standing.suspendedUntil == nil)
        #expect(lastRequest?.method == "GET")
        #expect(lastRequest?.path == "/api/v1/feed/me/standing")
    }

    @Test
    func anAcceptSendsTheAppsVersion() async throws {
        stub(status: 200, body: Data(#"{"rules_version":"2026-10-27","rules_accepted":true,"posts_today":0}"#.utf8))

        let standing = try await service.acceptRules(version: FeedRules.version).get()

        #expect(standing.rulesAccepted)
        #expect(standing.postsPerDay == nil)
        let request = try #require(lastRequest)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/feed/rules/accept")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["version"] as? String == FeedRules.version)
    }

    /// The `rules_version` extension member names the server's current rules.
    @Test
    func aRulesRefusalCarriesTheServersVersion() async {
        let body = Data(#"{"type":"/errors/feed-rules-not-accepted","title":"x","status":409,"detail":"x","rules_version":"2026-11-02"}"#.utf8)
        stub(status: 409, body: body)
        #expect(await service.acceptRules(version: FeedRules.version).failureValue == .rulesNotAccepted(currentVersion: "2026-11-02"))

        stub(status: 409, body: body)
        #expect(await service.createPost(text: "Hello feed", idempotencyKey: UUID()) == .failure(.rulesNotAccepted(currentVersion: "2026-11-02")))
    }

    @Test
    func aDeleteIsGoneOnlyWhenTheServerSaysSo() async {

        stub(status: 500, body: Self.problem(status: 500, type: "/errors/internal"))
        #expect(await service.deletePost(id: Self.postID).failureValue == .server(status: 500))

        stub(status: 204, body: Data())
        #expect(await service.deletePost(id: Self.postID).failureValue == nil)
        #expect(lastRequest?.method == "DELETE")
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)")

        // "No post of yours with this id": already gone.
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))
        #expect(await service.deletePost(id: Self.postID).failureValue == .notFound)
    }

    /// The router's fallback 404 (a backend without the route, a proxy) and a
    /// 400 deleted nothing: a failure with a Retry, never "Post deleted".
    @Test
    func aDeleteAnsweredByAnythingButTheFeedIsNotDeleted() async {

        stub(status: 404, body: Self.problem(status: 404, type: FeedError.routeNotFoundType))
        #expect(await service.deletePost(id: Self.postID).failureValue == .unavailable)

        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))
        #expect(await service.deletePost(id: Self.postID).failureValue == .server(status: 400))

    }

    /// A 429 the spec does not list (a limiter in front of the route) is still
    /// over a window: it keeps its `Retry-After` and deletes or accepts nothing (L-d).
    @Test
    func anUndocumented429KeepsItsRetryAfter() async {

        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "7"])
        #expect(await service.deletePost(id: Self.postID).failureValue == .rateLimited(retryAfterSeconds: 7))

        stub(status: 429, body: Data(), headers: ["Retry-After": "12"])
        #expect(await service.deletePost(id: Self.postID).failureValue == .rateLimited(retryAfterSeconds: 12), "No problem body: the status alone")

        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "9"])
        #expect(await service.acceptRules(version: FeedRules.version).failureValue == .rateLimited(retryAfterSeconds: 9))

        stub(status: 429, body: Data())
        #expect(await service.acceptRules(version: FeedRules.version).failureValue == .rateLimited(retryAfterSeconds: nil))

    }

    @Test
    func ownPostsReadEveryStateOfTheCallersPosts() async throws {
        stub(status: 200, body: Self.page(items: [Self.post(id: Self.postID, state: "held", heldReason: "filter"),
                                                  Self.post(id: Self.otherPostID, state: "removed")]))

        let page = try await service.ownPosts(cursor: nil, limit: 20).get()

        #expect(page.items.map(\.state) == [.held, .removed])
        #expect(lastRequest?.path == "/api/v1/feed/me/posts")
        #expect(lastRequest?.query?.contains("state") != true)
    }

    @Test
    func theDraftIsKeptUntilDeleted() {
        #expect(service.draft() == nil)
        let draft = FeedDraft(text: "Not yet", idempotencyKey: UUID())

        service.saveDraft(draft)
        #expect(service.draft() == draft)
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(component: "spiral-feed-draft.json").path()))

        service.deleteDraft()
        #expect(service.draft() == nil)
        service.deleteDraft()
    }

    // MARK: - Engagement (lane I3)

    @Test
    func aLikeTakesTheServersCountAndTellsTheLists() async throws {
        stub(status: 200, body: Data(#"{"likes":12,"liked":true}"#.utf8))

        let likes = try await service.setLiked(true, postID: Self.postID).get()

        #expect(likes == FeedLikes(likes: 12, liked: true))
        #expect(lastRequest?.method == "PUT")
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)/like")

        stub(status: 200, body: Data(#"{"likes":11,"liked":false}"#.utf8))
        _ = try await service.setLiked(false, postID: Self.postID).get()
        #expect(lastRequest?.method == "DELETE")
    }

    /// A refused like is a failure with what refused it.
    @Test
    func aRefusedLikeSaysWhyAndTellsNobody() async {

        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "40"])
        #expect(await service.setLiked(true, postID: Self.postID).failureValue == .rateLimited(retryAfterSeconds: 40))

        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))
        #expect(await service.setLiked(true, postID: Self.postID).failureValue == .notFound)

        stub(status: 404, body: Self.problem(status: 404, type: FeedError.routeNotFoundType))
        #expect(await service.setLiked(true, postID: Self.postID).failureValue == .unavailable, "A backend without the feed")

    }

    @Test
    func aHideLeavesTheListsOnlyOnceTheServerHidIt() async {

        stub(status: 503, body: Self.problem(status: 503, type: FeedError.unavailableType))
        #expect(await service.setHidden(true, postID: Self.postID).failureValue == .unavailable)

        stub(status: 204, body: Data())
        #expect(await service.setHidden(true, postID: Self.postID).failureValue == nil)
        #expect(lastRequest?.method == "PUT")
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)/hide")

        stub(status: 204, body: Data())
        #expect(await service.setHidden(false, postID: Self.postID).failureValue == nil)
        #expect(lastRequest?.method == "DELETE")
    }

    @Test
    func commentsDecodeWithTheirReplyStateAndSensitiveFlag() async throws {
        let reply = #","reply_to":{"id":"01933F2B-0000-7000-8000-000000000001","author":{"mxid":"@bob:spiral.md","official":false}}"#
        stub(status: 200, body: Data(#"""
        {"items":[\#(Self.comment(id: "01933f2b-0000-7000-8000-000000000001")),
                  \#(Self.comment(id: "01933f2b-0000-7000-8000-000000000002", state: "held", extra: #","held_reason":"filter","sensitive":true"# + reply)),
                  \#(Self.comment(id: "01933f2b-0000-7000-8000-000000000003", state: "archived", extra: #","votes":3"#))],
         "next_cursor":"c2"}
        """#.utf8))

        let page = try await service.comments(postID: Self.postID, cursor: "c1", limit: 20).get()

        #expect(page.nextCursor == "c2")
        #expect(page.items.map(\.state) == [.visible, .held, .other("archived")])
        #expect(page.items.map(\.isSensitive) == [false, true, false], "Absent is not sensitive (decision 265)")
        #expect(page.items[1].heldReason == .filter)
        #expect(page.items[1].replyTo?.id == "01933f2b-0000-7000-8000-000000000001")
        #expect(page.items[1].replyTo?.author.displayName == "bob")
        #expect(page.items[0].canDelete)
        #expect(!page.items[0].isAuthor)
        #expect(lastRequest?.path == "/api/v1/feed/posts/\(Self.postID)/comments")
        #expect(lastRequest?.query?.contains("cursor=c1") == true)
    }

    @Test
    func aCommentSendsItsKeyAndReplyAndAReplayIsTheSameComment() async throws {
        let key = UUID()
        stub(status: 201, body: Data(Self.comment(id: "01933f2b-0000-7000-8000-000000000009").utf8))

        let comment = try await service.createComment(postID: Self.postID, text: "Nice!", replyTo: "01933f2b-0000-7000-8000-000000000001",
                                                      idempotencyKey: key).get()

        #expect(comment.id == "01933f2b-0000-7000-8000-000000000009")
        let request = try #require(lastRequest)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/feed/posts/\(Self.postID)/comments")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["text"] as? String == "Nice!")
        #expect(json["reply_to"] as? String == "01933f2b-0000-7000-8000-000000000001")
        #expect(json["idempotency_key"] as? String == key.uuidString.lowercased())

        stub(status: 200, body: Data(Self.comment(id: "01933f2b-0000-7000-8000-000000000009").utf8))
        #expect(try await service.createComment(postID: Self.postID, text: "Nice!", replyTo: nil, idempotencyKey: key).get().id == comment.id)
    }

    @Test
    func aCommentRefusalIsToldApartByItsType() async {
        let cases = [RefusedPage(status: 404, type: FeedError.notFoundType, expected: .notFound),
                     RefusedPage(status: 404, type: FeedError.routeNotFoundType, expected: .unavailable),
                     RefusedPage(status: 422, type: FeedError.unprocessableType, expected: .unprocessable),
                     RefusedPage(status: 403, type: FeedError.suspendedType, expected: .suspended),
                     RefusedPage(status: 503, type: FeedError.readOnlyType, expected: .readOnly)]
        for refused in cases {
            stub(status: refused.status, body: Self.problem(status: refused.status, type: refused.type))
            #expect(await service.createComment(postID: Self.postID, text: "x", replyTo: nil, idempotencyKey: UUID()).failureValue == refused.expected)
        }
    }

    @Test
    func aCommentDeleteIsDoneOnlyOnTheFeedsAnswer() async {
        stub(status: 204, body: Data())
        #expect(await service.deleteComment(id: "01933f2b-0000-7000-8000-000000000001").failureValue == nil)
        #expect(lastRequest?.method == "DELETE")
        #expect(lastRequest?.path == "/api/v1/feed/comments/01933f2b-0000-7000-8000-000000000001")

        stub(status: 404, body: Self.problem(status: 404, type: FeedError.notFoundType))
        #expect(await service.deleteComment(id: "01933f2b-0000-7000-8000-000000000001").failureValue == .notFound)

        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))
        #expect(await service.deleteComment(id: "x").failureValue == .server(status: 400))
    }

    @Test
    func theCommentSwitchSendsOnlyItsFieldAndTellsTheLists() async throws {
        stub(status: 200, body: Data(Self.post(id: Self.postID).replacing(#""comments_enabled":true"#, with: #""comments_enabled":false"#).utf8))

        let post = try await service.setCommentsEnabled(false, postID: Self.postID).get()

        #expect(!post.commentsEnabled)
        let request = try #require(lastRequest)
        #expect(request.method == "PATCH")
        #expect(request.path == "/api/v1/feed/posts/\(Self.postID)")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json.keys.sorted() == ["comments_enabled"])
        #expect(json["comments_enabled"] as? Bool == false)
    }

    @Test
    func aShareSendsTheRoomAndLanguageAndReadsTheServersMessage() async throws {
        stub(status: 200, body: Data(#"""
        {"content":{"msgtype":"m.text","body":"Hello\n\nПереглянути допис у Spiral: https://spiral.md/feed/x"},
         "link":"https://spiral.md/feed/x","shares":3}
        """#.utf8))

        let share = try await service.share(postID: Self.postID, roomID: "!room:spiral.md", language: "uk").get()

        #expect(share == FeedShareMessage(body: "Hello\n\nПереглянути допис у Spiral: https://spiral.md/feed/x", shares: 3))
        let request = try #require(lastRequest)
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/feed/posts/\(Self.postID)/share")
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["room_id"] as? String == "!room:spiral.md")
        #expect(json["lang"] as? String == "uk")
    }

    @Test
    func aShareIntoABridgedRoomIsRefusedAndCountsNothing() async {
        stub(status: 422, body: Self.problem(status: 422, type: FeedError.shareBridgedRoomType))

        #expect(await service.share(postID: Self.postID, roomID: "!tg:spiral.md", language: nil).failureValue == .shareBridgedRoom)
    }

    /// The comment cap is additive: an older server's standing decodes without it.
    @Test
    func theCommentCapIsReadWhenTheServerSendsIt() async throws {
        stub(status: 200, body: Data(#"{"rules_version":"2026-10-27","rules_accepted":true,"posts_today":0,"comments_per_day":20,"comments_today":20}"#.utf8))
        let capped = try await service.standing().get()
        #expect(capped.commentsPerDay == 20)
        #expect(capped.commentsToday == 20)
        #expect(capped.hasReachedCommentCap)

        stub(status: 200, body: Data(#"{"rules_version":"2026-10-27","rules_accepted":true,"posts_today":0}"#.utf8))
        let uncapped = try await service.standing().get()
        #expect(uncapped.commentsPerDay == nil)
        #expect(uncapped.commentsToday == nil)
        #expect(!uncapped.hasReachedCommentCap)
    }

    // MARK: - Helpers

    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"
    private static let otherPostID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b03"

    private static func post(id: String,
                             kind: String = "text_images",
                             state: String = "visible",
                             heldReason: String? = nil,
                             author: String = #"{"mxid":"@ann:spiral.md","name":"Ann","avatar_mxc":"mxc://spiral.md/avatar","bio":"Gardener","official":false}"#,
                             extra: String = "") -> String {
        let held = heldReason.map { #","held_reason":"\#($0)""# } ?? ""
        return #"""
        {"id":"\#(id)","created_at":"2026-10-27T10:00:00.123456Z","author":\#(author),
         "content":{"kind":"\#(kind)","text":"Hello https://example.org","sensitive":true\#(extra),
                    "media":[{"id":"0199d0a1-7c2e-7b44-9a51-3f1e2d4c5b02","mxc":"mxc://spiral.md/a","mime":"image/jpeg",
                              "width":2048,"height":1536,"blurhash":"LEHV6nWB2yk8pyo0adR*.7kCMdnj","alt":"A birch wood"}]},
         "counts":{"likes":0,"comments":0,"shares":0},"viewer":{"liked":false,"hidden":false,"is_author":false},
         "state":"\#(state)"\#(held),"comments_enabled":true}
        """#
    }

    private static func comment(id: String, state: String = "visible", extra: String = "") -> String {
        #"""
        {"id":"\#(id)","post_id":"\#(postID)","author":{"mxid":"@ann:spiral.md","name":"Ann","official":false},
         "text":"Nice","created_at":"2026-10-27T10:05:00Z","state":"\#(state)",
         "viewer":{"is_author":false,"can_delete":true}\#(extra)}
        """#
    }

    private static func page(items: [String], nextCursor: String? = nil, pinned: String? = nil) -> Data {
        var fields = [#""items":[\#(items.joined(separator: ","))]"#]
        if let nextCursor { fields.append(#""next_cursor":"\#(nextCursor)""#) }
        if let pinned { fields.append(#""pinned":\#(pinned)"#) }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private static func problem(status: Int, type: String) -> Data {
        Data(#"{"type":"\#(type)","title":"x","status":\#(status),"detail":"x"}"#.utf8)
    }

    /// A second service on this test's stubs, reading in `language`.
    private func makeService(language: String?) throws -> FeedService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        return FeedService(client: client, cacheDirectory: nil, language: language)
    }

    private func stub(status: Int, body: Data, headers: [String: String] = [:]) {
        FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body, headers: headers) }
    }

    private var lastRequest: FeedURLProtocol.Recorded? {
        FeedURLProtocol.requests.withLock { $0[testID]?.last }
    }
}

/// Answers each test from its own stub, told apart by a header every request
/// of that test's session carries, and keeps what each request asked for.
/// Shared by the feed's wire suites.
nonisolated class FeedURLProtocol: URLProtocol {
    struct Stub {
        let status: Int
        let body: Data
        var headers: [String: String] = [:]
        /// Lane I5: the stream's `text/event-stream`; JSON (or a problem) otherwise.
        var contentType: String?
        /// A server that never answers: the request ends only when it is cancelled.
        var hangs = false
    }

    struct Recorded {
        let method: String?
        let path: String?
        let query: String?
        var body: Data?
        var headers: [String: String] = [:]
    }

    static let testIDHeader = "X-Test-ID"
    static let stubs = Mutex<[String: Stub]>([:])
    /// An answer for one path of a test, ahead of its general stub.
    static let pathStubs = Mutex<[String: [String: Stub]]>([:])
    static let requests = Mutex<[String: [Recorded]]>([:])

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let testID = request.value(forHTTPHeaderField: Self.testIDHeader) ?? ""
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.requests.withLock { $0[testID, default: []].append(Recorded(method: request.httpMethod, path: url.path(), query: url.query(), body: body,
                                                                         headers: request.allHTTPHeaderFields ?? [:])) }
        let stub = Self.pathStubs.withLock { $0[testID]?[url.path()] } ?? Self.stubs.withLock { $0[testID] } ?? Stub(status: 500, body: Data())
        guard !stub.hangs else { return }

        let contentType = stub.contentType ?? ((200..<300).contains(stub.status) ? "application/json" : "application/problem+json")
        guard let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": contentType].merging(stub.headers) { $1 }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        // A streamed body is written while it is read: `hasBytesAvailable` can be
        // false before the first bytes land, so read until the end of the stream.
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
