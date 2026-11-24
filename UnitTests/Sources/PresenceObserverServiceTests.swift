//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0072, ADR-0083, ADR-0084): whom the presence poll asks,
// when, and what it publishes.
//

import Combine
import Foundation
@testable import Spiral
import Testing
import UIKit

/// The mock's closure runs off the main actor; this keeps the answers and the
/// record of requests consistent across that boundary.
private final class PresenceAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: () -> Result<UserPresence, ClientProxyError>] = [:]
    private var requests: [String] = []
    
    func set(_ userID: String, _ result: Result<UserPresence, ClientProxyError>) {
        lock.withLock { answers[userID] = { result } }
    }
    
    /// A fresh answer per request, as the server gives: `receivedAt` moves.
    func set(_ userID: String, _ result: @escaping () -> Result<UserPresence, ClientProxyError>) {
        lock.withLock { answers[userID] = result }
    }
    
    func answer(_ userID: String) -> Result<UserPresence, ClientProxyError> {
        lock.withLock {
            requests.append(userID)
            return answers[userID]?() ?? .failure(.forbiddenAccess)
        }
    }
    
    var requested: [String] {
        lock.withLock { requests }
    }

    func requestCount(_ userID: String) -> Int {
        lock.withLock { requests.filter { $0 == userID }.count }
    }
}

@MainActor
struct PresenceObserverServiceTests {
    static let me = "@me:spiral.md"
    static let alice = "@alice:spiral.md"
    static let bob = "@bob:spiral.md"
    
    let clientProxy: ClientProxyMock
    let notificationCenter = NotificationCenter()
    fileprivate let answers = PresenceAnswers()
    let requestsSubject = PassthroughSubject<String, Never>()
    
    init() {
        clientProxy = ClientProxyMock(.init(userID: Self.me))
        clientProxy.userPresenceForClosure = { [answers, requestsSubject] userID in
            let result = answers.answer(userID)
            requestsSubject.send(userID)
            return result
        }
    }
    
    static func online(_ userID: String, active: Bool = true) -> UserPresence {
        UserPresence(userID: userID, state: .online, lastActiveAgo: 5, currentlyActive: active, receivedAt: Date())
    }
    
    static func offline(_ userID: String, ago: TimeInterval) -> UserPresence {
        UserPresence(userID: userID, state: .offline, lastActiveAgo: ago, currentlyActive: false, receivedAt: Date())
    }
    
    private func makeService(initialApplicationState: UIApplication.State = .active,
                             tickInterval: TimeInterval = 0.05,
                             focusedInterval: TimeInterval = 0.1,
                             listInterval: TimeInterval = 0.1) -> PresenceObserverService {
        PresenceObserverService(clientProxy: clientProxy,
                                notificationCenter: notificationCenter,
                                initialApplicationState: initialApplicationState,
                                tickInterval: tickInterval,
                                focusedInterval: focusedInterval,
                                listInterval: listInterval,
                                maxConcurrentRequests: 2,
                                forbiddenCooldown: 60)
    }
    
    private func nextRequest(_ userID: String? = nil) async throws -> String {
        try await deferFulfillment(requestsSubject) { userID == nil || $0 == userID }.fulfill()
    }
    
    // MARK: - Tests
    
    @Test
    func anObservedUserIsPolledAndPublished() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        let service = makeService()
        
        let deferred = deferFulfillment(service.presencePublisher) { $0[Self.alice]?.isOnline == true }
        service.observe(Self.alice)
        let presences = try await deferred.fulfill()
        
