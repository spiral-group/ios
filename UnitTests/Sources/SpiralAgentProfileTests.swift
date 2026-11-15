//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): whose agent a page shows, what it offers, and what its rows open.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct SpiralAgentProfileTests {
    private static let assistant = AgentProfileMock.assistant
    private static let salesAgent = AgentProfileMock.salesAgent
    private static let othersID = AgentProfileMock.othersAgentID
    private static let roomID = "!dm_room:spiral.md"
    private static let roomAgent = RoomToolAgentEntry(agentID: "agent-2", matrixUserID: salesAgent.matrixUserID, displayName: "Sales",
                                                      ownerUserID: "@me:spiral.md", isMine: true, tools: [])
    
    // MARK: - Whose agent it is
    
    @Test
    func aPersonHasNoAgentPage() {
        #expect(SpiralAgentProfile(userID: "@alice:spiral.md", ownership: .someoneElses) == nil)
    }
    
    @Test
    func theOwnersAgentHasItsCard() throws {
        let profile = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: .own(Self.assistant)))
        #expect(profile.ownCard == Self.assistant)
        #expect(!profile.offersVerify)
        #expect(!profile.offersBlock(isBlocked: false))
    }
    
    @Test
    func someoneElsesAgentHasNoCard() throws {
        let profile = try #require(SpiralAgentProfile(userID: Self.othersID, ownership: .someoneElses))
        #expect(profile.ownCard == nil)
        #expect(profile.offersVerify)
        #expect(profile.offersBlock(isBlocked: false))
    }
    
    /// While it's read the page offers nothing that the answer may take back.
    @Test
    func whileItIsReadNothingIsOfferedThatMayGo() throws {
        let profile = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: .unknown(isReading: true)))
        #expect(profile.isReadingOwnership)
        #expect(profile.ownCard == nil)
        #expect(!profile.offersVerify)
        #expect(!profile.offersBlock(isBlocked: false))
        #expect(!profile.offersLeave, "this may be the person's own assistant")
        #expect(profile.roleLine == UntranslatedL10n.screenProfileAgentKindAssistant)
        
        let roleAgent = try #require(SpiralAgentProfile(userID: Self.othersID, ownership: .unknown(isReading: true)))
        #expect(roleAgent.offersLeave, "no agent of this kind loses Leave")
    }
    
    /// A failed read offers no owner's rows, and hides nothing that protects the person.
    @Test
    func aFailedReadIsTheSafePage() throws {
        let profile = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: .unknown(isReading: false)))
        #expect(!profile.isReadingOwnership)
        #expect(profile.ownCard == nil)
        #expect(profile.offersVerify)
        #expect(profile.offersBlock(isBlocked: false))
        #expect(profile.offersLeave)
    }
    
    /// Hiding Block must not leave a blocked agent without its way back, whatever is known.
    @Test
    func aBlockedAgentKeepsUnblock() throws {
        for ownership in [AgentOwnership.own(Self.assistant), .unknown(isReading: true)] {
            let profile = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: ownership))
            #expect(profile.offersBlock(isBlocked: true))
        }
    }
    
    /// Only the person's own assistant loses Leave.
    @Test
    func onlyTheOwnAssistantHasNoLeave() throws {
        let assistant = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: .own(Self.assistant)))
        #expect(!assistant.offersLeave)
        
        let sales = try #require(SpiralAgentProfile(userID: Self.salesAgent.matrixUserID, ownership: .own(Self.salesAgent)))
        #expect(sales.offersLeave)
    }
    
    // MARK: - The role line
    
    @Test
    func theOwnersAgentsSayWhatTheyAre() throws {
        let assistant = try #require(SpiralAgentProfile(userID: Self.assistant.matrixUserID, ownership: .own(Self.assistant)))
        #expect(assistant.roleLine == UntranslatedL10n.screenAgentDetailKindPersonalAssistant)
        
        let sales = try #require(SpiralAgentProfile(userID: Self.salesAgent.matrixUserID, ownership: .own(Self.salesAgent)))
        #expect(sales.roleLine == UntranslatedL10n.screenCreateAgentRoleSales)
    }
    
    @Test
    func someoneElsesAgentSaysWhatItsIDSays() {
        #expect(SpiralAgentProfile(userID: "@assistant-lida:spiral.md", ownership: .someoneElses)?.roleLine == UntranslatedL10n.screenProfileAgentKindAssistant)
        #expect(SpiralAgentProfile(userID: Self.othersID, ownership: .someoneElses)?.roleLine == UntranslatedL10n.screenProfileAgentKindAgent)
    }
    
    @Test
    func anOwnAgentOfAnUnknownKindSaysWhatItsIDSays() {
        let card = AgentSpaceAgentCard(agentID: "agent-3", matrixUserID: "@agent-acme-new:spiral.md", displayName: "New", avatarMXC: nil, kind: "newer_role",
                                       visibility: "public", lifecycleState: "active", roomCount: 0, activeToolCount: 0)
        #expect(SpiralAgentProfile(userID: card.matrixUserID, ownership: .own(card))?.roleLine == UntranslatedL10n.screenProfileAgentKindAgent)
    }
    
    @Test
    func anIDOfNeitherKindIsNoAgent() {
        #expect(SpiralAppPostSession.agentIDKind("@assistant-a:spiral.md") == .assistant)
        #expect(SpiralAppPostSession.agentIDKind("@agent-a:spiral.md") == .agent)
        #expect(SpiralAppPostSession.agentIDKind("@agentsmith:spiral.md") == nil)
        #expect(SpiralAppPostSession.agentIDKind("assistant-a") == nil)
    }
    
    // MARK: - The chat's page
    
    @Test
    func theChatsPageFindsTheOwnAgent() async throws {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant))
        let found = deferFulfillment(viewModel.context.observe(\.viewState.ownAgentCard)) { $0 == Self.assistant }
        try await found.fulfill()
        
        #expect(!viewModel.context.viewState.showsBlockRow)
        
        let opened = deferFulfillment(viewModel.actions) { $0 == .openAgentRow(.chats, card: Self.assistant) }
        viewModel.context.send(viewAction: .processTapAgentRow(.chats))
        try await opened.fulfill()
    }
    
    // MARK: - Settings or Mute (question 391)
    
    @Test
    func theOwnAssistantsChatHasSettingsForItsScreen() async throws {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), storeHoldsSpaces: true)
        #expect(viewModel.context.viewState.showsAgentSettings)
        
        let opened = deferFulfillment(viewModel.actions) { $0 == .openAgentRow(.settings, card: Self.assistant) }
        viewModel.context.send(viewAction: .processTapAgentRow(.settings))
        try await opened.fulfill()
    }
    
    /// Tools was there for each of the person's own agents, so Settings is too.
    @Test
    func theOwnRoleAgentsChatHasSettings() async {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.salesAgent), storeHoldsSpaces: true)
        #expect(viewModel.context.viewState.showsAgentSettings)
    }
    
    @Test
    func someoneElsesAgentAndAPersonKeepMute() async throws {
        let (othersAgent, _) = await makeRoomDetails(recipient: AgentProfileMock.othersAgent)
        let read = deferFulfillment(othersAgent.context.observe(\.viewState.agentOwnership)) { $0 == .someoneElses }
        try await read.fulfill()
        #expect(!othersAgent.context.viewState.showsAgentSettings)
        
        let (person, _) = await makeRoomDetails(recipient: .mockDan, storeHoldsSpaces: true)
        #expect(!person.context.viewState.showsAgentSettings)
    }
    
    @Test
    func aChatStillReadingWhoseTheAgentIsHasNoSettings() async {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), spacesRead: .hangs)
        #expect(viewModel.context.viewState.agentProfile?.isReadingOwnership == true)
        #expect(!viewModel.context.viewState.showsAgentSettings)
    }
    
    /// A group keeps Mute, and its agents' tools stay behind the Agents row.
    @Test
    func aGroupKeepsMuteAndItsAgentsRow() {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        AgentProfileMock.configure(userSession)
        let roomProxy = JoinedRoomProxyMock(.init(id: Self.roomID, name: "Design team", isDirect: false, isEncrypted: false,
                                                  members: [.mockMe, .mockDan, AgentProfileMock.member(Self.assistant)]))
        let viewModel = RoomDetailsScreenViewModel(roomProxy: roomProxy,
                                                   userSession: userSession,
                                                   analyticsService: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: UserIndicatorControllerMock(),
                                                   notificationSettingsProxy: NotificationSettingsProxyMock(with: .init()),
                                                   attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()))
        
        #expect(!viewModel.context.viewState.showsAgentSettings)
        #expect(viewModel.context.viewState.showsAgentsRow)
    }
    
    /// The page takes its shape before it's pushed: nothing here waits for a member or a read.
    @Test
    func theChatsPageHasItsShapeAtInit() async {
        let (viewModel, service) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), storeHoldsSpaces: true)
        let state = viewModel.context.viewState
        
        #expect(state.dmUserID == Self.assistant.matrixUserID)
        #expect(state.dmRecipientInfo == nil, "the members are still on their way")
        #expect(state.ownAgentCard == Self.assistant)
        #expect(!state.showsBlockRow)
        #expect(!state.showsLeaveRow)
        #expect(service.listMyAgentSpacesCallsCount == 1, "the store's read, and none of the page's own")
    }
    
    @Test
    func aPersonsChatHasItsShapeAtInit() async {
        let (viewModel, _) = await makeRoomDetails(recipient: .mockDan, storeHoldsSpaces: true)
        
        #expect(viewModel.context.viewState.dmUserID == RoomMemberProxyMock.mockDan.userID)
        #expect(viewModel.context.viewState.agentProfile == nil)
    }
    
    /// The spaces aren't in memory yet: the sparkle's page, with nothing on it that the answer may take back.
    @Test
    func theChatsPageHoldsItsPlaceWhileReading() async throws {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), spacesRead: .hangs)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.dmRecipientInfo?.member.id)) { $0 != nil }
        try await loaded.fulfill()
        
        let state = viewModel.context.viewState
        #expect(state.agentProfile?.isReadingOwnership == true)
        #expect(state.ownAgentCard == nil)
        #expect(!state.showsBlockRow)
        #expect(!state.showsLeaveRow)
    }
    
    /// A failed read is the safe page with Block, and a reappearing page reads again.
    @Test
    func aFailedReadOnTheChatsPageKeepsBlockUntilTheNextRead() async throws {
        let (viewModel, service) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), spacesRead: .fails)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState)) { $0.dmRecipientInfo != nil && $0.agentOwnership == .unknown(isReading: false) }
        try await failed.fulfill()
        
        #expect(viewModel.context.viewState.ownAgentCard == nil)
        #expect(viewModel.context.viewState.showsBlockRow)
        
        service.listMyAgentSpacesReturnValue = AgentProfileMock.spaces
        let read = deferFulfillment(viewModel.context.observe(\.viewState.ownAgentCard)) { $0 == Self.assistant }
        viewModel.context.send(viewAction: .appeared)
        try await read.fulfill()
        #expect(!viewModel.context.viewState.showsBlockRow)
    }
    
    /// Reappearing reads again, and meanwhile the page stays the safe one: Block doesn't go for the length of a read.
    @Test
    func theSafePageStaysWhileAReappearingPageReadsAgain() async throws {
        let (viewModel, service) = await makeRoomDetails(recipient: AgentProfileMock.member(Self.assistant), spacesRead: .fails)
        let failed = deferFulfillment(viewModel.context.observe(\.viewState)) { $0.dmRecipientInfo != nil && $0.agentOwnership == .unknown(isReading: false) }
        try await failed.fulfill()
        
        let reads = service.listMyAgentSpacesCallsCount
        service.listMyAgentSpacesClosure = {
            try? await Task.sleep(for: .seconds(3600))
            return .failure(.serverError(status: 503))
        }
        viewModel.context.send(viewAction: .appeared)
        for _ in 0..<200 where service.listMyAgentSpacesCallsCount == reads {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(service.listMyAgentSpacesCallsCount == reads + 1)
        #expect(viewModel.context.viewState.agentOwnership == .unknown(isReading: false))
        #expect(viewModel.context.viewState.showsBlockRow)
    }
    
    @Test
    func someoneElsesAgentKeepsBlockOnTheChatsPage() async throws {
        let (viewModel, _) = await makeRoomDetails(recipient: AgentProfileMock.othersAgent)
        let read = deferFulfillment(viewModel.context.observe(\.viewState)) { $0.agentOwnership == .someoneElses && $0.dmRecipientInfo != nil }
        try await read.fulfill()
        
        #expect(viewModel.context.viewState.agentProfile?.roleLine == UntranslatedL10n.screenProfileAgentKindAgent)
        #expect(viewModel.context.viewState.ownAgentCard == nil)
        #expect(viewModel.context.viewState.showsBlockRow)
    }
    
    /// The room info names someone who has left: the members have the last word, or Block's placeholder stays for ever.
    @Test
    func theMembersOverruleTheRoomInfo() async throws {
        let left = RoomMemberProxyMock(with: .init(userID: Self.othersID, displayName: "Left", membership: .leave))
        let (viewModel, _) = await makeRoomDetails(recipient: left)
        #expect(viewModel.context.viewState.dmUserID == Self.othersID)
        
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.dmUserID)) { $0 == nil }
        try await settled.fulfill()
        #expect(viewModel.context.viewState.agentProfile == nil)
    }
    
    // MARK: - The chat's agents
    
    @Test
    func theAgentsCountComesFromTheStore() async throws {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        let service = AgentProfileMock.configure(userSession)
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: Self.roomID, agents: [Self.roomAgent]))
        let store = try #require(userSession.agentsStore)
        await store.reread(.roomTools(roomID: Self.roomID))
        
        let viewModel = makeRoomDetails(recipient: .mockDan, userSession: userSession)
        #expect(viewModel.context.viewState.agentsCount == 1, "shown at once, from what the session holds")
        
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: Self.roomID, agents: []))
        let followed = deferFulfillment(viewModel.context.observe(\.viewState.agentsCount)) { $0 == 0 }
        await store.reread(.roomTools(roomID: Self.roomID))
        try await followed.fulfill()
    }
    
    /// Others' agents don't come on the owner's stream, so opening the page reads the room's again.
    @Test
    func openingThePageReadsTheRoomsAgentsAgain() async throws {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        let service = AgentProfileMock.configure(userSession)
        let store = try #require(userSession.agentsStore)
        await store.reread(.roomTools(roomID: Self.roomID))
        
        _ = makeRoomDetails(recipient: .mockDan, userSession: userSession)
        await store.settle()
        
        #expect(service.fetchRoomToolsRoomIDCallsCount == 2)
    }
    
    @Test
    func aPersonsChatReadsNoAgents() async throws {
        let (viewModel, service) = await makeRoomDetails(recipient: .mockDan)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.dmRecipientInfo?.member.id)) { $0 != nil }
        try await loaded.fulfill()
        
        #expect(service.listMyAgentSpacesCallsCount == 0)
        #expect(viewModel.context.viewState.agentProfile == nil)
        #expect(viewModel.context.viewState.showsBlockRow)
    }
    
    // MARK: - The profile pages
    
    @Test
    func theMemberPageDropsVerifyAndBlockForTheOwnAgent() async throws {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.member(Self.assistant))
        let found = deferFulfillment(viewModel.context.$viewState) { $0.agentProfile?.ownCard == Self.assistant && $0.verificationState != nil }
        try await found.fulfill()
        
        #expect(!viewModel.context.viewState.showVerifyIdentitySection)
        #expect(!viewModel.context.viewState.showBlockUserSection)
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)
    }
    
    @Test
    func theMemberPageKeepsVerifyBlockAndTheEraseForSomeoneElsesAgent() async throws {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.othersAgent)
        let read = deferFulfillment(viewModel.context.$viewState) { $0.agentOwnership == .someoneElses && $0.memberDetails != nil && $0.verificationState != nil }
        try await read.fulfill()
        
        #expect(viewModel.context.viewState.showVerifyIdentitySection)
        #expect(viewModel.context.viewState.showBlockUserSection)
        #expect(viewModel.context.viewState.showEraseAssistantMemorySection)
    }
    
    /// Own agent on a warm store: no Verify or Block ever, not even for a frame.
    @Test
    func theMemberPageHasItsShapeAtInit() async {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.member(Self.assistant), storeHoldsSpaces: true)
        let state = viewModel.context.viewState
        
        #expect(state.memberDetails == nil, "the member is still on its way")
        #expect(state.agentProfile?.ownCard == Self.assistant)
        #expect(!state.showBlockUserSection)
        #expect(!state.showVerifyIdentitySection)
        #expect(!state.showEraseAssistantMemorySection)
    }
    
    /// Someone else's agent has its erase and Block places from the start.
    @Test
    func theMemberPageShowsSomeoneElsesRowsAtInit() async {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.othersAgent, storeHoldsSpaces: true)
        
        #expect(viewModel.context.viewState.showBlockUserSection)
        #expect(viewModel.context.viewState.showEraseAssistantMemorySection)
    }
    
    /// The member and the identity have answered, whose it is hasn't: nothing shows that the answer may take back.
    @Test
    func theMemberPageOffersNothingWhileReading() async throws {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.member(Self.assistant), spacesRead: .hangs)
        let loaded = deferFulfillment(viewModel.context.$viewState) { $0.memberDetails != nil && $0.verificationState != nil }
        try await loaded.fulfill()
        
        let state = viewModel.context.viewState
        #expect(state.agentProfile?.isReadingOwnership == true)
        #expect(!state.showVerifyIdentitySection)
        #expect(!state.showBlockUserSection)
        #expect(!state.showEraseAssistantMemorySection)
    }
    
    /// After a failed read: today's page. Verify and Block stay, and the erase, which needs an answer, doesn't show.
    @Test
    func theMemberPageIsTheSafePageAfterAFailedRead() async throws {
        let viewModel = await makeMemberDetails(member: AgentProfileMock.member(Self.assistant), spacesRead: .fails)
        let loaded = deferFulfillment(viewModel.context.$viewState) {
            $0.memberDetails != nil && $0.verificationState != nil && $0.agentOwnership == .unknown(isReading: false)
        }
        try await loaded.fulfill()
        
        let state = viewModel.context.viewState
        #expect(state.agentProfile?.ownCard == nil)
        #expect(state.showVerifyIdentitySection)
        #expect(state.showBlockUserSection)
        #expect(!state.showEraseAssistantMemorySection)
    }
    
    @Test
    func theUserProfileHasItsShapeAtInit() async {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        AgentProfileMock.configure(userSession)
        await userSession.agentsStore?.reread(.spaces)
        let viewModel = UserProfileScreenViewModel(userID: Self.salesAgent.matrixUserID,
                                                   isPresentedModally: false,
                                                   userSession: userSession,
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: UserIndicatorControllerMock())
        
        #expect(viewModel.context.viewState.userProfile == nil, "the profile is still on its way")
        #expect(viewModel.context.viewState.agentProfile?.ownCard == Self.salesAgent)
        #expect(!viewModel.context.viewState.showEraseAssistantMemorySection)
    }
    
    @Test
    func theUserProfileOpensTheOwnAgentsRows() async throws {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        AgentProfileMock.configure(userSession)
        let viewModel = UserProfileScreenViewModel(userID: Self.salesAgent.matrixUserID,
                                                   isPresentedModally: false,
                                                   userSession: userSession,
                                                   analytics: AnalyticsServiceMock(.init()),
                                                   userIndicatorController: UserIndicatorControllerMock())
        let found = deferFulfillment(viewModel.context.observe(\.viewState.agentProfile?.ownCard)) { $0 == Self.salesAgent }
        try await found.fulfill()
        
        let opened = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openAgentRow(.usage, let card) = action { card == Self.salesAgent } else { false }
        }
        viewModel.context.send(viewAction: .openAgentRow(.usage))
        try await opened.fulfill()
    }
    
    // MARK: - Helpers
    
    private func makeRoomDetails(recipient: RoomMemberProxyMock, spacesRead: AgentProfileMock.SpacesRead = .answers,
                                 storeHoldsSpaces: Bool = false) async -> (RoomDetailsScreenViewModel, AgentPlatformServiceMock) {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        let service = AgentProfileMock.configure(userSession, spacesRead: spacesRead)
        if storeHoldsSpaces {
            await userSession.agentsStore?.reread(.spaces)
        }
        return (makeRoomDetails(recipient: recipient, userSession: userSession), service)
    }
    
    private func makeRoomDetails(recipient: RoomMemberProxyMock, userSession: UserSessionMock) -> RoomDetailsScreenViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(id: Self.roomID, name: recipient.displayName, isDirect: true, isEncrypted: false,
                                                  members: [.mockMe, recipient], heroes: [recipient]))
        return RoomDetailsScreenViewModel(roomProxy: roomProxy,
                                          userSession: userSession,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          notificationSettingsProxy: NotificationSettingsProxyMock(with: .init()),
                                          attributedStringBuilder: AttributedStringBuilder(mentionBuilder: MentionBuilder()))
    }
    
    private func makeMemberDetails(member: RoomMemberProxyMock, spacesRead: AgentProfileMock.SpacesRead = .answers,
                                   storeHoldsSpaces: Bool = false) async -> RoomMemberDetailsScreenViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: ""))
        roomProxy.getMemberUserIDClosure = { _ in .success(member) }
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success("roomID")
        clientProxy.userIdentityForFallBackToServerClosure = { _, _ in .success(UserIdentityProxyMock(.init(verificationState: .notVerified))) }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        AgentProfileMock.configure(userSession, spacesRead: spacesRead)
        if storeHoldsSpaces {
            await userSession.agentsStore?.reread(.spaces)
        }
        return RoomMemberDetailsScreenViewModel(userID: member.userID,
                                                roomProxy: roomProxy,
                                                userSession: userSession,
                                                analytics: AnalyticsServiceMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock())
    }
}

