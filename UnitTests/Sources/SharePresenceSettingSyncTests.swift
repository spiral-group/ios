//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0084): «Share presence» and the account data
// the server's privacy rule reads stay in step.
//

import Combine
import Foundation
@testable import Spiral
import Testing

/// The account data as this device sees it: the synced copy, and the writes
/// it made. The mock's closures run off the main actor.
private final class AccountDataServer: @unchecked Sendable {
    private let lock = NSLock()
    private var synced: String?
    private var writes: [String] = []
    private var inFlight = 0
    private var maxInFlight = 0
    private var failWrites = false
    private var writeDelay: Duration = .zero
    let writesSubject = PassthroughSubject<String, Never>()
    let writeStartedSubject = PassthroughSubject<String, Never>()
    
    /// What the next sync delivers, as the SDK stores it: the whole event.
    func sync(share: Bool?) {
        lock.withLock {
            synced = share.map { #"{"type":"com.spiral.presence","content":{"share":\#($0)}}"# }
        }
    }
    
    func setFailWrites(_ fail: Bool) {
        lock.withLock { failWrites = fail }
    }

    func setWriteDelay(_ delay: Duration) {
        lock.withLock { writeDelay = delay }
    }
    
    var syncedValue: String? {
        lock.withLock { synced }
    }

    var recordedWrites: [String] {
        lock.withLock { writes }
    }

    var largestConcurrency: Int {
        lock.withLock { maxInFlight }
    }
    
    func read() -> String? {
        lock.withLock { synced }
    }
    
    func write(_ content: String) async -> Result<Void, ClientProxyError> {
        let delay = lock.withLock {
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            return writeDelay
        }
        writeStartedSubject.send(content)
        try? await Task.sleep(for: delay)
        let failed = lock.withLock {
            inFlight -= 1
            if !failWrites {
                writes.append(content)
            }
            return failWrites
        }
        writesSubject.send(content)
        return failed ? .failure(.sdkError(ClientProxyMockError.generic)) : .success(())
    }
}

@MainActor
struct SharePresenceSettingSyncTests {
    let clientProxy: ClientProxyMock
    let accountSettings = AppSettings.volatile().userSettings(for: "@alice:example.com").account
    let syncActions = PassthroughSubject<ClientProxyAction, Never>()
    private let server = AccountDataServer()
    
    static let hide = #"{"share":false}"#
    static let share = #"{"share":true}"#
    
    init() {
        clientProxy = ClientProxyMock(.init(userID: "@me:spiral.md"))
        clientProxy.actionsPublisher = syncActions.eraseToAnyPublisher()
        clientProxy.accountDataEventTypeClosure = { [server] _ in
            .success(server.read())
        }
        clientProxy.setAccountDataEventTypeContentClosure = { [server] _, content in
            await server.write(content)
        }
    }
    
    private func makeSync(echoSyncs: Int = 3) -> SharePresenceSettingSync {
        SharePresenceSettingSync(clientProxy: clientProxy, accountSettings: accountSettings, syncThrottle: .milliseconds(10), echoSyncs: echoSyncs)
    }
    
    /// The next write's content, once the writer has also recorded how it went.
    private func nextWrite() async throws -> String {
        let content = try await deferFulfillment(server.writesSubject) { _ in true }.fulfill()
        try await Task.sleep(for: .milliseconds(50))
        return content
    }
    
    // MARK: - Tests
    
    @Test
    func aToggleHereIsWrittenToTheAccount() async throws {
        accountSettings.sharePresence = true
        let sync = makeSync()
        
        accountSettings.sharePresence = false
        #expect(try await nextWrite() == Self.hide)
        #expect(clientProxy.setAccountDataEventTypeContentReceivedArguments?.eventType == "com.spiral.presence")
        
        accountSettings.sharePresence = true
        #expect(try await nextWrite() == Self.share)
        #expect(server.recordedWrites == [Self.hide, Self.share])
        _ = sync
    }
    
    @Test
    func aValueSetOnAnotherDeviceWinsAndIsNotWrittenBack() async throws {
        accountSettings.sharePresence = true
        server.sync(share: false)
        let sync = makeSync()
        
        await sync.reconcile()
        
        #expect(accountSettings.sharePresence == false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.recordedWrites.isEmpty, "applying the server's value is not a toggle")
        _ = sync
    }
    
