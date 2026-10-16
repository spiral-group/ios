//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 98): the messenger's block and unblock alerts say
// what happens to the owner's agents, where there are agents to speak of.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct SpiralOwnerBlockAlertsTests {
    @Test(arguments: [true, false])
    func memberDetailsBlockAlertsNameTheAgents(hasAgents: Bool) throws {
        let viewModel = makeMemberDetails(hasAgents: hasAgents)

        viewModel.context.send(viewAction: .showIgnoreAlert)
        let block = try #require(viewModel.context.ignoreUserAlert)
        #expect(block.description.hasPrefix(L10n.screenRoomMemberDetailsBlockAlertDescription))
        #expect(block.description.contains(UntranslatedL10n.screenRoomMemberDetailsBlockAlertAgents) == hasAgents)

        viewModel.context.send(viewAction: .showUnignoreAlert)
        let unblock = try #require(viewModel.context.ignoreUserAlert)
        #expect(unblock.description.hasPrefix(L10n.screenRoomMemberDetailsUnblockAlertDescription))
        #expect(unblock.description.contains(UntranslatedL10n.screenRoomMemberDetailsUnblockAlertAgents) == hasAgents)
    }

    @Test
    func dmDetailsBlockAlertsNameTheAgents() {
        typealias Item = RoomDetailsScreenViewStateBindings.IgnoreUserAlertItem
        #expect(Item(action: .ignore, mentionsAgents: true).description
            == "\(L10n.screenDmDetailsBlockAlertDescription)\n\n\(UntranslatedL10n.screenRoomMemberDetailsBlockAlertAgents)")
        #expect(Item(action: .unignore, mentionsAgents: true).description
            == "\(L10n.screenDmDetailsUnblockAlertDescription)\n\n\(UntranslatedL10n.screenRoomMemberDetailsUnblockAlertAgents)")
        #expect(Item(action: .ignore).description == L10n.screenDmDetailsBlockAlertDescription)
    }

    @Test(arguments: [true, false])
    func blockedUsersUnblockAlertNamesTheAgents(hasAgents: Bool) throws {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        if hasAgents {
            userSession.agentPlatformService = AgentPlatformServiceMock()
        }
        let viewModel = BlockedUsersScreenViewModel(hideProfiles: true, userSession: userSession, userIndicatorController: UserIndicatorControllerMock())

        viewModel.context.send(viewAction: .unblockUser(UserProfile(userID: "@bob:spiral.md")))

        let message = try #require(viewModel.context.alertInfo?.message)
        #expect(message.hasPrefix(L10n.screenBlockedUsersUnblockAlertDescription))
        #expect(message.contains(UntranslatedL10n.screenRoomMemberDetailsUnblockAlertAgents) == hasAgents)
    }

    private func makeMemberDetails(hasAgents: Bool) -> RoomMemberDetailsScreenViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getMemberUserIDReturnValue = .success(RoomMemberProxyMock.mockAlice)
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        if hasAgents {
            let service = AgentPlatformServiceMock()
            service.listAgentBlocksOfContactReturnValue = .success([])
            userSession.agentPlatformService = service
        }
        return RoomMemberDetailsScreenViewModel(userID: RoomMemberProxyMock.mockAlice.userID,
                                                roomProxy: roomProxy,
                                                userSession: userSession,
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                analytics: AnalyticsServiceMock(.init()))
    }
}