/// The rows open on the page's own stack, and every action of what they open has an answer.
@MainActor
struct AgentRowFlowCoordinatorTests {
    private static let card = AgentProfileMock.assistant
    
    @Test
    func eachRowIsPushedOverThePageAndFinishesOnPop() async throws {
        for row in [AgentPageRow.activity, .usage, .chats, .settings] {
            let fixture = try makeFixture(row: row)
            let flowCoordinator = fixture.flowCoordinator
            let navigationStackCoordinator = fixture.navigationStackCoordinator
            var actions: [AgentRowFlowCoordinatorAction] = []
            let cancellable = flowCoordinator.actionsPublisher.sink { actions.append($0) }
            defer { cancellable.cancel() }
            
            let pushed = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 2 }
            flowCoordinator.start(animated: false)
            try await pushed.fulfill()
            
            let top = navigationStackCoordinator.stackCoordinators.last
            switch row {
            case .activity: #expect(top is AgentActivityScreenCoordinator)
            case .usage: #expect(top is AgentUsageScreenCoordinator)
            case .chats: #expect(top is AgentChatsScreenCoordinator)
            case .settings: #expect(top is AgentDetailScreenCoordinator)
            }
            
            let finished = deferFulfillment(flowCoordinator.actionsPublisher) { if case .finished = $0 { true } else { false } }
            navigationStackCoordinator.pop(animated: false)
            try await finished.fulfill()
        }
    }
    
    @Test
    func clearingTheRouteGoesBackToThePageOnly() async throws {
        let fixture = try makeFixture(row: .usage)
        let flowCoordinator = fixture.flowCoordinator
        let navigationStackCoordinator = fixture.navigationStackCoordinator
        let pushed = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 2 }
        flowCoordinator.start(animated: false)
        try await pushed.fulfill()
        
        let cleared = deferFulfillment(navigationStackCoordinator.observe(\.stackCoordinators.count)) { $0 == 1 }
        flowCoordinator.clearRoute(animated: false)
        try await cleared.fulfill()
        #expect(navigationStackCoordinator.stackCoordinators.last is BlankFormCoordinator)
    }
    
    @Test
    func whatTheFlowSendsReachesTheParent() throws {
        let flowCoordinator = try makeFixture(row: .activity).flowCoordinator
        var actions: [AgentRowFlowCoordinatorAction] = []
        let cancellable = flowCoordinator.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }
        
        flowCoordinator.handle(.presentCallScreen(roomProxy: JoinedRoomProxyMock(.init(id: "1")), isVoiceCall: true))
        flowCoordinator.handle(.presentAIConsentSettings)
        flowCoordinator.handle(.verifyUser(userID: "@alice:spiral.md"))
        flowCoordinator.handle(.finished)
        
        #expect(actions.count == 4)
    }
    
    /// A chat the agent left: the page's count reads the spaces again.
    @Test
    func aChangeReadsTheSpacesAgain() async throws {
        let fixture = try makeFixture(row: .chats)
        let before = fixture.service.listMyAgentSpacesCallsCount
        
        fixture.flowCoordinator.handle(.changed)
        
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.service.listMyAgentSpacesCallsCount > before)
    }
    
    @Test
    func noPlatformHasNoFlow() {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init())))
        #expect(AgentRowFlowCoordinator(row: .usage, card: Self.card,
                                        navigationStackCoordinator: NavigationStackCoordinator(),
                                        flowParameters: Self.flowParameters(userSession)) == nil)
    }
    
    private struct Fixture {
        let flowCoordinator: AgentRowFlowCoordinator
        let navigationStackCoordinator: NavigationStackCoordinator
        let service: AgentPlatformServiceMock
    }
    
    private func makeFixture(row: AgentPageRow) throws -> Fixture {
        let navigationStackCoordinator = NavigationStackCoordinator()
        navigationStackCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: false))
        navigationStackCoordinator.push(BlankFormCoordinator())
        
        let clientProxy = ClientProxyMock(.init(userID: "@owner:spiral.md"))
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        let service = AgentProfileMock.configure(userSession)
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 503))
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 503))
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .failure(.serverError(status: 503))
        // The agent's own screen, for Settings (question 391).
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 503))
        service.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 503))
        
        let flowCoordinator = try #require(AgentRowFlowCoordinator(row: row,
                                                                   card: Self.card,
                                                                   navigationStackCoordinator: navigationStackCoordinator,
                                                                   flowParameters: Self.flowParameters(userSession)))
        return Fixture(flowCoordinator: flowCoordinator, navigationStackCoordinator: navigationStackCoordinator, service: service)
    }
    
    private static func flowParameters(_ userSession: UserSessionMock) -> CommonFlowParameters {
        CommonFlowParameters(userSession: userSession,
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
    }
}

