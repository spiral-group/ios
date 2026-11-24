//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import MatrixRustSDKMocks
@testable import Spiral
import Testing

/// 1.0.3 A2 (ADR-0017): the person's own assistant's invite waits on top of Chats and is never declined; accepting it
/// stays the person's own tap.
@MainActor
struct AssistantInviteTests {
    private static let othersAssistantID = "@assistant-bob:spiral.md"

    // MARK: - Recognition

    @Test
    func onlyTheOwnPersonalAssistantsDirectInviteIsTheAssistants() {
        let own = AgentOwnership.own(AgentProfileMock.assistant)
        let assistantID = AgentProfileMock.assistant.matrixUserID

        #expect(AssistantInvite.recognise(inviterID: assistantID, isDirect: true) { _ in own } == .own)
        #expect(AssistantInvite.recognise(inviterID: assistantID, isDirect: false) { _ in own } == .none)
        #expect(AssistantInvite.recognise(inviterID: AgentProfileMock.salesAgent.matrixUserID, isDirect: true) { _ in .own(AgentProfileMock.salesAgent) } == .none)
        #expect(AssistantInvite.recognise(inviterID: Self.othersAssistantID, isDirect: true) { _ in .someoneElses } == .none)
        #expect(AssistantInvite.recognise(inviterID: "@bob:spiral.md", isDirect: true) { _ in own } == .none)
        #expect(AssistantInvite.recognise(inviterID: assistantID, isDirect: true) { _ in nil } == .none, "No agent platform, no assistant.")
    }

    @Test
    func anAssistantWhoseOwnerIsntKnownCantBeDeclined() {
        let invite = AssistantInvite.recognise(inviterID: Self.othersAssistantID, isDirect: true) { _ in .unknown(isReading: false) }

        #expect(invite == .unconfirmed(isReading: false))
        #expect(!invite.allowsDecline)
        #expect(!AssistantInvite.own.allowsDecline)
        #expect(AssistantInvite.none.allowsDecline)
    }

    // MARK: - Chats

