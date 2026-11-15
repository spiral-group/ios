//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: after a relaunch the SDK's ignored-users subscription starts
// with an unrestored `[]`; the app's list must not take it for the account's.
//

import Foundation
@testable import Spiral
import Testing

struct IgnoredUsersListTests {
    let list = IgnoredUsersList()
    
    @Test
    func theSubscriptionsFirstValueIsNotTheList() {
        list.subscriptionDelivered([])
        
        #expect(list.publisher.value == nil)
        #expect(!list.isKnown)
    }
    
    @Test
    func aRelaunchShowsTheListItRead() async throws {
        list.subscriptionDelivered([])
        
        try await list.refresh { ["@peer:spiral.md"] }
        
        #expect(list.publisher.value == ["@peer:spiral.md"])
        #expect(list.isKnown)
    }
    
    @Test
    func aSyncsChangeIsTaken() {
        list.subscriptionDelivered([])
        list.subscriptionDelivered(["@peer:spiral.md"])
        
        #expect(list.publisher.value == ["@peer:spiral.md"])
        
        list.subscriptionDelivered([])
        
        #expect(list.publisher.value == [])
    }
    
    @Test
    func aSyncsChangeDuringARefreshWins() async throws {
        list.subscriptionDelivered([])
        
        try await list.refresh {
            list.subscriptionDelivered(["@new:spiral.md"])
            return ["@old:spiral.md"]
        }
        
        #expect(list.publisher.value == ["@new:spiral.md"])
    }
    
    @Test
    func aFailedRefreshLeavesTheListUnknown() async {
        list.subscriptionDelivered([])
        
        await #expect(throws: RefreshError.self) {
            try await list.refresh { throw RefreshError() }
        }
        
        #expect(list.publisher.value == nil)
    }
    
    @Test
    func aRefreshInFlightIsNotRepeated() async throws {
        var reads = 0
        try await list.refresh {
            reads += 1
            try await list.refresh {
                reads += 1
                return ["@inner:spiral.md"]
            }
            return ["@outer:spiral.md"]
        }
        
        #expect(reads == 1)
        #expect(list.publisher.value == ["@outer:spiral.md"])
    }
    
    @Test
    func aFailedLoadIsTriedAgain() async {
        list.subscriptionDelivered([])
        var reads = 0
        
        await list.load(retryDelays: [.zero, .zero]) {
            reads += 1
            if reads == 1 { throw RefreshError() }
            return ["@peer:spiral.md"]
        }
        
        #expect(reads == 2)
        #expect(list.publisher.value == ["@peer:spiral.md"])
    }
    
    @Test
    func aLoadStopsAfterItsTries() async {
        list.subscriptionDelivered([])
        var reads = 0
        
        await list.load(retryDelays: [.zero, .zero]) {
            reads += 1
            throw RefreshError()
        }
        
        #expect(reads == 3)
        #expect(list.publisher.value == nil)
    }
    
    @Test
    func aSyncsChangeEndsTheTries() async {
        list.subscriptionDelivered([])
        var reads = 0
        
        await list.load(retryDelays: [.zero, .zero]) {
            reads += 1
            list.subscriptionDelivered(["@new:spiral.md"])
            throw RefreshError()
        }
        
        #expect(reads == 1)
        #expect(list.publisher.value == ["@new:spiral.md"])
    }
    
    private struct RefreshError: Error { }
}
