//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
@testable import Spiral
import SwiftUI
import Testing

@MainActor
struct RoomHeaderTypingTests {
    private let online = UserPresence(userID: "@u:x", state: .online, lastActiveAgo: 2, currentlyActive: true, receivedAt: .now)
    
    @Test
    func nobodyTypingLeavesTheStatusAlone() {
        #expect(RoomHeaderView.Typing(members: [], isDM: true).text == nil)
        #expect(RoomHeaderView.Typing(members: [], isDM: false).text == nil)
    }
    
    @Test
    func aDMDoesNotRepeatTheNameInTheTitle() {
        #expect(RoomHeaderView.Typing(members: ["Alice"], isDM: true).text == "typing…")
    }
    
    @Test
    func aGroupSaysWhoIsTyping() {
        #expect(RoomHeaderView.Typing(members: ["Alice"]).text == "Alice is typing…")
        #expect(RoomHeaderView.Typing(members: ["Alice", "Bob"]).text == "Alice and Bob are typing…")
        #expect(RoomHeaderView.Typing(members: ["Alice", "Bob", "Charlie"]).text == "Alice, Bob and 1 other are typing…")
        #expect(RoomHeaderView.Typing(members: ["Alice", "Bob", "Charlie", "Dan"]).text == "Alice, Bob and 2 others are typing…")
    }
    
    @Test
    func aDMWithTwoPeopleTypingNamesThem() {
        #expect(RoomHeaderView.Typing(members: ["Alice", "Bob"], isDM: true).text == "Alice and Bob are typing…")
    }
    
    @Test(arguments: [("Lunch", false), ("Design team", false), ("Weekend trip with everybody", false), ("Bo", true), ("Helena Ortiz", true)])
    func theHeaderKeepsItsWidthWhenSomebodyTypes(roomName: String, isDM: Bool) {
        let presence = isDM ? online : nil
        let members = ["Alice with her very long display name", "Bob", "Charlie", "Dan"]
        
        let atRest = size(roomName: roomName, presence: presence, typing: .init(members: [], isDM: isDM))
        let typing = size(roomName: roomName, presence: presence, typing: .init(members: members, isDM: isDM))
        
        #expect(typing.width == atRest.width)
    }
    
    @Test
    func aShortRoomNameStillLeavesRoomForAName() {
        let width = size(roomName: "Lunch", presence: nil, typing: .init(members: [])).width
        let withoutTyping = size(roomName: "Lunch", presence: nil, typing: nil).width
        
        #expect(width > withoutTyping)
    }
    
    @Test
    func theHeaderHearsWhatTheRoomSays() async throws {
        let viewModels = RoomScreenTimeline_Previews.makeViewModels(name: "Weekend trip", items: [], typingMembers: ["Jacob"])
        
        let deferred = deferFulfillment(viewModels.timeline.context.$viewState) { $0.headerTyping.text == "Jacob is typing…" }
        try await deferred.fulfill()
    }
    
    // MARK: - A group's member count (question 392)
    
    @Test
    func aGroupCountsItsJoinedMembersAgentsToo() {
        let agent = RoomMemberProxyMock(with: .init(userID: "@assistant-alex:spiral.md", membership: .join))
        let invited = RoomMemberProxyMock(with: .init(userID: "@mira:spiral.md", displayName: "Mira Testova", membership: .invite))
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init(members: [.mockMe, .mockAlice, .mockBob, agent, invited])))
        
        #expect(viewModel.state.memberCount == 4)
        #expect(viewModel.state.headerSubtitle == "4 Members")
    }
    
    @Test
    func aDMKeepsItsStatusLine() {
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init(isDirect: true, members: [.mockMe, .mockAlice])))
        
        #expect(viewModel.state.isDM)
        #expect(viewModel.state.headerSubtitle == nil)
    }
    
    @Test
    func noCountYetIsNoLine() {
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: JoinedRoomProxyMock(.init(members: [])))
        
        #expect(viewModel.state.headerSubtitle == nil)
    }
    
    @Test
    func theCountFollowsTheRoom() async throws {
        var configuration = JoinedRoomProxyMockConfiguration(members: [.mockMe, .mockAlice])
        let roomProxy = JoinedRoomProxyMock(configuration)
        let infoSubject = CurrentValueSubject<RoomInfoProxyProtocol, Never>(RoomInfoProxyMock(configuration))
        roomProxy.infoPublisher = infoSubject.asCurrentValuePublisher()
        let viewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxy)
        #expect(viewModel.state.memberCount == 2)
        
        let deferred = deferFulfillment(viewModel.context.$viewState) { $0.memberCount == 3 }
        configuration.members.append(.mockBob)
        infoSubject.send(RoomInfoProxyMock(configuration))
        try await deferred.fulfill()
    }
    
    @Test
    func theCountIsPluralisedByLanguage() {
        defer { Bundle.overrideLocalizations = nil }
        
        Bundle.overrideLocalizations = ["ru"]
        #expect(L10n.commonMemberCount(1) == "1 участник")
        #expect(L10n.commonMemberCount(4) == "4 участника")
        #expect(L10n.commonMemberCount(5) == "5 участников")
        #expect(L10n.commonMemberCount(22) == "22 участника")
        Bundle.overrideLocalizations = ["pl"]
        #expect(L10n.commonMemberCount(3) == "3 członkowie")
        Bundle.overrideLocalizations = ["uk"]
        #expect(L10n.commonMemberCount(4) == "4 учасники")
    }
    
    @Test(arguments: [["Alex Sample"], ["Alex Sample", "Mira Testova", "Bob"]])
    func typingTakesTheCountsLineWithoutMovingTheHeader(members: [String]) {
        let count = L10n.commonMemberCount(4)
        
        let atRest = size(roomName: "Design team", subtitle: count, presence: nil, typing: .init(members: []))
        let typing = size(roomName: "Design team", subtitle: count, presence: nil, typing: .init(members: members))
        
        #expect(typing == atRest)
    }
    
    @Test
    func aGroupsLineIsTheHeightOfADMsStatus() {
        let group = size(roomName: "Design team", subtitle: L10n.commonMemberCount(4), presence: nil, typing: .init(members: []))
        let dm = size(roomName: "Alex Sample", presence: online, typing: .init(members: [], isDM: true))
        
        #expect(group.height == dm.height)
    }
    
    // MARK: - Helpers
    
    private func size(roomName: String, subtitle: String? = nil, presence: UserPresence?, typing: RoomHeaderView.Typing?) -> CGSize {
        let header = RoomHeaderView(roomName: roomName,
                                    roomSubtitle: subtitle,
                                    roomAvatar: .room(id: "1", name: roomName, avatarURL: nil),
                                    dmRecipientDetails: .init(presence: presence),
                                    typing: typing,
                                    isCapsule: true,
                                    mediaProvider: nil) { }
        return UIHostingController(rootView: header).sizeThatFits(in: CGSize(width: 320, height: 100))
    }
}