/// The agent's chats on a screen of their own.
@MainActor
struct AgentChatsScreenViewModelTests {
    private let service = AgentPlatformServiceMock()
    private static let rooms = [AgentRoomEntry(roomID: "!a:spiral.md", displayName: "Alice", kind: "dm", activeTools: [])]
    
    init() {
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: "agent-1", matrixUserID: AgentProfileMock.assistant.matrixUserID, displayName: "Anna",
                                                                       avatarMXC: nil, kind: "personal_assistant", visibility: "private", lifecycleState: "active",
                                                                       organizationID: "org-1", roomCount: 1, activeToolCount: 0, configVersionNumber: 1, persona: nil))
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
    }
    
    @Test
    func theChatsComeFromTheStoreAndARowOpensItsChat() async throws {
        let viewModel = makeViewModel()
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.rooms) }
        try await loaded.fulfill()
        
        let selected = deferFulfillment(viewModel.actionsPublisher) { if case .selectRoom(Self.rooms[0]) = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectRoom(Self.rooms[0]))
        try await selected.fulfill()
    }
    
    /// Brief 0083, question 359: the card's count is how many rows hold the place during the read.
    @Test
    func thePlaceholdersFollowTheCardsCount() {
        let viewModel = makeViewModel()
        #expect(viewModel.context.viewState.loadState == .loading)
        #expect(viewModel.context.viewState.expectedRoomCount == AgentProfileMock.assistant.roomCount)
    }
    
    @Test
    func aFailedReadSaysSoAndRetries() async throws {
        service.fetchAgentRoomsAgentIDReturnValue = .failure(.serverError(status: 503))
        let viewModel = makeViewModel()
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .failure }
        try await failed.fulfill()
        
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.rooms) }
        viewModel.context.send(viewAction: .retry)
        try await loaded.fulfill()
    }
    
    @Test
    func anAgentDeletedElsewhereClosesTheScreen() async throws {
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.notFound)
        let viewModel = makeViewModel()
        let gone = deferFulfillment(viewModel.actionsPublisher) { if case .gone = $0 { true } else { false } }
        try await gone.fulfill()
    }
    
    private func makeViewModel() -> AgentChatsScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success(nil)
        return AgentChatsScreenViewModel(agent: AgentProfileMock.assistant, clientProxy: clientProxy, store: AgentsStore(service: service, retryDelays: []))
    }
}