        #expect(presences[Self.alice]?.state == .online)
        #expect(answers.requested.first == Self.alice)
        _ = service
    }
    
    @Test
    func pollingRepeatsAndStopsWhenNobodyObserves() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        let service = makeService()
        
        service.observe(Self.alice)
        _ = try await nextRequest(Self.alice)
        _ = try await nextRequest(Self.alice)
        #expect(answers.requestCount(Self.alice) >= 2, "polls repeat while observed")
        
        service.stopObserving(Self.alice)
        let before = answers.requestCount(Self.alice)
        try await Task.sleep(for: .milliseconds(400))
        #expect(answers.requestCount(Self.alice) == before, "no poll after the last observer left")
        _ = service
    }
    
    @Test
    func aForbiddenUserIsDroppedAndNotAskedAgainWithinTheCooldown() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        answers.set(Self.bob, .failure(.forbiddenAccess))
        let service = makeService()
        
        service.observe(Self.alice)
        service.observe(Self.bob)
        _ = try await nextRequest(Self.bob)
        _ = try await nextRequest(Self.alice)
        _ = try await nextRequest(Self.alice)
        _ = try await nextRequest(Self.alice)
        
        #expect(answers.requestCount(Self.bob) == 1, "a 403 keeps the user out of the poll")
        #expect(answers.requestCount(Self.alice) >= 3, "the others keep being polled")
        #expect(service.presencePublisher.value[Self.bob] == nil)
        _ = service
    }
    
    @Test
    func neitherTheUserNorAgentsNorBridgeContactsArePolled() async throws {
        let nobodies = [Self.me,
                        "@telegram_123456:spiral.md", "@whatsapp_380501234567:spiral.md", "@instagram_17841400:spiral.md",
                        "@telegrambot:spiral.md", "@whatsappbot:spiral.md", "@instagrambot:spiral.md", "@instagram-login-bot:spiral.md"]
        for userID in nobodies + [Self.alice] {
            answers.set(userID, .success(Self.online(userID)))
        }
        let service = makeService()
        
        for userID in nobodies {
            service.observe(userID)
        }
        service.setObserved(Set(nobodies), scope: "list")
        service.observe(Self.alice)
        _ = try await nextRequest(Self.alice)
        try await Task.sleep(for: .milliseconds(150))
        
        #expect(Set(answers.requested) == [Self.alice])
        _ = service
    }
    
    @Test
    func nothingIsPolledInTheBackgroundAndPollingResumesInTheForeground() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        let service = makeService(initialApplicationState: .background)
        
        service.observe(Self.alice)
        try await Task.sleep(for: .milliseconds(300))
        #expect(answers.requested.isEmpty, "the background does not poll")
        
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        _ = try await nextRequest(Self.alice)
        
        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        let before = answers.requestCount(Self.alice)
        try await Task.sleep(for: .milliseconds(400))
        #expect(answers.requestCount(Self.alice) == before, "resigning active stops the poll")
        _ = service
    }
    
    @Test
    func aScopeReplacesItsPreviousSet() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        answers.set(Self.bob, .success(Self.online(Self.bob)))
        let service = makeService()
        
        service.setObserved([Self.alice], scope: "list")
        _ = try await nextRequest(Self.alice)
        
        service.setObserved([Self.bob], scope: "list")
        _ = try await nextRequest(Self.bob)
        let aliceBefore = answers.requestCount(Self.alice)
        _ = try await nextRequest(Self.bob)
        _ = try await nextRequest(Self.bob)
        #expect(answers.requestCount(Self.alice) == aliceBefore, "alice left the scope")
        
        service.setObserved([], scope: "list")
        let bobBefore = answers.requestCount(Self.bob)
        try await Task.sleep(for: .milliseconds(400))
        #expect(answers.requestCount(Self.bob) == bobBefore, "an empty scope polls nobody")
        _ = service
    }
    
    @Test
    func theFocusedUserIsAskedMoreOftenThanAListRow() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        answers.set(Self.bob, .success(Self.online(Self.bob)))
        let service = makeService(focusedInterval: 0.1, listInterval: 60)
        
        service.setObserved([Self.bob], scope: "list")
        service.observe(Self.alice)
        for _ in 0..<4 {
            _ = try await nextRequest(Self.alice)
        }
        
        #expect(answers.requestCount(Self.bob) == 1, "a list row waits for its own interval")
        _ = service
    }
    
    @Test
    func aNewlyShownUserIsAskedWithoutWaitingForTheNextTick() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        answers.set(Self.bob, .success(Self.online(Self.bob)))
        let service = makeService(tickInterval: 60, focusedInterval: 60, listInterval: 60)
        
        service.observe(Self.alice)
        _ = try await nextRequest(Self.alice)
        
        let clock = ContinuousClock()
        let start = clock.now
        service.setObserved([Self.bob], scope: "list")
        _ = try await nextRequest(Self.bob)
        #expect(clock.now - start < .seconds(5), "asked at once, not a tick (60 s) later")
        _ = service
    }
    
    @Test
    func anAnswerThatShowsTheSameIsNotPublishedAgain() async throws {
        answers.set(Self.alice) { .success(Self.offline(Self.alice, ago: 120)) }
        let service = makeService()
        var publications = 0
        let cancellable = service.presencePublisher
            .dropFirst()
            .sink { _ in publications += 1 }
        
        service.observe(Self.alice)
        for _ in 0..<4 {
            _ = try await nextRequest(Self.alice)
        }
        #expect(publications == 1, "the same last seen, re-anchored by every answer, is not news")
        
        let deferred = deferFulfillment(service.presencePublisher) { $0[Self.alice]?.isOnline == true }
        answers.set(Self.alice) { .success(Self.online(Self.alice)) }
        _ = try await deferred.fulfill()
        #expect(publications == 2, "a change is")
        
        _ = cancellable
        _ = service
    }
    
    /// AGENT-PLATFORM (1.0.3): a deleted or signed out account's service kept
    /// polling the chat list's DMs on every foreground with the dead token,
    /// because screens of the ended session outlived it. A stopped service
    /// never asks again: not on the next foreground, not for a screen that
    /// still calls in.
    @Test
    func aStoppedServiceNeverPollsAgain() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        answers.set(Self.bob, .success(Self.online(Self.bob)))
        let service = makeService(initialApplicationState: .background)
        service.setObserved([Self.alice], scope: "homeScreen")
        
        service.stop()
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        service.observe(Self.bob)
        service.setObserved([Self.alice, Self.bob], scope: "homeScreen")
        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(400))
        
        #expect(answers.requested.isEmpty, "a stopped service polled")
        _ = service
    }
    
    @Test
    func stoppingAPollingServiceEndsThePoll() async throws {
        answers.set(Self.alice, .success(Self.online(Self.alice)))
        let service = makeService()
        service.setObserved([Self.alice], scope: "homeScreen")
        _ = try await nextRequest(Self.alice)
        
        service.stop()
        try await Task.sleep(for: .milliseconds(100))
        let before = answers.requestCount(Self.alice)
        try await Task.sleep(for: .milliseconds(400))
        
        #expect(answers.requestCount(Self.alice) == before, "the poll outlived the stop")
        _ = service
    }
}
