//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083): a screen's interest in presence lasts
// exactly as long as the screen holds it.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct PresenceObservationTests {
    static let me = "@me:spiral.md"
    static let alice = "@alice:spiral.md"
    static let bob = "@bob:spiral.md"
    static let agent = "@assistant-me:spiral.md"
    
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
        let nobodies: [String?] = [nil, Self.me, "@telegram_123:spiral.md", "@whatsappbot:spiral.md"]
        for userID in nobodies {
            #expect(PresenceObservation(userID: userID, ownUserID: Self.me, service: service) { _ in } == nil, "\(userID ?? "nil")")
        }
        #expect(PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: nil) { _ in } == nil, "no service")
        #expect(service.observeCallsCount == 0)
    }
    
    // MARK: - An agent's pause
    
    @Test
    func aPausedAgentIsMarkedAndFollowsTheStore() async throws {
        let platform = agentPlatform(cards: [card(isPaused: true)])
        let store = AgentsStore(service: platform)
        let changes = PassthroughSubject<UserPresence?, Never>()
        let observation = PresenceObservation(userID: Self.agent, ownUserID: Self.me, service: service, agentsStore: store) { changes.send($0) }
        presences.send([Self.agent: offlineAgent])
        
        let paused = deferFulfillment(changes) { $0?.isAgentPaused == true }
        try await paused.fulfill()
        
        platform.fetchAgentSpaceOrgIDReturnValue = .success(space(cards: [card(isPaused: false)]))
        let resumed = deferFulfillment(changes) { $0?.isAgentPaused == false }
        await store.reread(.spaces)
        try await resumed.fulfill()
        _ = observation
    }
    
    /// Someone else's agent has no card, and a failed read says nothing: neither reads as paused.
    @Test(arguments: [false, true])
    func anAgentWithoutACardIsNotPaused(readFails: Bool) async {
        let platform = agentPlatform(cards: [])
        if readFails {
            platform.listMyAgentSpacesReturnValue = .failure(.serverError(status: 500))
        }
        let store = AgentsStore(service: platform)
        var delivered: [UserPresence?] = []
        let observation = PresenceObservation(userID: Self.agent, ownUserID: Self.me, service: service, agentsStore: store) { delivered.append($0) }
        presences.send([Self.agent: offlineAgent])
        await store.reread(.spaces)
        await settle { delivered.contains { $0 != nil } }
        
        #expect(delivered.contains { $0 != nil })
        #expect(delivered.allSatisfy { $0?.isAgentPaused != true })
        _ = observation
    }
    
    @Test
    func aPersonReadsNoSpacesAndAnAgentStopsShowingThem() {
        let platform = agentPlatform(cards: [])
        let store = AgentsStore(service: platform)
        
        let person = PresenceObservation(userID: Self.alice, ownUserID: Self.me, service: service, agentsStore: store) { _ in }
        #expect(!store.isShown(.spaces))
        person?.cancel()
        
        let agent = PresenceObservation(userID: Self.agent, ownUserID: Self.me, service: service, agentsStore: store) { _ in }
        #expect(store.isShown(.spaces))
        agent?.cancel()
        #expect(!store.isShown(.spaces))
    }
    
    private var offlineAgent: UserPresence {
        UserPresence(userID: Self.agent, state: .offline, lastActiveAgo: 780, currentlyActive: false, receivedAt: .now)
    }
    
    private func agentPlatform(cards: [AgentSpaceAgentCard]) -> AgentPlatformServiceMock {
        let platform = AgentPlatformServiceMock()
        platform.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "org", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: cards.count)],
                                                               provisioningStatus: .ready))
        platform.fetchAgentSpaceOrgIDReturnValue = .success(space(cards: cards))
        return platform
    }
    
    private func space(cards: [AgentSpaceAgentCard]) -> AgentSpaceDetail {
        .init(orgID: "org", name: "Personal", kind: .solo, avatarMXC: nil, industry: nil, website: nil, agents: cards)
    }
    
    private func card(isPaused: Bool) -> AgentSpaceAgentCard {
        .init(agentID: "agent-1", matrixUserID: Self.agent, displayName: "Assistant", avatarMXC: nil, kind: "personal_assistant",
              visibility: "private", lifecycleState: "active", roomCount: 1, activeToolCount: 0, isPaused: isPaused)
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
