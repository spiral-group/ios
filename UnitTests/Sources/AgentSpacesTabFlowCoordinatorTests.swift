//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the Agents tab's transition table, every state × event.
// An unrouted event is a `fatalError`, so the table is the crash surface:
// the step B review found the agent's flow ending under the bell hub
// (archive, or the agent popped on iPhone) with no route for `.deselectAgent`.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct AgentSpacesTabFlowCoordinatorTests {
    typealias State = AgentSpacesTabFlowCoordinator.State
    typealias Event = AgentSpacesTabFlowCoordinator.Event

    static let states: [State] = [.initial,
                                  .agentSpacesScreen(selectedAgentID: nil),
                                  .agentSpacesScreen(selectedAgentID: "agent"),
                                  .createCompanyFlow(selectedAgentID: nil),
                                  .createCompanyFlow(selectedAgentID: "agent"),
                                  .notificationsHub(selectedAgentID: nil),
                                  .notificationsHub(selectedAgentID: "agent")]

    static let events: [Event] = [.start, .selectAgent, .deselectAgent,
                                  .startCreateCompanyFlow, .dismissedCreateCompanyFlow,
                                  .openNotificationsHub, .popNotificationsHub]

    private func next(_ state: State, _ event: Event) -> State? {
        AgentSpacesTabFlowCoordinator.nextState(from: state, on: event, selectedAgentID: event == .selectAgent ? "other" : nil)
    }

    @Test
    func deselectFromTheHubKeepsTheHubAndClearsTheSelection() {
        #expect(next(.notificationsHub(selectedAgentID: "agent"), .deselectAgent) == .notificationsHub(selectedAgentID: nil))
        #expect(next(.notificationsHub(selectedAgentID: "agent"), .deselectAgent).flatMap { next($0, .popNotificationsHub) }
            == .agentSpacesScreen(selectedAgentID: nil))
    }

    @Test
    func deselectIsRoutedFromEveryStartedState() {
        for state in Self.states where state != .initial {
            let result = next(state, .deselectAgent)
            #expect(result != nil, "No route for .deselectAgent from \(state)")
            switch result {
            case .agentSpacesScreen(let selected), .createCompanyFlow(let selected), .notificationsHub(let selected):
                #expect(selected == nil)
            case .initial, .none:
                Issue.record("Deselect from \(state) went to \(String(describing: result))")
            }
        }
    }

    @Test
    func createCompanyKeepsTheOpenAgent() {
        // iPad: the agent beside the sheet stays open, so its later archive
        // still has a selection to clear.
        let afterSheet = next(.agentSpacesScreen(selectedAgentID: "agent"), .startCreateCompanyFlow)
        #expect(afterSheet == .createCompanyFlow(selectedAgentID: "agent"))
        #expect(afterSheet.flatMap { next($0, .dismissedCreateCompanyFlow) } == .agentSpacesScreen(selectedAgentID: "agent"))
    }

    @Test
    func everyStateAndEvent() {
        let routed: [State: [Event: State]] = [
            .initial: [.start: .agentSpacesScreen(selectedAgentID: nil)],
            .agentSpacesScreen(selectedAgentID: nil): [.selectAgent: .agentSpacesScreen(selectedAgentID: "other"),
                                                       .deselectAgent: .agentSpacesScreen(selectedAgentID: nil),
                                                       .startCreateCompanyFlow: .createCompanyFlow(selectedAgentID: nil),
                                                       .openNotificationsHub: .notificationsHub(selectedAgentID: nil)],
            .agentSpacesScreen(selectedAgentID: "agent"): [.selectAgent: .agentSpacesScreen(selectedAgentID: "other"),
                                                           .deselectAgent: .agentSpacesScreen(selectedAgentID: nil),
                                                           .startCreateCompanyFlow: .createCompanyFlow(selectedAgentID: "agent"),
                                                           .openNotificationsHub: .notificationsHub(selectedAgentID: "agent")],
            .createCompanyFlow(selectedAgentID: nil): [.deselectAgent: .createCompanyFlow(selectedAgentID: nil),
                                                       .dismissedCreateCompanyFlow: .agentSpacesScreen(selectedAgentID: nil)],
            .createCompanyFlow(selectedAgentID: "agent"): [.deselectAgent: .createCompanyFlow(selectedAgentID: nil),
                                                           .dismissedCreateCompanyFlow: .agentSpacesScreen(selectedAgentID: "agent")],
            .notificationsHub(selectedAgentID: nil): [.deselectAgent: .notificationsHub(selectedAgentID: nil),
                                                      .popNotificationsHub: .agentSpacesScreen(selectedAgentID: nil)],
            .notificationsHub(selectedAgentID: "agent"): [.deselectAgent: .notificationsHub(selectedAgentID: nil),
                                                          .popNotificationsHub: .agentSpacesScreen(selectedAgentID: "agent")]
        ]

        for state in Self.states {
            for event in Self.events {
                #expect(next(state, event) == routed[state]?[event], "\(state) × \(event)")
            }
        }
    }
}

