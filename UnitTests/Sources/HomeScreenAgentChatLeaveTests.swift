//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
import MatrixRustSDKMocks
@testable import Spiral
import Testing

/// Question 359: the person's own assistant stays with their account, so its chat offers no Leave — on the chat's page
/// and, the same, when its row is held in Chats.
@MainActor
struct HomeScreenAgentChatLeaveTests {
    @Test
    func theOwnAssistantsChatOffersNoLeave() async throws {
        let userSession = UserSessionMock(.init(userSettings: UserSettings.mock()))
        AgentProfileMock.configure(userSession)
        let rooms = [Self.dm(id: "!own", with: AgentProfileMock.assistant.matrixUserID),
                     Self.dm(id: "!sales", with: AgentProfileMock.salesAgent.matrixUserID),
                     Self.dm(id: "!others", with: "@assistant-bob:spiral.md"),
                     Self.dm(id: "!person", with: "@bob:spiral.md")]
        userSession.clientProxy = ClientProxyMock(.init(userID: "@anna:spiral.md",
                                                        roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms)))))
        let viewModel = HomeScreenViewModel(userSession: userSession,
                                            availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                            selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                            analyticsService: AnalyticsServiceMock(.init()),
                                            bugReportService: BugReportServiceMock(.init()),
                                            userIndicatorController: UserIndicatorControllerMock())
        // The Agents tab keeps the person's spaces read.
        let agentsTab = NSObject()
        let spacesRead = deferFulfillment(viewModel.context.$viewState) { state in
            state.rooms.count == 4 && state.rooms.first { $0.id == "!others" }?.offersLeave == true
        }
        userSession.agentsStore?.show(.spaces, by: agentsTab)
        try await spacesRead.fulfill()
        
        let offersLeave = Dictionary(uniqueKeysWithValues: viewModel.context.viewState.rooms.map { ($0.id, $0.offersLeave) })
        #expect(offersLeave["!own"] == false)
        #expect(offersLeave["!sales"] == true, "the person's company agent can be left")
        #expect(offersLeave["!others"] == true, "someone else's assistant can be left")
        #expect(offersLeave["!person"] == true)
        userSession.agentsStore?.stopShowing(.spaces, by: agentsTab)
    }
    
    private static func dm(id: String, with userID: String) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(), id: id, joinRequestType: nil, isJoined: true, name: userID, isDirect: true, isSpace: false,
                    avatarURL: nil, heroes: [.init(userID: userID)], activeMembersCount: 2, lastMessage: nil, lastMessageDate: nil,
                    lastMessageState: nil, unreadMessagesCount: 0, unreadMentionsCount: 0, unreadNotificationsCount: 0,
                    notificationMode: nil, canonicalAlias: nil, alternativeAliases: [], hasOngoingCall: false, activeCallIntent: nil,
                    isMarkedUnread: false, isFavourite: false, isTombstoned: false)
    }
}
