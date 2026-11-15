//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the people and agents the previews of an agent's page show.
//

import Foundation

enum AgentProfileMock {
    static let assistant = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-anna:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                               avatarMXC: nil, kind: "personal_assistant", visibility: "private", lifecycleState: "active",
                                               roomCount: 3, activeToolCount: 2)
    static let salesAgent = AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md", displayName: "Sales · Acme Corp",
                                                avatarMXC: nil, kind: "sales", visibility: "public", lifecycleState: "active",
                                                roomCount: 12, activeToolCount: 0)
    /// Someone else's: the person has no card of it.
    static let othersAgentID = "@agent-lida-sales:spiral.md"
    
    static func member(_ card: AgentSpaceAgentCard) -> RoomMemberProxyMock {
        .init(with: .init(userID: card.matrixUserID, displayName: card.displayName, membership: .join))
    }
    
    static var othersAgent: RoomMemberProxyMock {
        .init(with: .init(userID: othersAgentID, displayName: "Lida · sales", membership: .join))
    }
    
    static var spaces: Result<AgentSpacesDirectory, AgentPlatformError> {
        .success(.init(spaces: [.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 2)], provisioningStatus: .ready))
    }
    
    /// How the read of the person's spaces goes.
    enum SpacesRead {
        case answers
        /// Never answers: a page's first render, held.
        case hangs
        case fails
    }
    
    /// Gives `userSession` the person's two agents, and shows every agent online.
    @discardableResult
    static func configure(_ userSession: UserSessionMock, spacesRead: SpacesRead = .answers) -> AgentPlatformServiceMock {
        let cards = [assistant, salesAgent]
        let service = AgentPlatformServiceMock()
        switch spacesRead {
        case .answers:
            service.listMyAgentSpacesReturnValue = spaces
        case .hangs:
            service.listMyAgentSpacesClosure = {
                try? await Task.sleep(for: .seconds(3600))
                return .failure(.serverError(status: 503))
            }
        case .fails:
            service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        }
        service.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                 industry: nil, website: nil, agents: cards))
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: "!dm_room:spiral.md", agents: []))
        service.listAgentBlocksOfContactReturnValue = .success([])
        userSession.agentPlatformService = service
        userSession.agentsStore = AgentsStore(service: service)
        
        let presences = (cards.map(\.matrixUserID) + [othersAgentID]).reduce(into: [String: UserPresence]()) { presences, userID in
            presences[userID] = .init(userID: userID, state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now)
        }
        let presenceService = PresenceObserverServiceMock()
        presenceService.underlyingPresencePublisher = .init(presences)
        userSession.presenceObserverService = presenceService
        return service
    }
}
