//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 98): the owner's messenger ignore list is sent to
// the platform so that their agents ignore the same people.
//

import Combine
@testable import ElementX
import Foundation
import Testing

/// The platform as the sync sees it: every PUT it was sent, and the lists it
/// accepted. The mock's closure runs off the main actor.
private final class IgnoreListPlatform: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts: [[String]] = []
    private var accepted: [[String]] = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var fails = false
    private var delay: Duration = .zero
    let attemptsSubject = PassthroughSubject<[String], Never>()
    let startedSubject = PassthroughSubject<[String], Never>()
    
    var recordedAttempts: [[String]] {
        lock.withLock { attempts }
    }
    
    var acceptedLists: [[String]] {
        lock.withLock { accepted }
    }
    
    var largestConcurrency: Int {
        lock.withLock { maxInFlight }
    }
    
    func setFails(_ fails: Bool) {
        lock.withLock { self.fails = fails }
    }
    
    func setDelay(_ delay: Duration) {
        lock.withLock { self.delay = delay }
    }
    
    func put(_ list: [String]) async -> Result<Void, AgentPlatformError> {
        let delay = lock.withLock {
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return self.delay
        }
        startedSubject.send(list)
        try? await Task.sleep(for: delay)
        let failed = lock.withLock {
            inFlight -= 1
            attempts.append(list)
            if !fails {
                accepted.append(list)
            }
            return fails
        }
        attemptsSubject.send(list)
        return failed ? .failure(.serverError(status: 500)) : .success(())
    }
}

@MainActor
struct OwnerBlocksSyncTests {
    let clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
    let service = AgentPlatformServiceMock()
    let ignoredUsers = CurrentValueSubject<[String]?, Never>(nil)
    let syncActions = PassthroughSubject<ClientProxyAction, Never>()
    let resyncs = PassthroughSubject<Void, Never>()
    private let platform = IgnoreListPlatform()
    
    init() {
        clientProxy.ignoredUsersPublisher = ignoredUsers.asCurrentValuePublisher()
        clientProxy.actionsPublisher = syncActions.eraseToAnyPublisher()
        service.underlyingOwnerBlocksResyncPublisher = resyncs.eraseToAnyPublisher()
        service.syncIgnoredUsersClosure = { [platform] list in
            await platform.put(list)
        }
    }
    
    private func makeSync() -> OwnerBlocksSync {
        OwnerBlocksSync(clientProxy: clientProxy, agentPlatformService: service, debounce: .milliseconds(30), syncThrottle: .milliseconds(10))
    }
    
    /// The next PUT the platform answered.
    private func nextAttempt() async throws -> [String] {
        try await deferFulfillment(platform.attemptsSubject) { _ in true }.fulfill()
    }
    
    // MARK: - Tests
    
    /// An unknown list is never sent, and a known one waits for the first
    /// sync after launch, which may change it. Then it goes, on every launch.
    /// Each PUT records what its instance had seen when it went, so the test
    /// waits on the PUTs themselves, never on a sleep.
    @Test
    func nothingGoesWhileTheListIsUnknownOrBeforeTheFirstSync() async throws {
        let moments = Moments()
        service.syncIgnoredUsersClosure = { [platform, moments] list in
            moments.record(listKnown: moments.isListKnown)
            return await platform.put(list)
        }
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        
        // A second launch: its own session, which has not synced yet.
        let relaunchSyncs = PassthroughSubject<ClientProxyAction, Never>()
        let relaunchClient = ClientProxyMock(.init(userID: "@me:spiral.md"))
        relaunchClient.ignoredUsersPublisher = ignoredUsers.asCurrentValuePublisher()
        relaunchClient.actionsPublisher = relaunchSyncs.eraseToAnyPublisher()
        let relaunchService = AgentPlatformServiceMock()
        relaunchService.underlyingOwnerBlocksResyncPublisher = Empty().eraseToAnyPublisher()
        let relaunchPlatform = IgnoreListPlatform()
        relaunchService.syncIgnoredUsersClosure = { [relaunchPlatform, moments] list in
            moments.record(relaunchSynced: moments.isRelaunchSynced)
            return await relaunchPlatform.put(list)
        }
        let relaunch = OwnerBlocksSync(clientProxy: relaunchClient, agentPlatformService: relaunchService,
                                       debounce: .milliseconds(30), syncThrottle: .milliseconds(10))
        
        let first = deferFulfillment(platform.attemptsSubject) { _ in true }
        moments.listBecomesKnown()
        ignoredUsers.send(["@bob:remote.org"])
        #expect(try await first.fulfill() == ["@bob:remote.org"])
        #expect(moments.listKnownAtEachPut == [true], "an unknown list is never sent")
        
        let launched = deferFulfillment(relaunchPlatform.attemptsSubject) { _ in true }
        moments.relaunchSyncs()
        relaunchSyncs.send(.receivedSyncUpdate)
        #expect(try await launched.fulfill() == ["@bob:remote.org"], "the same list again, on the next launch")
        #expect(moments.relaunchSyncedAtEachPut == [true], "the relaunched session waited for its first sync")
        _ = (sync, relaunch)
    }
    
