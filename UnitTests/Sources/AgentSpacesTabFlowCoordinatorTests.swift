//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the Agents tab's transition table, every state × event.
// An unrouted event is a `fatalError`, so the table is the crash surface:
// the step B review found the agent's flow ending under the bell hub
// (archive, or the agent popped on iPhone) with no route for `.deselectAgent`.
//

import Combine
@testable import ElementX
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
                                                  visibility: "public", lifecycleState: "active", presence: .online,
                                                  roomCount: 1, activeToolCount: 0)

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
    
    private func makeFlowCoordinator(navigationStackCoordinator: NavigationStackCoordinator) -> AgentFlowCoordinator {
        let clientProxy = ClientProxyMock(.init(userID: "@owner:spiral.md",
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(.mockRooms)))))
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.notFound)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [], nextCursor: nil))
        service.listMyPersonalAgentsReturnValue = .success(.init(agents: [], provisioningStatus: .ready))
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: "1", agents: [])) // the room screen's tools banner
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        userSession.agentPlatformService = service
        
        let appSettings = AppSettings.volatile()
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  bugReportService: BugReportServiceMock(.init()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()),
                                                  emojiProvider: EmojiProvider(appSettings: appSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  appSettings: appSettings,
                                                  appHooks: AppHooks(),
                                                  analytics: AnalyticsServiceMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  notificationManager: NotificationManagerMock(),
                                                  stateMachineFactory: StateMachineFactory())
        
        return AgentFlowCoordinator(selection: .init(card: Self.card, companyName: nil),
                                    agentPlatformService: service,
                                    navigationStackCoordinator: navigationStackCoordinator,
                                    flowParameters: flowParameters)
    }
}
