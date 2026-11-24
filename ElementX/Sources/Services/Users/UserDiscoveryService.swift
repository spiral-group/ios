//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

final class UserDiscoveryService: UserDiscoveryServiceProtocol {
    private let clientProxy: ClientProxyProtocol
    
    init(clientProxy: ClientProxyProtocol) {
        self.clientProxy = clientProxy
    }
    
    func searchProfiles(with searchQuery: String) async -> Result<[UserProfile], UserDiscoveryErrorType> {
        async let queriedProfile = profileIfPossible(with: searchQuery)
        
        do {
            let searchedUsers = try await clientProxy.searchUsers(searchTerm: searchQuery, limit: 10).get()
            let users = await merge(queriedProfile: queriedProfile, searchResults: searchedUsers)
            return .success(filterServiceAccounts(filterAccountOwner(users)))
        } catch {
            // we want to show the profile (if any) even if the search fails
            if let queriedProfile = await queriedProfile {
                return .success([queriedProfile])
            } else {
                return .failure(.failedSearchingUsers)
            }
        }
    }
    
    private func merge(queriedProfile: UserProfile?, searchResults: SearchUsersResults) -> [UserProfile] {
        let searchResults = searchResults.results
        
        guard let queriedProfile else {
            return searchResults
        }
        
        let filteredSearchResult = searchResults.filter {
            $0.id != queriedProfile.id
        }
        
        return [queriedProfile] + filteredSearchResult
    }
    
    private func profileIfPossible(with searchQuery: String) async -> UserProfile? {
        // AGENT-PLATFORM (1.0.3): every account lives on our one server (no federation), so `@name`
        // without a server part is looked up as `@name:<own server>`. Unlike a full MXID there is no
        // placeholder row: a handle that doesn't resolve (a 404 on every keystroke) shows nobody.
        if let handleUserID = bareHandleUserID(for: searchQuery) {
            guard handleUserID != clientProxy.userID, !isServiceAccount(handleUserID) else {
                return nil
            }
            
            return try? await clientProxy.profile(for: handleUserID).get()
        }
        
        // AGENT-PLATFORM (1.0.3): a service account's full MXID is not looked up, so it gets no placeholder row either.
        guard searchQuery.isMatrixIdentifier, searchQuery != clientProxy.userID, !isServiceAccount(searchQuery) else {
            return nil
        }
        
        let getProfileResult = try? await clientProxy.profile(for: searchQuery).get()
        
        // fallback to a "local profile" if the profile api fails
        return getProfileResult ?? .init(userID: searchQuery)
    }
    
    // AGENT-PLATFORM (1.0.3): `@name` (no `:`, a valid localpart) → `@name:<own server>`, else nil.
    // Localparts are lowercase (spec grammar; Synapse registers no other), so `@Alice` finds `@alice`.
    private func bareHandleUserID(for searchQuery: String) -> String? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard query.hasPrefix("@"), !query.contains(":") else {
            return nil
        }
        
        let localpart = query.dropFirst().lowercased()
        
        guard !localpart.isEmpty,
              localpart.allSatisfy(Self.localpartCharacters.contains),
              let serverName = ownServerName else {
            return nil
        }
        
        let userID = "@\(localpart):\(serverName)"
        return userID.isMatrixIdentifier ? userID : nil
    }
    
    /// https://spec.matrix.org/latest/appendices/#user-identifiers
    private static let localpartCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789._=-/+")
    
    private var ownServerName: String? {
        Self.ownServerName(of: clientProxy)
    }
    
    private static func ownServerName(of clientProxy: ClientProxyProtocol) -> String? {
        if let serverName = clientProxy.userIDServerName, !serverName.isEmpty {
            return serverName
        }
        
        guard let separator = clientProxy.userID.firstIndex(of: ":") else {
            return nil
        }
        
        let serverName = clientProxy.userID[clientProxy.userID.index(after: separator)...]
        return serverName.isEmpty ? nil : String(serverName)
    }
    
    // AGENT-PLATFORM (1.0.3): people search shows only people — agents, bridge bots and puppets and the
    // official account are left out (operator, 2026-11-19). Agents are added and messaged from their own
    // screens (the room's agent picker, the agent's «Add to chat», «Message», «Contact agent»), never from here.
    /// The people among `profiles`: the one filter for the search results and for the Suggestions that
    /// Start chat and Invite users show before a query (`recentConversationCounterparts`).
    static func peopleOnly(_ profiles: [UserProfile], clientProxy: ClientProxyProtocol) -> [UserProfile] {
        guard let ownServerName = ownServerName(of: clientProxy) else {
            return profiles
        }
        return profiles.filter { !SpiralServiceAccount.isService($0.id, ownServerName: ownServerName) }
    }
    
    private func filterServiceAccounts(_ profiles: [UserProfile]) -> [UserProfile] {
        Self.peopleOnly(profiles, clientProxy: clientProxy)
    }
    
    private func isServiceAccount(_ userID: String) -> Bool {
        guard let ownServerName else {
            return false
        }
        return SpiralServiceAccount.isService(userID, ownServerName: ownServerName)
    }
    
    private func filterAccountOwner(_ profiles: [UserProfile]) -> [UserProfile] {
        let accountOwnerID = clientProxy.userID
        return profiles.filter { $0.id != accountOwnerID }
    }
}

private extension String {
    var isMatrixIdentifier: Bool {
        MatrixEntityRegex.isMatrixUserIdentifier(self)
    }
}
