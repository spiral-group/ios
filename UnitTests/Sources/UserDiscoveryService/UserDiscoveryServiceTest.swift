//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

@MainActor
struct UserDiscoveryServiceTest {
    private var service: UserDiscoveryService
    private var clientProxy: ClientProxyMock
    
    private var searchResults: [UserProfile] {
        [.mockAlice, .mockBob, .mockCharlie]
    }
    
    init() {
        clientProxy = .init(.init(userID: "@foo:matrix.org"))
        service = UserDiscoveryService(clientProxy: clientProxy)
    }
    
    @Test
    func queryShowingResults() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [UserProfile.mockAlice], limited: true))
        
        let results = await (try? search(query: "AAA").get()) ?? []
        assertSearchResults(results, toBe: 1)
    }
    
    @Test
    func ownerIsFiltered() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [UserProfile(userID: "@foo:matrix.org")], limited: true))
        
        let results = await (try? search(query: "AAA").get()) ?? []
        assertSearchResults(results, toBe: 0)
    }
    
    @Test
    func getProfileIsNotCalled() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@alice:matrix.org"))
        
        let results = await (try? search(query: "AAA").get()) ?? []
        assertSearchResults(results, toBe: 3)
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func getProfileIsNotCalledForAccountOwnerID() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@alice:matrix.org"))
        
        let results = await (try? search(query: "foo:matrix.org").get()) ?? []
        assertSearchResults(results, toBe: 3)
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func localResultShows() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@some:matrix.org"))
        
        let results = await (try? search(query: "@a:b.com").get()) ?? []
        
        assertSearchResults(results, toBe: 4)
        #expect(clientProxy.profileForCalled)
    }
    
    @Test
    func localResultShowsOnSearchError() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        clientProxy.profileForReturnValue = .success(.init(userID: "@some:matrix.org"))
        
        let results = await (try? search(query: "@a:b.com").get()) ?? []
        
        assertSearchResults(results, toBe: 1)
        #expect(clientProxy.profileForCalled)
    }
    
    @Test
    func searchErrorTriggers() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        clientProxy.profileForReturnValue = .success(.init(userID: "@some:matrix.org"))
        
        switch await search(query: "some query") {
        case .success:
            Issue.record("Search users must fail")
        case .failure(let error):
            #expect(error == UserDiscoveryErrorType.failedSearchingUsers)
        }
        
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func localResultWithDuplicates() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@bob:matrix.org"))
        
        let results = await (try? search(query: "@a:b.com").get()) ?? []
        
        assertSearchResults(results, toBe: 3)
        let firstUserID = results.first?.id
        #expect(firstUserID == "@bob:matrix.org")
        #expect(clientProxy.profileForCalled)
    }
    
    @Test
    func searchResultsShowWhenGetProfileFails() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        let results = await (try? search(query: "@a:b.com").get()) ?? []
        
        let firstUserID = results.first?.id
        #expect(firstUserID == "@a:b.com")
        #expect(clientProxy.profileForCalled)
    }
    
    // MARK: - Bare handle (AGENT-PLATFORM, 1.0.3)
    
    @Test
    func bareHandleFindsProfileOnOwnServer() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@dan:matrix.org", displayName: "Dan"))
        
        let results = await (try? search(query: "@dan").get()) ?? []
        
        #expect(clientProxy.profileForReceivedUserID == "@dan:matrix.org")
        assertSearchResults(results, toBe: 4)
        #expect(results.first?.id == "@dan:matrix.org")
        #expect(clientProxy.searchUsersSearchTermLimitReceivedArguments?.searchTerm == "@dan")
    }
    
    @Test
    func bareHandleUsesTheServerNameAndNormalisesTheQuery() async {
        let clientProxy = ClientProxyMock(.init(userIDServerName: "spiral.test", userID: "@foo:spiral.test"))
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [], limited: false))
        clientProxy.profileForReturnValue = .success(.init(userID: "@dan.k:spiral.test"))
        let service = UserDiscoveryService(clientProxy: clientProxy)
        
        let results = await (try? service.searchProfiles(with: "  @Dan.K ").get()) ?? []
        
        #expect(clientProxy.profileForReceivedUserID == "@dan.k:spiral.test")
        #expect(results.map(\.id) == ["@dan.k:spiral.test"])
    }
    
    @Test
    func bareHandleNotFoundShowsNoPlaceholder() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [], limited: false))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        let results = await (try? search(query: "@nobody").get()) ?? []
        
        #expect(clientProxy.profileForCalled)
        assertSearchResults(results, toBe: 0)
    }
    
    @Test
    func bareHandleNotFoundAndSearchFailingIsAFailure() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        switch await search(query: "@nobody") {
        case .success:
            Issue.record("A failed search with no profile must stay a failure")
        case .failure(let error):
            #expect(error == UserDiscoveryErrorType.failedSearchingUsers)
        }
    }
    
    @Test
    func ownBareHandleIsNotLookedUp() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [UserProfile(userID: "@foo:matrix.org")], limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@foo:matrix.org"))
        
        let results = await (try? search(query: "@foo").get()) ?? []
        
        #expect(!clientProxy.profileForCalled)
        assertSearchResults(results, toBe: 0)
    }
    
    @Test
    func invalidBareHandleIsNotLookedUp() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@some:matrix.org"))
        
        for query in ["@da n", "@dan!", "@", "@ "] {
            let results = await (try? search(query: query).get()) ?? []
            assertSearchResults(results, toBe: 3)
        }
        
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func plainWordIsNotLookedUp() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: searchResults, limited: true))
        clientProxy.profileForReturnValue = .success(.init(userID: "@dan:matrix.org"))
        
        let results = await (try? search(query: "dan").get()) ?? []
        
        #expect(!clientProxy.profileForCalled)
        assertSearchResults(results, toBe: 3)
        #expect(clientProxy.searchUsersSearchTermLimitReceivedArguments?.searchTerm == "dan")
    }
    
    @Test
    func fullUserIDKeepsItsPlaceholder() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [], limited: false))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        let results = await (try? search(query: "@dan:other.org").get()) ?? []
        
        #expect(clientProxy.profileForReceivedUserID == "@dan:other.org")
        #expect(results.map(\.id) == ["@dan:other.org"])
    }
    
    // MARK: - People only (AGENT-PLATFORM, 1.0.3)
    
    @Test
    func serviceAccountsInDirectoryResultsAreRemoved() async {
        let services = ["@assistant-alice:matrix.org", "@agent-shop-1:matrix.org", "@agent-platform-bot:matrix.org",
                        "@telegrambot:matrix.org", "@whatsapp_380501234567:matrix.org", "@_lk_jwt_service:matrix.org",
                        "@spiral:matrix.org"]
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: services.map { UserProfile(userID: $0) } + searchResults,
                                                                           limited: true))
        
        let results = await (try? search(query: "a").get()) ?? []
        
        #expect(results.map(\.id) == searchResults.map(\.id))
    }
    
    @Test
    func serviceAccountHandlesAreNotLookedUp() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [], limited: false))
        clientProxy.profileForReturnValue = .success(.init(userID: "@assistant-x:matrix.org"))
        
        for query in ["@assistant-x", "@agent-x:matrix.org", "@telegrambot", "@spiral:matrix.org", "@_lk_jwt_service"] {
            let results = await (try? search(query: query).get()) ?? []
            assertSearchResults(results, toBe: 0)
        }
        
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func mixedCaseServiceAccountIDsAreNotLookedUp() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [UserProfile(userID: "@Agent-Y:matrix.org"), .mockAlice],
                                                                           limited: false))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        for query in ["@Agent-X:matrix.org", "@agent-x:MATRIX.ORG", "@Assistant-X"] {
            let results = await (try? search(query: query).get()) ?? []
            #expect(results.map(\.id) == [UserProfile.mockAlice.id])
        }
        
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func serviceAccountHandleWithFailingSearchIsAFailure() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        switch await search(query: "@agent-x:matrix.org") {
        case .success:
            Issue.record("A service account's MXID must not produce a placeholder")
        case .failure(let error):
            #expect(error == UserDiscoveryErrorType.failedSearchingUsers)
        }
        
        #expect(!clientProxy.profileForCalled)
    }
    
    @Test
    func personNamedLikeAServiceIsKept() async {
        let people = [UserProfile(userID: "@dan:matrix.org", displayName: "Dan's assistant"),
                      UserProfile(userID: "@telegramfan:matrix.org", displayName: "Telegram Agent")]
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: people, limited: false))
        clientProxy.profileForReturnValue = .success(.init(userID: "@spiralfan:matrix.org"))
        
        let results = await (try? search(query: "@spiralfan").get()) ?? []
        
        #expect(clientProxy.profileForReceivedUserID == "@spiralfan:matrix.org")
        #expect(results.map(\.id) == ["@spiralfan:matrix.org", "@dan:matrix.org", "@telegramfan:matrix.org"])
    }
    
    @Test
    func anotherServersServiceLookalikeIsKept() async {
        clientProxy.searchUsersSearchTermLimitReturnValue = .success(.init(results: [], limited: false))
        clientProxy.profileForReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        
        let results = await (try? search(query: "@telegrambot:other.org").get()) ?? []
        
        #expect(clientProxy.profileForReceivedUserID == "@telegrambot:other.org")
        #expect(results.map(\.id) == ["@telegrambot:other.org"])
    }
    
    // MARK: - Private
    
    private func assertSearchResults(_ results: [UserProfile], toBe count: Int) {
        #expect(count >= 0)
        #expect(results.count == count)
        #expect(results.isEmpty == (count == 0))
    }
    
    private func search(query: String) async -> Result<[UserProfile], UserDiscoveryErrorType> {
        await service.searchProfiles(with: query)
    }
}
