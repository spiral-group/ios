//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync (decision 289, contract § 7). One stream per
// session: it resumes from the last position, `ready.fresh` and `limited`
// make the stores read again what is shown, the server's end reconnects at
// once, a failure waits, the background closes it, and the changes reach the
// feed's store by their kind.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct PlatformSyncTests {
    private let feedService = FeedServiceMock()
    private let service = PlatformSyncServiceMock()
    private let store: FeedStore
    private let opened = Opened()

    init() {
        store = FeedStore(feedService: feedService, currentUserID: "@me:spiral.md")
        feedService.activityCursorLimitReturnValue = .success(FeedActivityPage(items: [], nextCursor: nil, unread: 0))
        feedService.noticesCursorLimitLanguageReturnValue = .success(FeedNoticePage(items: [], nextCursor: nil, unread: 0))
    }

    /// The position of every frame, `ready`'s included, is where the next stream starts: `since` and `Last-Event-ID` (the service's test).
    @Test
    func aStreamTheServerEndedResumesAtOnceFromTheLastPosition() async throws {
        let sync = makeSync(streams: [[.ready(position: "p0", fresh: true),
                                       .changes(position: "p1", changes: [])],
                                      [.ready(position: "p1", fresh: false)]])
        sync.start()
        try await eventually { opened.sinces.count == 3 }

        #expect(opened.sinces == [nil, "p1", "p1"])
        #expect(sync.position == "p1")
        sync.stop()
    }

    /// A position the server refuses (`400`) starts fresh at once: `ready.fresh` then re-reads what is shown.
    @Test
    func aRefusedPositionStartsFresh() async throws {
        let sync = makeSync(streams: [[.ready(position: "p0", fresh: true)]], backoff: { _ in .seconds(3600) }, failures: [.invalidPosition])
        sync.start()
        try await eventually { opened.sinces.count == 3 }

        #expect(opened.sinces == [nil, "p0", nil])
        sync.stop()
    }

    /// The server's healthy end every 30 minutes reconnects at once without "Updating…" at the top.
    @Test
    func theServersEndReconnectsWithoutSayingSo() async throws {
        let sync = makeSync(streams: [[.ready(position: "p0", fresh: false)]])
        sync.start()
        try await eventually { opened.sinces.count == 2 }

        #expect(sync.connectionState == .live)
        #expect(store.syncStatus == nil)
        sync.stop()
    }

    /// A stream that ends before `ready` (or right after it) is a failure: it waits, longer each time.
    @Test
    func aFailedStreamWaitsBeforeTheNextAttempt() async throws {
        let sync = makeSync(streams: [], backoff: { _ in .seconds(3600) }, failures: [.transport])
        sync.start()
        try await eventually { sync.connectionState == .waiting(attempt: 1, isOffline: true) }

        #expect(opened.sinces.count == 1)
        #expect(store.syncStatus == .noConnection)
        sync.stop()
        #expect(store.syncStatus == nil)
    }

    /// Review I6 L1: a 429 or a 5xx is the server, not the connection: the wait says "Updating…", not "No connection".
    @Test(arguments: [PlatformSyncError.rateLimited(retryAfterSeconds: nil), .server(status: 500), .temporarilyUnavailable(retryAfterSeconds: nil)])
    func theServersRefusalWaitsAsUpdating(error: PlatformSyncError) async throws {
        let sync = makeSync(streams: [], backoff: { _ in .seconds(3600) }, failures: [error])
        sync.start()
        try await eventually { sync.connectionState == .waiting(attempt: 1, isOffline: false) }

        #expect(store.syncStatus == .updating)
        sync.stop()
    }

    /// A stream that broke off is the network; one the server ended before `ready` is not.
    @Test
    func aBrokenStreamWaitsAsOfflineAndAnEarlyEndDoesNot() async throws {
        let broken = makeSync(streams: [], backoff: { _ in .seconds(3600) }, brokenStreams: 1)
        broken.start()
        try await eventually { broken.connectionState == .waiting(attempt: 1, isOffline: true) }
        #expect(store.syncStatus == .noConnection)
        broken.stop()

        let ended = makeSync(streams: [[]], backoff: { _ in .seconds(3600) })
        ended.start()
        try await eventually { ended.connectionState == .waiting(attempt: 1, isOffline: false) }
        #expect(store.syncStatus == .updating)
        ended.stop()
    }

    @Test
    func theServersWaitIsKeptOverTheBackoff() {
        let backoff: (Int) -> Duration = { _ in .seconds(1) }
        #expect(PlatformSync.wait(after: .rateLimited(retryAfterSeconds: 9), failures: 1, backoff: backoff) == .seconds(9))
        #expect(PlatformSync.wait(after: .temporarilyUnavailable(retryAfterSeconds: nil), failures: 1, backoff: backoff) == .seconds(1))
        #expect(PlatformSync.defaultBackoff(1) == .seconds(1))
        #expect(PlatformSync.defaultBackoff(3) == .seconds(4))
        #expect(PlatformSync.defaultBackoff(20) == .seconds(60))
    }

    /// No sync on this backend: nothing is opened again until the app returns.
    @Test
    func aBackendWithoutSyncIsLeftAlone() async throws {
        let sync = makeSync(streams: [], failures: [.unavailable])
        sync.start()
        try await eventually { opened.sinces.count == 1 }
        try await Task.sleep(for: .milliseconds(50))

        #expect(opened.sinces.count == 1)
        #expect(sync.connectionState == .idle)
    }

    /// Foreground only: the background closes the stream, the return opens it from where it was.
    @Test
    func theBackgroundClosesAndTheReturnResumes() async throws {
        let sync = makeSync(streams: [[.ready(position: "p4", fresh: true)]], hangsAfterStreams: true)
        sync.start()
        try await eventually { sync.connectionState == .live }

        sync.appDidEnterBackground()
        #expect(sync.connectionState == .idle)
        sync.appDidBecomeActive()
        try await eventually { opened.sinces.count == 2 }

        #expect(opened.sinces == [nil, "p4"])
        sync.stop()
    }

    @Test
    func aLaunchIntoTheBackgroundOpensNothing() async throws {
        let sync = PlatformSync(service: service, feedStore: store, isApplicationInBackground: { true })
        service.openSinceClosure = { [opened] since in
            opened.sinces.append(since)
            return .failure(.transport)
        }
        sync.start()
        try await Task.sleep(for: .milliseconds(50))

        #expect(opened.sinces.isEmpty)
    }

    // MARK: - Routing

    /// `ready` without `since` and `limited` both mean "read again what is shown" (H1, H4); a resumed `ready` does not.
    @Test
    func freshAndLimitedReadAgainWhatIsShownAndAResumeDoesNot() async {
        let reads = Counter()
        let owner = NSObject()
        store.setList(.ownPosts, FeedStoreList(ids: [], nextCursor: nil))
        store.show(.ownPosts, by: owner) {
            reads.count += 1
            return true
        }
        let sync = makeSync(streams: [])

        sync.handle(.ready(position: "p0", fresh: false))
        await store.settle()
        #expect(reads.count == 0)

        sync.handle(.ready(position: "p0", fresh: true))
        await store.settle()
        #expect(reads.count == 1)

        sync.handle(.limited(position: "p9"))
        await store.settle()
        #expect(reads.count == 2)
        #expect(sync.position == "p9")
    }

    /// Changes go to the feed's store by kind; another area's wait for its store.
    @Test
    func feedChangesReachTheStore() {
        store.upsert([FeedPreviewData.textPost])
        let sync = makeSync(streams: [])

        sync.handle(.changes(position: "p2", changes: [.other(kind: "agent.updated"),
                                                       .feed(.counts(postID: FeedPreviewData.textPost.id, counts: FeedCounts(likes: 5, comments: 6, shares: 7)))]))

        #expect(store.post(FeedPreviewData.textPost.id)?.counts == FeedCounts(likes: 5, comments: 6, shares: 7))
        #expect(sync.position == "p2")
    }

    /// The Agents tab's kinds reach its store (lane I7); `ready.fresh` reads
    /// again what it shows, and its screens hear the connection too.
    @Test
    func agentsChangesReachTheAgentsStore() async {
        let platform = AgentPlatformServiceMock()
        platform.fetchAgentUsageAgentIDReturnValue = .success(AgentUsage(current: .init(period: .week, startsAt: .now, resetsAt: .now, usedPercent: 1, limitReached: false, categories: []), days: []))
        let agentsStore = AgentsStore(service: platform)
        let owner = NSObject()
        agentsStore.show(.usage(agentID: "a1"), by: owner)
        await agentsStore.settle()
        let sync = PlatformSync(service: service, feedStore: store, agentsStore: agentsStore, backoff: { _ in .milliseconds(1) },
                                minimumHealthyLife: .zero, isApplicationInBackground: { false })

        sync.handle(.changes(position: "p1", changes: [.agents(.agentUsage(agentID: "a1"))]))
        await agentsStore.settle()
        #expect(platform.fetchAgentUsageAgentIDCallsCount == 2)

        sync.handle(.ready(position: "p2", fresh: true))
        #expect(agentsStore.connectionState == .live)
        await agentsStore.settle()
        #expect(platform.fetchAgentUsageAgentIDCallsCount == 3)

        sync.handle(.limited(position: "p3"))
        await agentsStore.settle()
        #expect(platform.fetchAgentUsageAgentIDCallsCount == 4)
    }

    /// Review H1: a failed read of what waits (the tab badge) is read again on
    /// the next resumed `ready` and on the return to the foreground, not only on the next change.
    @Test
    func aFailedBadgeReadIsReadAgainOnTheNextReadyAndOnForeground() async {
        let platform = AgentPlatformServiceMock()
        platform.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 503))
        let agentsStore = AgentsStore(service: platform, retryDelays: [])
        let owner = NSObject()
        agentsStore.show(.needsAction, by: owner)
        await agentsStore.settle()
        let sync = PlatformSync(service: service, feedStore: store, agentsStore: agentsStore, backoff: { _ in .milliseconds(1) },
                                minimumHealthyLife: .zero, isApplicationInBackground: { false })
        sync.handle(.ready(position: "p0", fresh: false))
        await agentsStore.settle()
        #expect(platform.fetchNotificationsActivityCursorLimitCallsCount == 2)

        platform.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                   lastSeenAt: nil, unseenCount: 0))
        sync.appDidBecomeActive()
        await agentsStore.settle()
        #expect(platform.fetchNotificationsActivityCursorLimitCallsCount == 3)
        #expect(agentsStore.needsAction?.isEmpty == true)

        // Read: nothing is stale, so neither re-reads again.
        sync.handle(.ready(position: "p1", fresh: false))
        sync.appDidBecomeActive()
        await agentsStore.settle()
        #expect(platform.fetchNotificationsActivityCursorLimitCallsCount == 3)
        sync.stop()
    }

    // MARK: - Helpers

    /// Each open yields the next stream's events and ends (the server's end), or first breaks off `brokenStreams` times;
    /// then `failures`, then a stream that never ends.
    private func makeSync(streams: [[PlatformSyncEvent]],
                          backoff: @escaping (Int) -> Duration = { _ in .milliseconds(1) },
                          failures: [PlatformSyncError] = [],
                          brokenStreams: Int = 0,
                          hangsAfterStreams: Bool = false) -> PlatformSync {
        var streams = streams
        var failures = failures
        var brokenStreams = brokenStreams
        service.openSinceClosure = { [opened] since in
            opened.sinces.append(since)
            if brokenStreams > 0 {
                brokenStreams -= 1
                return .success(PlatformSyncEventStream { $0.finish(throwing: URLError(.networkConnectionLost)) })
            }
            if !streams.isEmpty {
                let events = streams.removeFirst()
                return .success(PlatformSyncEventStream { continuation in
                    for event in events {
                        continuation.yield(event)
                    }
                    if !(hangsAfterStreams && streams.isEmpty) {
                        continuation.finish()
                    }
                })
            }
            if !failures.isEmpty {
                return .failure(failures.removeFirst())
            }
            return .success(PlatformSyncEventStream { _ in })
        }
        return PlatformSync(service: service, feedStore: store, backoff: backoff, minimumHealthyLife: .zero, isApplicationInBackground: { false })
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private final class Opened {
        var sinces: [String?] = []
    }

    private final class Counter {
        var count = 0
    }
}