/// An agent's own flow: an activity row's chat opens on the agent's stack.
@MainActor
struct AgentFlowCoordinatorTests {
    private static let card = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                  displayName: "Assistant", avatarMXC: nil, kind: "personal_assistant",
                                                  visibility: "public", lifecycleState: "active", roomCount: 1, activeToolCount: 0)

    /// The chat is pushed over the agent's screens, so back returns to them
    /// and the owner stays on the Agents tab.
    @Test
    func anActivityRowsChatOpensOnTheAgentsStack() async throws {
        let navigationStackCoordinator = NavigationStackCoordinator()
        let flowCoordinator = makeFlowCoordinator(navigationStackCoordinator: navigationStackCoordinator)
        var actions: [AgentFlowCoordinatorAction] = []
        let cancellable = flowCoordinator.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }
        
        flowCoordinator.start(animated: false)
        #expect(navigationStackCoordinator.rootCoordinator is AgentDetailScreenCoordinator)
        
        flowCoordinator.openRoom(roomID: "1")
        let pushed = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 1 }
        try await pushed.fulfill()
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomScreenCoordinator)
        #expect(navigationStackCoordinator.rootCoordinator is AgentDetailScreenCoordinator)
        #expect(actions.isEmpty)
    }
    
    /// «Open chat» of the agent in a chat that isn't the one the flow came from opens it on the agent's stack.
    @Test
    func openChatOfAnotherChatOpensItOnTheAgentsStack() async throws {
        let navigationStackCoordinator = NavigationStackCoordinator()
        var asked: [String] = []
        let flowCoordinator = makeFlowCoordinator(navigationStackCoordinator: navigationStackCoordinator) { roomID in
            asked.append(roomID)
            return false
        }
        flowCoordinator.start(animated: false)
        
        flowCoordinator.openChat(roomID: "1")
        let pushed = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 1 }
        try await pushed.fulfill()
        
        #expect(asked == ["1"])
        #expect(navigationStackCoordinator.stackCoordinators.last is RoomScreenCoordinator)
    }
    
    /// A second tap on a room that is still opening doesn't start a second flow.
    @Test
    func aSecondTapOnAChatThatIsOpeningPushesItOnce() async throws {
        let navigationStackCoordinator = NavigationStackCoordinator()
        let flowCoordinator = makeFlowCoordinator(navigationStackCoordinator: navigationStackCoordinator)
        flowCoordinator.start(animated: false)
        
        flowCoordinator.openRoom(roomID: "1")
        flowCoordinator.openRoom(roomID: "1")
        let pushed = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 1 }
        try await pushed.fulfill()
        
        let pushedAgain = deferFailure(navigationStackCoordinator.observe(\.stackCoordinators.count), timeout: .seconds(1)) { $0 != 1 }
        try await pushedAgain.fulfill()
        #expect(navigationStackCoordinator.stackCoordinators.count == 1)
    }
    
    /// «Open chat» of the chat the flow came from returns to that chat, and doesn't stack a second copy of it.
    @Test
    func openChatOfTheOriginChatLeavesItToItsOwnFlow() async throws {
        let navigationStackCoordinator = NavigationStackCoordinator()
        var asked: [String] = []
        let flowCoordinator = makeFlowCoordinator(navigationStackCoordinator: navigationStackCoordinator) { roomID in
            asked.append(roomID)
            return true
        }
        flowCoordinator.start(animated: false)
        
        flowCoordinator.openChat(roomID: "1")
        let notPushed = deferFailure(navigationStackCoordinator.observe(\.stackCoordinators.count), timeout: .seconds(1)) { $0 != 0 }
        try await notPushed.fulfill()
        
        #expect(asked == ["1"])
        #expect(navigationStackCoordinator.stackCoordinators.isEmpty)
    }
    
    private func makeFlowCoordinator(navigationStackCoordinator: NavigationStackCoordinator,
                                     showOriginRoom: ((String) -> Bool)? = nil) -> AgentFlowCoordinator {
        let clientProxy = ClientProxyMock(.init(userID: "@owner:spiral.md",
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))))
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        // Not a 404, which says the agent is gone and closes its flow.
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 503))
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [], nextCursor: nil))
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [], provisioningStatus: .ready))
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: "1", agents: [])) // the room screen's tools banner
        // AGENT-PLATFORM: platform sync (decision 289): the agent screen shows what waits for the owner.
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [], activity: [], nextActivityCursor: nil,
                                                                                  lastSeenAt: nil, unseenCount: 0))
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        
        let appSettings = AppSettings.volatile()
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  stateMachineFactory: StateMachineFactory())
        
        return AgentFlowCoordinator(selection: .init(card: Self.card, companyName: nil),
                                    agentPlatformService: service,
                                    agentsStore: AgentsStore(service: service),
                                    navigationStackCoordinator: navigationStackCoordinator,
                                    flowParameters: flowParameters,
                                    showOriginRoom: showOriginRoom)
    }
}
