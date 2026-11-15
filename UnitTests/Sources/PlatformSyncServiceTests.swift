//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync (decision 289, contract § 4–5). The one
// stream as the app reads it off the wire: `ready`, `changes` and `limited`,
// the resume position in `since` and `Last-Event-ID`, the refusals, and a
// kind or frame newer than this build skipped rather than failing (decision 96).
//

import AgentPlatformClient
import Foundation
import OpenAPIRuntime
@testable import Spiral
import Testing

@MainActor
struct PlatformSyncServiceTests {
    private let testID = UUID().uuidString
    private let service: PlatformSyncService

    init() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedURLProtocol.self]
        configuration.httpAdditionalHeaders = [FeedURLProtocol.testIDHeader: testID]
        let client = try AgentPlatformClient(serverURL: "https://platform.test",
                                             authProvider: StaticAuthTokenProvider(token: "mat_test"),
                                             urlSession: URLSession(configuration: configuration))
        service = PlatformSyncService(client: client)
    }

    @Test
    func theStreamYieldsTheFramesThisBuildKnows() async throws {
        stub(status: 200, body: Data("""
        event: ready
        data: {"position":"p0","fresh":true}

        : keepalive

        id: p1
        event: changes
        data: {"position":"p1","changes":[{"kind":"feed.counts","post":"\(Self.postID.uppercased())","likes":3,"comments":1,"shares":0},{"kind":"agent.updated","agent":"A1","space":"s1"},{"kind":"approval.changed","approval":"ap1"},{"kind":"agent.tools","agent":"a1"},{"kind":"agent.rooms","agent":"a1","room":"!r:spiral.md"},{"kind":"notification.seen"},{"kind":"feed.counts","post":"\(Self.postID)"},{"kind":"feed.post_published","post":"\(Self.postID)","author":"@ann:spiral.md"}]}

        event: something_newer
        data: {}

        event: limited
        data: {"position":"p2"}


        """.utf8), contentType: "text/event-stream")

        let events = try await collect(service.open(since: nil).get())

        #expect(events == [.ready(position: "p0", fresh: true),
                           .changes(position: "p1", changes: [.feed(.counts(postID: Self.postID, counts: FeedCounts(likes: 3, comments: 1, shares: 0))),
                                                              // The Agents tab's kinds, uuids lower-cased (lane I7).
                                                              .agents(.agentUpdated(agentID: "a1", spaceID: "s1")),
                                                              .agents(.approvalChanged(approvalID: "ap1")),
                                                              // `agent.tools` without its room is skipped.
                                                              .other(kind: "agent.tools"),
                                                              .agents(.agentRooms(agentID: "a1", roomID: "!r:spiral.md")),
                                                              .agents(.notificationSeen),
                                                              // A feed kind missing what it must name is skipped like a newer one.
                                                              .other(kind: "feed.counts"),
                                                              .feed(.postPublished(postID: Self.postID, authorID: "@ann:spiral.md"))]),
                           .limited(position: "p2")])
        let request = try #require(lastRequest)
        #expect(request.path == "/api/v1/sync")
        #expect(request.query == nil)
        #expect(request.headers["Last-Event-ID"] == nil)
        #expect(request.headers["Authorization"] == "Bearer mat_test")
    }

    /// Resume (H2): the last position goes in `since` and in `Last-Event-ID`, the same value.
    @Test
    func aResumeSendsTheLastPosition() async throws {
        stub(status: 200, body: Data("id: 8125-4417\nevent: ready\ndata: {\"position\":\"8125-4417\",\"fresh\":false}\n\n".utf8),
             contentType: "text/event-stream")

        let events = try await collect(service.open(since: "8125-4417").get())

        #expect(events == [.ready(position: "8125-4417", fresh: false)])
        let request = try #require(lastRequest)
        #expect(request.headers["Last-Event-ID"] == "8125-4417")
        #expect(request.query == "since=8125-4417")
    }

    @Test
    func theRefusalsSayWhatTheyAre() async {
        stub(status: 429, body: Self.problem(status: 429, type: FeedError.tooManyRequestsType), headers: ["Retry-After": "7"])
        #expect(await service.open(since: nil).failureValue == .rateLimited(retryAfterSeconds: 7))

        stub(status: 503, body: Self.problem(status: 503, type: "/errors/service-unavailable"))
        #expect(await service.open(since: nil).failureValue == .temporarilyUnavailable(retryAfterSeconds: nil))

        // A position this server did not give out: start without one.
        stub(status: 400, body: Self.problem(status: 400, type: "/errors/validation-failed"))
        #expect(await service.open(since: "8125-4417").failureValue == .invalidPosition)

        // The router's fallback: a backend without the route.
        stub(status: 404, body: Self.problem(status: 404, type: FeedError.routeNotFoundType))
        #expect(await service.open(since: nil).failureValue == .unavailable)

        // Any other 404 (a proxy) is retried, never "no sync".
        stub(status: 404, body: Data())
        #expect(await service.open(since: nil).failureValue == .server(status: 404))
    }

    /// One more try after a `401`, as every platform call: the SDK may be landing a refreshed token.
    @Test
    func anUnauthorizedOpenIsTriedOnceMore() async {
        stub(status: 401, body: Self.problem(status: 401, type: "/errors/unauthorized"))

        #expect(await service.open(since: nil).failureValue == .unauthorized)
        #expect(FeedURLProtocol.requests.withLock { $0[testID]?.count } == 2)
    }

    // MARK: - Frames

    /// Review I6 L2: the background cancelling an open is not an error to log; a dropped connection is.
    @Test
    func aCancelledOpenIsToldFromAFailedOne() {
        let wrapped = { (error: any Error) in
            ClientError(operationID: "getSync", operationInput: "", causeDescription: "Transport threw an error.", underlyingError: error)
        }
        #expect(PlatformSyncService.isCancellation(CancellationError()))
        #expect(PlatformSyncService.isCancellation(URLError(.cancelled)))
        #expect(PlatformSyncService.isCancellation(wrapped(URLError(.cancelled))))
        #expect(PlatformSyncService.isCancellation(wrapped(CancellationError())))
        #expect(!PlatformSyncService.isCancellation(URLError(.networkConnectionLost)))
        #expect(!PlatformSyncService.isCancellation(wrapped(URLError(.notConnectedToInternet))))
    }

    @Test
    func eachFeedKindIsRead() {
        let frame = """
        {"position":7,"changes":[
          {"kind":"feed.post_published","post":"P1","author":"@ann:spiral.md"},
          {"kind":"feed.post_state","post":"p1","state":"held"},
          {"kind":"feed.post_state","post":"p1","state":"gone"},
          {"kind":"feed.post_updated","post":"p1"},
          {"kind":"feed.counts","post":"p1","likes":1,"comments":2,"shares":3,"newer":true},
          {"kind":"feed.comment_added","post":"p1","comment":"C1","parent":null},
          {"kind":"feed.comment_removed","post":"p1","comment":"c1"},
          {"kind":"feed.viewer_like","post":"p1","liked":true},
          {"kind":"feed.hidden","post":"p1"},
          {"kind":"feed.unhidden","post":"p1"},
          {"kind":"feed.blocks"},
          {"kind":"feed.activity"},
          {"kind":"feed.notice"}
        ]}
        """
        let event = PlatformSyncEvent(event: "changes", data: frame)

        #expect(event == .changes(position: "7", changes: [
            .feed(.postPublished(postID: "p1", authorID: "@ann:spiral.md")),
            .feed(.postState(postID: "p1", state: .held)),
            .feed(.postState(postID: "p1", state: .other("gone"))),
            .feed(.postUpdated(postID: "p1")),
            .feed(.counts(postID: "p1", counts: FeedCounts(likes: 1, comments: 2, shares: 3))),
            .feed(.commentAdded(postID: "p1", commentID: "c1")),
            .feed(.commentRemoved(postID: "p1", commentID: "c1")),
            .feed(.viewerLike(postID: "p1", liked: true)),
            .feed(.hidden(postID: "p1")),
            .feed(.unhidden(postID: "p1")),
            .feed(.blocks),
            .feed(.activity),
            .feed(.notice)
        ]))
    }

    /// Decision 96: a newer kind is another area's, a change that cannot be read is skipped, never the frame.
    @Test
    func aNewerOrUnreadableChangeDegrades() {
        let frame = #"{"position":"p","changes":[{"kind":"feed.mentions","post":"p1"},{"post":"no kind"},{"kind":"feed.viewer_like","post":"p1"},{"kind":"feed.blocks"}]}"#

        #expect(PlatformSyncEvent(event: "changes", data: frame)
            == .changes(position: "p", changes: [.other(kind: "feed.mentions"), .other(kind: "feed.viewer_like"), .feed(.blocks)]))
        #expect(PlatformSyncEvent(event: "ready", data: #"{"fresh":true}"#) == nil)
        #expect(PlatformSyncEvent(event: "poll_votes", data: "{}") == nil)
        #expect(PlatformSyncEvent(event: nil, data: #"{"position":"p"}"#) == nil)
        #expect(PlatformSyncEvent(event: "limited", data: nil) == nil)
    }

    // MARK: - Helpers

    private static let postID = "01933f2a-7c2e-7b44-9a51-3f1e2d4c5b01"

    private func collect(_ stream: PlatformSyncEventStream) async throws -> [PlatformSyncEvent] {
        var events: [PlatformSyncEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func stub(status: Int, body: Data, headers: [String: String] = [:], contentType: String? = nil) {
        FeedURLProtocol.stubs.withLock { $0[testID] = .init(status: status, body: body, headers: headers, contentType: contentType) }
    }

    private var lastRequest: FeedURLProtocol.Recorded? {
        FeedURLProtocol.requests.withLock { $0[testID]?.last }
    }

    private static func problem(status: Int, type: String) -> Data {
        Data(#"{"type":"\#(type)","title":"x","status":\#(status),"detail":"x"}"#.utf8)
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