    /// A resync while a PUT of the same list is in flight goes again after
    /// it: the in-flight PUT may have been reconciled before the erase that
    /// asked for the resync, so it cannot count for it.
    @Test
    func aResyncDuringAPutOfTheSameListSendsItAgain() async throws {
        platform.setDelay(.milliseconds(150))
        ignoredUsers.send(["@bob:spiral.md"])
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        let started = deferFulfillment(platform.startedSubject) { _ in true }
        _ = try await started.fulfill()
        
        let first = deferFulfillment(platform.attemptsSubject) { _ in true }
        resyncs.send()
        _ = try await first.fulfill()
        
        #expect(try await nextAttempt() == ["@bob:spiral.md"], "one more PUT for the resync")
        #expect(platform.acceptedLists == [["@bob:spiral.md"], ["@bob:spiral.md"]])
        _ = sync
    }
    
    /// A soft logout refuses the session's token: no PUT goes until the person
    /// signs in again, which builds a new session and a new sync.
    @Test
    func nothingGoesOnceTheSessionIsSignedOut() async throws {
        ignoredUsers.send(["@bob:spiral.md"])
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        _ = try await nextAttempt()
        
        syncActions.send(.receivedAuthError(isSoftLogout: true))
        let nothing = deferFailure(platform.attemptsSubject, timeout: .seconds(1)) { _ in true }
        resyncs.send()
        ignoredUsers.send(["@bob:spiral.md", "@eve:spiral.md"])
        try await Task.sleep(for: .milliseconds(20))
        syncActions.send(.receivedSyncUpdate)
        try await nothing.fulfill()
        
        #expect(platform.recordedAttempts == [["@bob:spiral.md"]])
        _ = sync
    }
    
    /// A burst of changes is one PUT with the latest list.
    @Test
    func quickChangesCollapseIntoOnePut() async throws {
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        
        ignoredUsers.send(["@a:spiral.md"])
        ignoredUsers.send(["@a:spiral.md", "@b:spiral.md"])
        ignoredUsers.send(["@c:spiral.md", "@b:spiral.md"])
        
        #expect(try await nextAttempt() == ["@b:spiral.md", "@c:spiral.md"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(platform.recordedAttempts == [["@b:spiral.md", "@c:spiral.md"]])
        _ = sync
    }
    
    /// A change while a PUT is in flight goes after it: one at a time, the
    /// latest last.
    @Test
    func oneRequestIsInFlightAndTheLatestListGoesLast() async throws {
        platform.setDelay(.milliseconds(150))
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        
        ignoredUsers.send(["@a:spiral.md"])
        try await Task.sleep(for: .milliseconds(80))
        ignoredUsers.send(["@a:spiral.md", "@b:spiral.md"])
        
        #expect(try await nextAttempt() == ["@a:spiral.md"])
        #expect(try await nextAttempt() == ["@a:spiral.md", "@b:spiral.md"])
        #expect(platform.largestConcurrency == 1)
        _ = sync
    }
    
    @Test
    func aFailedPutIsRetriedOnTheNextSync() async throws {
        platform.setFails(true)
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        ignoredUsers.send(["@bob:spiral.md"])
        _ = try await nextAttempt()
        #expect(platform.acceptedLists.isEmpty)
        
        platform.setFails(false)
        let retried = deferFulfillment(platform.attemptsSubject) { _ in true }
        try await Task.sleep(for: .milliseconds(20))
        syncActions.send(.receivedSyncUpdate)
        _ = try await retried.fulfill()
        
        #expect(platform.acceptedLists == [["@bob:spiral.md"]])
        _ = sync
    }
    
    /// Another device changed the ignore list: the sync brings it here, and
    /// it goes.
    @Test
    func aChangeFromAnotherDeviceIsSent() async throws {
        ignoredUsers.send(["@bob:spiral.md"])
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        _ = try await nextAttempt()
        
        ignoredUsers.send(["@bob:spiral.md", "@eve:spiral.md"])
        
        #expect(try await nextAttempt() == ["@bob:spiral.md", "@eve:spiral.md"])
        _ = sync
    }
    
    /// An erase of an assistant's memory drops the rows the owner's blocks
    /// live in, and a new company agent has none: the list goes again.
    @Test
    func theServiceAsksForAResync() async throws {
        ignoredUsers.send(["@bob:spiral.md"])
        let sync = makeSync()
        syncActions.send(.receivedSyncUpdate)
        _ = try await nextAttempt()
        
        resyncs.send()
        
        #expect(try await nextAttempt() == ["@bob:spiral.md"])
        #expect(platform.acceptedLists == [["@bob:spiral.md"], ["@bob:spiral.md"]])
        _ = sync
    }
}

/// What the test had done when each PUT went. The mock's closures run off
/// the main actor.
private final class Moments: @unchecked Sendable {
    private let lock = NSLock()
    private var listKnown = false
    private var relaunchSynced = false
    private var listKnownAtPuts: [Bool] = []
    private var relaunchSyncedAtPuts: [Bool] = []

    var isListKnown: Bool {
        lock.withLock { listKnown }
    }

    var isRelaunchSynced: Bool {
        lock.withLock { relaunchSynced }
    }

    var listKnownAtEachPut: [Bool] {
        lock.withLock { listKnownAtPuts }
    }

    var relaunchSyncedAtEachPut: [Bool] {
        lock.withLock { relaunchSyncedAtPuts }
    }

    func listBecomesKnown() {
        lock.withLock { listKnown = true }
    }

    func relaunchSyncs() {
        lock.withLock { relaunchSynced = true }
    }

    func record(listKnown: Bool) {
        lock.withLock { listKnownAtPuts.append(listKnown) }
    }

    func record(relaunchSynced: Bool) {
        lock.withLock { relaunchSyncedAtPuts.append(relaunchSynced) }
    }
}