    @Test
    func aSyncTriggersTheReconcile() async throws {
        accountSettings.sharePresence = true
        server.sync(share: false)
        let sync = makeSync()
        
        let deferred = deferFulfillment(accountSettings.sharePresencePublisher) { $0 == false }
        syncActions.send(.receivedSyncUpdate)
        try await deferred.fulfill()
        _ = sync
    }
    
    @Test
    func aFreshInstallNeverOverwritesTheAccount() async throws {
        accountSettings.sharePresence = true
        server.sync(share: nil)
        let sync = makeSync()
        
        await sync.reconcile()
        try await Task.sleep(for: .milliseconds(100))
        
        #expect(accountSettings.sharePresence == true)
        #expect(server.recordedWrites.isEmpty)
        _ = sync
    }
    
    @Test
    func neverWrittenAndNotSharingIsWrittenAsHidden() async {
        accountSettings.sharePresence = false
        server.sync(share: nil)
        let sync = makeSync()
        
        await sync.reconcile()
        
        #expect(server.recordedWrites == [Self.hide])
        #expect(accountSettings.sharePresence == false)
        _ = sync
    }
    
    @Test
    func theStaleSyncedValueIsNotTakenWhileTheWriteComesBack() async throws {
        accountSettings.sharePresence = true
        server.sync(share: true)
        let sync = makeSync()
        
        accountSettings.sharePresence = false
        _ = try await nextWrite()
        
        await sync.reconcile()
        await sync.reconcile()
        #expect(accountSettings.sharePresence == false, "the sync has not brought our write back yet")
        
        server.sync(share: false)
        await sync.reconcile()
        #expect(accountSettings.sharePresence == false)
        
        server.sync(share: true)
        await sync.reconcile()
        #expect(accountSettings.sharePresence == true, "once our write came back, a later change elsewhere wins again")
        #expect(server.recordedWrites == [Self.hide])
        _ = sync
    }
    
    @Test
    func withoutTheEchoTheServerWinsAfterAFewSyncs() async throws {
        accountSettings.sharePresence = true
        server.sync(share: true)
        let sync = makeSync(echoSyncs: 3)
        
        accountSettings.sharePresence = false
        _ = try await nextWrite()
        
        // Another device turned it back on before our write reached this one.
        await sync.reconcile()
        await sync.reconcile()
        #expect(accountSettings.sharePresence == false)
        await sync.reconcile()
        #expect(accountSettings.sharePresence == true)
        _ = sync
    }
    
    @Test
    func aFailedWriteIsRetriedOnTheNextSync() async throws {
        accountSettings.sharePresence = true
        server.sync(share: true)
        server.setFailWrites(true)
        let sync = makeSync()
        
        accountSettings.sharePresence = false
        _ = try await nextWrite()
        #expect(server.recordedWrites.isEmpty)
        
        await sync.reconcile()
        #expect(accountSettings.sharePresence == false, "a pending toggle is not undone by the stale synced value")
        #expect(server.recordedWrites.isEmpty)
        
        server.setFailWrites(false)
        await sync.reconcile()
        #expect(server.recordedWrites == [Self.hide])
        _ = sync
    }
    
    @Test
    func writesNeverOverlapAndTheLatestLandsLast() async throws {
        accountSettings.sharePresence = true
        server.sync(share: true)
        server.setWriteDelay(.milliseconds(300))
        let sync = makeSync()
        
        let started = deferFulfillment(server.writeStartedSubject) { _ in true }
        accountSettings.sharePresence = false
        _ = try await started.fulfill()
        accountSettings.sharePresence = true
        
        let deferred = deferFulfillment(server.writesSubject.collect(2).first()) { _ in true }
        #expect(try await deferred.fulfill() == [Self.hide, Self.share])
        #expect(server.largestConcurrency == 1)
        _ = sync
    }
    
    // MARK: - Parsing
    
    @Test
    func onlyTheJSONLiteralCounts() {
        #expect(SharePresenceSettingSync.share(fromJSON: #"{"type":"com.spiral.presence","content":{"share":false}}"#) == false)
        #expect(SharePresenceSettingSync.share(fromJSON: #"{"share":true}"#) == true)
        #expect(SharePresenceSettingSync.share(fromJSON: #"{"share":0}"#) == nil, "the server shares unless it is the literal false")
        #expect(SharePresenceSettingSync.share(fromJSON: #"{"share":"false"}"#) == nil)
        #expect(SharePresenceSettingSync.share(fromJSON: #"{}"#) == nil)
        #expect(SharePresenceSettingSync.share(fromJSON: "not json") == nil)
    }
}