    @Test
    func theOwnAssistantsInviteIsPinnedOnTop() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID)

        try await deferFulfillment(viewModel.context.$viewState) { $0.rooms.first?.assistantInvite == .own }.fulfill()

        #expect(viewModel.context.viewState.rooms.first?.id == "!assistant-dm")
        #expect(viewModel.context.viewState.rooms.filter { $0.assistantInvite == .own }.count == 1)
    }

    @Test
    func theOwnAssistantsInviteIsNeverDeclinedFromChats() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID)
        try await deferFulfillment(viewModel.context.$viewState) { $0.rooms.first?.assistantInvite == .own }.fulfill()

        let noAlert = deferFailure(viewModel.context.$viewState, timeout: .seconds(1)) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await noAlert.fulfill()
    }

    @Test
    func someoneElsesAssistantIsAnOrdinaryInvite() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: Self.othersAssistantID)
        try await deferFulfillment(viewModel.context.$viewState) { state in
            state.rooms.contains { $0.id == "!assistant-dm" && $0.assistantInvite == .none }
        }.fulfill()

        #expect(viewModel.context.viewState.rooms.first?.id != "!assistant-dm")

        let alert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await alert.fulfill()
    }

    @Test
    func aPersonsInviteIsAnOrdinaryInvite() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: "@bob:spiral.md")
        try await deferFulfillment(viewModel.context.$viewState) { state in
            state.rooms.contains { $0.id == "!assistant-dm" }
        }.fulfill()
        
        let invite = try #require(viewModel.context.viewState.rooms.first { $0.id == "!assistant-dm" })
        #expect(invite.assistantInvite == .none)
        #expect(invite.assistantInvite.allowsDecline)
        #expect(viewModel.context.viewState.rooms.first?.id != "!assistant-dm", "Not pinned.")
        
        let alert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await alert.fulfill()
    }
    
    @Test
    func anAssistantsInviteOffersNoDeclineWhileItsOwnerIsRead() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID, spacesRead: .hangs)
        try await deferFulfillment(viewModel.context.$viewState) { state in
            state.rooms.contains { $0.id == "!assistant-dm" && $0.assistantInvite == .unconfirmed(isReading: true) }
        }.fulfill()

        let noAlert = deferFailure(viewModel.context.$viewState, timeout: .seconds(1)) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await noAlert.fulfill()
    }

    /// Fable M2: spaces read before the new account's assistant existed answer «not yours» for it too. That answer is
    /// read again before it counts, with no Decline meanwhile.
    @Test
    func aNewAccountsOwnAssistantIsntTakenForSomeoneElses() async throws {
        let userSession = UserSessionMock(.init(userSettings: UserSettings.mock()))
        let service = AgentProfileMock.configure(userSession)
        let store = try #require(userSession.agentsStore)
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .idle))
        await store.reread(.spaces)
        #expect(store.ownership(matrixUserID: AgentProfileMock.assistant.matrixUserID) == .someoneElses)
        service.listMyAgentSpacesReturnValue = AgentProfileMock.spaces
        
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID, userSession: userSession)
        let invite = viewModel.context.viewState.rooms.first { $0.id == "!assistant-dm" }?.assistantInvite
        #expect(invite == .unconfirmed(isReading: true))
        #expect(invite?.allowsDecline == false)
        
        try await deferFulfillment(viewModel.context.$viewState) { $0.rooms.first?.assistantInvite == .own }.fulfill()
    }
    
    /// Fable M1 (b): an owner that can't be told hides Decline within the bound, a read on its way or not.
    @Test
    func anOwnerThatCantBeToldHidesDeclineWithinTheBound() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        let store = AgentsStore(service: service, retryDelays: [])
        let watch = AssistantInviteSpacesWatch(store: store, unconfirmedLimit: .seconds(30)) { }
        
        #expect(watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .unconfirmed(isReading: true))
        try await Self.waitUntil { watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .unconfirmed(isReading: false) }
        #expect(!watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true).allowsDecline)
    }
    
    /// Fable review of the 1.0.3 DEBT lane, M1: past the bound with no answer (a platform that keeps failing, another
    /// server's assistant) Decline comes back, behind a warning that the person's own assistant's chat is lost with it.
    @Test
    func anOwnerThatCantBeToldOffersAWarnedDeclinePastTheBound() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        let store = AgentsStore(service: service, retryDelays: [])
        var changes = 0
        let watch = AssistantInviteSpacesWatch(store: store, unconfirmedLimit: .milliseconds(300)) { changes += 1 }
        
        #expect(!watch.invite(inviterID: Self.othersAssistantID, isDirect: true).allowsDecline)
        try await Self.waitUntil { watch.invite(inviterID: Self.othersAssistantID, isDirect: true) == .undetermined }
        let invite = watch.invite(inviterID: Self.othersAssistantID, isDirect: true)
        #expect(invite.allowsDecline)
        #expect(invite.declineNeedsWarning)
        #expect(!AssistantInvite.none.declineNeedsWarning)
        #expect(changes > 0, "The bound re-renders the screen holding the invite.")
    }
    
    /// Fable follow-up M-B: a read on its way at the bound, or any later read, no longer hides the warned Decline, so the
    /// join screen's wait can't stick on its spinner when the read ends without a change.
    @Test
    func aReadOnItsWayPastTheBoundStillOffersTheWarnedDecline() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesClosure = {
            try? await Task.sleep(for: .seconds(3600))
            return .failure(.serverError(status: 503))
        }
        let store = AgentsStore(service: service, retryDelays: [])
        let watch = AssistantInviteSpacesWatch(store: store, unconfirmedLimit: .milliseconds(100)) { }
        
        #expect(watch.invite(inviterID: Self.othersAssistantID, isDirect: true) == .unconfirmed(isReading: true))
        try await Task.sleep(for: .milliseconds(300))
        #expect(watch.invite(inviterID: Self.othersAssistantID, isDirect: true) == .undetermined)
    }
    
    /// A real answer past the bound wins: the person's own assistant never gets Decline back.
    @Test
    func anOwnAnswerPastTheBoundTakesDeclineAway() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        let store = AgentsStore(service: service, retryDelays: [])
        let watch = AssistantInviteSpacesWatch(store: store, unconfirmedLimit: .milliseconds(100)) { }
        try await Self.waitUntil { watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .undetermined }
        
        service.listMyAgentSpacesReturnValue = AgentProfileMock.spaces
        service.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                 industry: nil, website: nil, agents: [AgentProfileMock.assistant]))
        watch.refreshIfUnconfirmed()
        
        try await Self.waitUntil { watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .own }
        #expect(!watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true).allowsDecline)
    }
    
    @Test
    func chatsWarnsBeforeDecliningAnAssistantWhoseOwnerCantBeTold() async throws {
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID, spacesRead: .fails, unconfirmedLimit: .milliseconds(200))
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { state in
            state.rooms.contains { $0.id == "!assistant-dm" && $0.assistantInvite == .undetermined }
        }.fulfill()
        
        let alert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await alert.fulfill()
        #expect(viewModel.context.alertInfo?.message?.contains(UntranslatedL10n.screenInvitesAssistantDeclineWarningSpiral) == true)
    }
    
    /// Fable follow-up: a warned Decline already on screen must not decline once the answer says it's the person's own.
    @Test
    func aWarnedDeclineInChatsDoesNothingOnceTheAssistantIsKnownToBeOwn() async throws {
        let userSession = UserSessionMock(.init(userSettings: UserSettings.mock()))
        let service = AgentProfileMock.configure(userSession, spacesRead: .fails)
        let viewModel = makeHomeScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID,
                                                userSession: userSession,
                                                unconfirmedLimit: .milliseconds(200))
        let clientProxy = try #require(userSession.clientProxy as? ClientProxyMock)
        let invitedRoom = InvitedRoomProxyMock(.init(id: "!assistant-dm"))
        clientProxy.roomForIdentifierClosure = { _ in .invited(invitedRoom) }
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { state in
            state.rooms.contains { $0.id == "!assistant-dm" && $0.assistantInvite == .undetermined }
        }.fulfill()
        let alertShown = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite(roomIdentifier: "!assistant-dm"))
        try await alertShown.fulfill()
        let alert = try #require(viewModel.context.alertInfo)
        var declinedAndBlocked = false
        let cancellable = viewModel.actions.sink { if case .presentDeclineAndBlock = $0 { declinedAndBlocked = true } }
        defer { cancellable.cancel() }
        
        try await answerThatTheAssistantIsOwn(service: service, store: #require(userSession.agentsStore))
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { $0.bindings.alertInfo == nil }.fulfill()
        
        // The person had already tapped: the stale alert's buttons decline nothing.
        alert.secondaryButton?.action?()
        alert.verticalButtons?.forEach { $0.action?() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!invitedRoom.rejectInvitationCalled)
        #expect(!declinedAndBlocked)
    }
    
    @Test
    func aWarnedDeclineOnTheJoinScreenDoesNothingOnceTheAssistantIsKnownToBeOwn() async throws {
        let clientProxy = ClientProxyMock(.init(userID: "@anna:spiral.md"))
        clientProxy.roomPreviewForIdentifierViaReturnValue = .success(RoomPreviewProxyMock.inviteDM(roomID: "!assistant-dm"))
        let inviter = RoomMemberProxyMock(with: .init(userID: AgentProfileMock.assistant.matrixUserID, displayName: "Anna · assistant", membership: .join))
        let invitedRoom = InvitedRoomProxyMock(.init(id: "!assistant-dm", inviter: inviter))
        clientProxy.roomForIdentifierClosure = { _ in .invited(invitedRoom) }
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded([])))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy, userSettings: UserSettings.mock()))
        let service = AgentProfileMock.configure(userSession, spacesRead: .fails)
        let viewModel = JoinRoomScreenViewModel(source: .generic(roomID: "!assistant-dm", via: []),
                                                userSession: userSession,
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                assistantInviteUnconfirmedLimit: .milliseconds(200))
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { $0.assistantInvite == .undetermined }.fulfill()
        let alertShown = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite)
        try await alertShown.fulfill()
        let alert = try #require(viewModel.context.alertInfo)
        
        try await answerThatTheAssistantIsOwn(service: service, store: #require(userSession.agentsStore))
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { $0.assistantInvite == .own }.fulfill()
        #expect(viewModel.context.alertInfo == nil, "The stale alert is taken down.")
        
        alert.secondaryButton?.action?()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!invitedRoom.rejectInvitationCalled)
    }
    
    @Test
    func theJoinScreenEndsItsWaitAtTheBoundAndWarnsBeforeDeclining() async throws {
        let (viewModel, _) = makeJoinRoomScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID, spacesRead: .hangs, unconfirmedLimit: .milliseconds(300))
        try await deferFulfillment(viewModel.context.$viewState) { $0.isReadingAssistantInvite }.fulfill()
        try await deferFulfillment(viewModel.context.$viewState, timeout: .seconds(5)) { $0.assistantInvite == .undetermined }.fulfill()
        #expect(!viewModel.context.viewState.isReadingAssistantInvite)
        
        let declineAlert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite)
        try await declineAlert.fulfill()
        #expect(viewModel.context.alertInfo?.message?.contains(UntranslatedL10n.screenInvitesAssistantDeclineWarningSpiral) == true)
        
        viewModel.context.alertInfo = nil
        let blockAlert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInviteAndBlock(userID: AgentProfileMock.assistant.matrixUserID))
        try await blockAlert.fulfill()
        #expect(viewModel.context.alertInfo?.message?.contains(UntranslatedL10n.screenInvitesAssistantDeclineWarningSpiral) == true)
    }
    
    /// Fable M1 (a): Chats or the join screen showing again asks once more about an owner that couldn't be told.
    @Test
    func showingAgainAsksAboutAnOwnerThatCouldntBeTold() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        let store = AgentsStore(service: service, retryDelays: [])
        let watch = AssistantInviteSpacesWatch(store: store) { }
        _ = watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true)
        try await Self.waitUntil { watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .unconfirmed(isReading: false) }
        let reads = service.listMyAgentSpacesCallsCount
        
        service.listMyAgentSpacesReturnValue = AgentProfileMock.spaces
        service.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                 industry: nil, website: nil, agents: [AgentProfileMock.assistant]))
        watch.refreshIfUnconfirmed()
        
        try await Self.waitUntil { service.listMyAgentSpacesCallsCount == reads + 1 }
        try await Self.waitUntil { watch.invite(inviterID: AgentProfileMock.assistant.matrixUserID, isDirect: true) == .own }
    }
    
    // MARK: - The assistant's chat before consent

    @Test
    func theOwnAssistantsInviteOpensItsOwnScreenWithoutDecline() async throws {
        let (viewModel, clientProxy) = makeJoinRoomScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID)
        try await deferFulfillment(viewModel.context.$viewState) { $0.showsAssistantInvite }.fulfill()

        let noAlert = deferFailure(viewModel.context.$viewState, timeout: .seconds(1)) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite)
        viewModel.context.send(viewAction: .declineInviteAndBlock(userID: AgentProfileMock.assistant.matrixUserID))
        try await noAlert.fulfill()

        // «Start conversation» is the person's own tap, and it joins.
        #expect(!clientProxy.joinRoomViaCalled && !clientProxy.joinRoomAliasCalled)
        let joined = deferFulfillment(viewModel.actionsPublisher) { $0 == .joined(.roomID("!assistant-dm")) }
        viewModel.context.send(viewAction: .acceptInvite)
        try await joined.fulfill()
        #expect(clientProxy.joinRoomViaCalled || clientProxy.joinRoomAliasCalled)
    }

    /// Fable L1: while it's told whose assistant asks, the join screen waits (a spinner) with nothing to decline.
    @Test
    func theJoinScreenWaitsWhileItsToldWhoseAssistantAsks() async throws {
        let (viewModel, _) = makeJoinRoomScreenViewModel(inviterID: AgentProfileMock.assistant.matrixUserID, spacesRead: .hangs)
        try await deferFulfillment(viewModel.context.$viewState) { $0.isReadingAssistantInvite }.fulfill()
        
        #expect(!viewModel.context.viewState.showsAssistantInvite)
        let noAlert = deferFailure(viewModel.context.$viewState, timeout: .seconds(1)) { $0.bindings.alertInfo != nil || !$0.isReadingAssistantInvite }
        viewModel.context.send(viewAction: .declineInvite)
        try await noAlert.fulfill()
    }
    
    @Test
    func someoneElsesAssistantKeepsElementsInvite() async throws {
        let (viewModel, _) = makeJoinRoomScreenViewModel(inviterID: Self.othersAssistantID)
        // While its owner is read the screen holds blank; then it's an ordinary invite.
        try await deferFulfillment(viewModel.context.$viewState) { $0.isReadingAssistantInvite }.fulfill()
        try await deferFulfillment(viewModel.context.$viewState) { $0.mode.isInvite && $0.assistantInvite == .none }.fulfill()

        #expect(!viewModel.context.viewState.showsAssistantInvite)
        let alert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite)
        try await alert.fulfill()
    }

    @Test
    func aPersonsInviteKeepsElementsInvite() async throws {
        let (viewModel, _) = makeJoinRoomScreenViewModel(inviterID: "@bob:spiral.md")
        try await deferFulfillment(viewModel.context.$viewState) { $0.mode.isInvite }.fulfill()
        
        #expect(viewModel.context.viewState.assistantInvite == .none)
        #expect(!viewModel.context.viewState.showsAssistantInvite)
        #expect(!viewModel.context.viewState.isReadingAssistantInvite)
        let alert = deferFulfillment(viewModel.context.$viewState) { $0.bindings.alertInfo != nil }
        viewModel.context.send(viewAction: .declineInvite)
        try await alert.fulfill()
    }
    
    // MARK: - Helpers
    
    /// The platform comes back and says the inviter is the person's own assistant.
    private func answerThatTheAssistantIsOwn(service: AgentPlatformServiceMock, store: AgentsStore) async throws {
        service.listMyAgentSpacesReturnValue = AgentProfileMock.spaces
        service.listMyAgentSpacesClosure = nil
        service.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                 industry: nil, website: nil, agents: [AgentProfileMock.assistant]))
        await store.reread(.spaces)
        guard case .own = store.ownership(matrixUserID: AgentProfileMock.assistant.matrixUserID) else {
            Issue.record("The reread didn't tell the assistant is the person's own")
            return
        }
    }
    
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    private func makeHomeScreenViewModel(inviterID: String,
                                         spacesRead: AgentProfileMock.SpacesRead = .answers,
                                         userSession: UserSessionMock? = nil,
                                         unconfirmedLimit: Duration = .seconds(30)) -> HomeScreenViewModel {
        let rooms: [RoomSummary] = .mockRooms + [Self.assistantInviteSummary(inviterID: inviterID)]
        let clientProxy = ClientProxyMock(.init(userID: "@anna:spiral.md", roomSummaryProvider: RoomSummaryProviderMock(.init(state: .loaded(rooms)))))
        clientProxy.roomForIdentifierClosure = { roomID in .invited(InvitedRoomProxyMock(.init(id: roomID))) }
        let userSession = userSession ?? {
            let userSession = UserSessionMock(.init(userSettings: UserSettings.mock()))
            AgentProfileMock.configure(userSession, spacesRead: spacesRead)
            return userSession
        }()
        userSession.clientProxy = clientProxy

        return HomeScreenViewModel(userSession: userSession,
                                   availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   userIndicatorController: UserIndicatorControllerMock(),
                                   assistantInviteUnconfirmedLimit: unconfirmedLimit)
    }

    private func makeJoinRoomScreenViewModel(inviterID: String,
                                             spacesRead: AgentProfileMock.SpacesRead = .answers,
                                             unconfirmedLimit: Duration = .seconds(30)) -> (JoinRoomScreenViewModel, ClientProxyMock) {
        let clientProxy = ClientProxyMock(.init(userID: "@anna:spiral.md"))
        clientProxy.roomPreviewForIdentifierViaReturnValue = .success(RoomPreviewProxyMock.inviteDM(roomID: "!assistant-dm"))
        let inviter = RoomMemberProxyMock(with: .init(userID: inviterID, displayName: "Anna · assistant", membership: .join))
        clientProxy.roomForIdentifierClosure = { _ in
            .invited(InvitedRoomProxyMock(.init(id: "!assistant-dm", inviter: inviter)))
        }
        clientProxy.joinRoomViaReturnValue = .success(())
        clientProxy.staticRoomSummaryProvider = RoomSummaryProviderMock(.init(state: .loaded([])))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy, userSettings: UserSettings.mock()))
        AgentProfileMock.configure(userSession, spacesRead: spacesRead)

        let viewModel = JoinRoomScreenViewModel(source: .generic(roomID: "!assistant-dm", via: []),
                                                userSession: userSession,
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                assistantInviteUnconfirmedLimit: unconfirmedLimit)
        return (viewModel, clientProxy)
    }

    private static func assistantInviteSummary(inviterID: String) -> RoomSummary {
        let inviter = RoomMemberProxyMock(with: .init(userID: inviterID, displayName: "Anna · assistant", membership: .join))
        return RoomSummary(room: RoomSDKMock(),
                           id: "!assistant-dm",
                           joinRequestType: .invite(inviter: inviter),
                           isJoined: false,
                           name: "Anna · assistant",
                           isDirect: true,
                           isSpace: false,
                           avatarURL: nil,
                           heroes: [.init(userID: inviterID)],
                           activeMembersCount: 1,
                           lastMessage: nil,
                           lastMessageDate: nil,
                           lastMessageState: nil,
                           unreadMessagesCount: 0,
                           unreadMentionsCount: 0,
                           unreadNotificationsCount: 0,
                           notificationMode: nil,
                           canonicalAlias: nil,
                           alternativeAliases: [],
                           hasOngoingCall: false,
                           activeCallIntent: nil,
                           isMarkedUnread: false,
                           isFavourite: false,
                           isTombstoned: false)
    }
}
