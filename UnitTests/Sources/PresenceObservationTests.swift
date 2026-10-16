//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083): a screen's interest in presence lasts
// exactly as long as the screen holds it.
//

import Combine
@testable import ElementX
import Foundation
import Testing

@MainActor
struct PresenceObservationTests {
    static let me = "@me:spiral.md"
    static let alice = "@alice:spiral.md"
    static let bob = "@bob:spiral.md"
    
    let service = PresenceObserverServiceMock()
    let presences = CurrentValueSubject<[String: UserPresence], Never>([:])
    
    init() {
        service.presencePublisher = presences.asCurrentValuePublisher()
    }
    
    /// A release runs the isolated deinit; give it the turn it may need.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<20 where !condition() {
            await Task.yield()
        }
    }
    
    // MARK: - One person
    
    @Test
    func aPersonIsObservedAndTheirPresenceDelivered() async throws {
        let changes = PassthroughSubject<UserPresence?, Never>()
        let observation = PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: service) { changes.send($0) }
        #expect(observation != nil)
        #expect(service.observeReceivedInvocations == [Self.alice])
        
        let deferred = deferFulfillment(changes) { $0?.isOnline == true }
        presences.send([Self.alice: UserPresence(userID: Self.alice, state: .online, lastActiveAgo: 1, currentlyActive: true, receivedAt: .now)])
        try await deferred.fulfill()
        _ = observation
    }
    
    @Test
    func cancellingStopsOnceAndForAll() {
        let observation = PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: service) { _ in }
        observation?.cancel()
        observation?.cancel()
        #expect(service.stopObservingReceivedInvocations == [Self.alice])
    }
    
    @Test
    func releasingStopsObserving() async {
        var observation = PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: service) { _ in }
        #expect(observation != nil)
        observation = nil
        await settle { service.stopObservingCallsCount > 0 }
        #expect(service.stopObservingReceivedInvocations == [Self.alice])
    }
    
    @Test
    func nobodyWorthObservingIsNil() {
        let nobodies: [String?] = [nil, Self.me, "@assistant-me:spiral.md", "@telegram_123:spiral.md", "@whatsappbot:spiral.md"]
        for userID in nobodies {
            #expect(PresenceObservation(userID: userID, ownUserID: Self.me, service: service) { _ in } == nil, "\(userID ?? "nil")")
        }
        #expect(PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: nil) { _ in } == nil, "no service")
        #expect(service.observeCallsCount == 0)
    }
    
    // MARK: - A list's rows
    
    @Test
    func aScopeReplacesItsSetAndIsClearedOnCancel() {
        let scope = PresenceScope(service: service)
        scope.observe([Self.alice])
        scope.observe([Self.alice, Self.bob])
        scope.cancel()
        scope.observe([Self.bob])
        
        let calls = service.setObservedScopeReceivedInvocations
        #expect(calls.map(\.userIDs) == [[Self.alice], [Self.alice, Self.bob], []], "nothing after cancel")
        #expect(Set(calls.map(\.scope)).count == 1, "one scope name throughout")
    }
    
    @Test
    func twoListsNeverShareAScope() {
        let first = PresenceScope(service: service)
        let second = PresenceScope(service: service)
        first.observe([Self.alice])
        second.observe([Self.alice])
        
        let names = service.setObservedScopeReceivedInvocations.map(\.scope)
        #expect(names.count == 2)
        #expect(names.first != names.last)
        _ = (first, second)
    }
    
    @Test
    func releasingAScopeClearsIt() async {
        var scope: PresenceScope? = PresenceScope(service: service)
        scope?.observe([Self.alice])
        scope = nil
        await settle { service.setObservedScopeCallsCount > 1 }
        #expect(service.setObservedScopeReceivedInvocations.last?.userIDs == [])
    }
}
