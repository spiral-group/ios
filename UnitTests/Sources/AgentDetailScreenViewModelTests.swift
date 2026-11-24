//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Brief 0037 — agent-detail screen (artboard 0037-D).
//

import AgentPlatformClient
import Combine
import Foundation
import MatrixRustSDKMocks
@testable import Spiral
import Testing

@MainActor
struct AgentDetailScreenViewModelTests {
    private static let card = AgentSpaceAgentCard(agentID: "agent-1",
                                                  matrixUserID: "@assistant-owner:spiral.md",
                                                  displayName: "Personal Assistant",
                                                  avatarMXC: nil,
                                                  kind: "personal_assistant",
                                                  visibility: "public",
                                                  lifecycleState: "active",
                                                  roomCount: 2,
                                                  activeToolCount: 1)
    
    private static let readModel = AgentReadModel(agentID: "agent-1",
                                                  matrixUserID: card.matrixUserID,
                                                  displayName: "Fresh Name",
                                                  avatarMXC: "mxc://host/avatar",
                                                  kind: card.kind,
                                                  visibility: card.visibility,
                                                  lifecycleState: card.lifecycleState,
                                                  organizationID: "org-personal",
                                                  roomCount: 3,
                                                  activeToolCount: 1,
                                                  configVersionNumber: 5,
                                                  persona: nil)
    
    private static let rooms: [AgentRoomEntry] = [
        .init(roomID: "!dm:host", displayName: "Alice", kind: "dm",
              activeTools: [.init(toolID: "t1", toolKind: "translate",
                                  targetLanguages: ["en"])])
    ]
    
    /// A company agent: the one kind of agent that is archived.
    private static let salesCard = AgentSpaceAgentCard(agentID: "agent-2",
                                                       matrixUserID: "@agent-sales:spiral.md",
                                                       displayName: "Sales",
                                                       avatarMXC: nil,
                                                       kind: "sales",
                                                       visibility: "public",
                                                       lifecycleState: "active",
                                                       roomCount: 0,
                                                       activeToolCount: 0)
    
    private func makeViewModel(service: AgentPlatformServiceMock,
                               store: AgentsStore? = nil,
                               card: AgentSpaceAgentCard = Self.card,
                               companyName: String? = nil,
                               clientProxy: ClientProxyMock = ClientProxyMock(.init())) -> AgentDetailScreenViewModel {
        if service.listBlockedContactsAgentIDCursorLimitReturnValue == nil, service.listBlockedContactsAgentIDCursorLimitClosure == nil {
            service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [], nextCursor: nil))
        }
        if service.fetchNotificationsActivityCursorLimitReturnValue == nil, service.fetchNotificationsActivityCursorLimitClosure == nil {
            service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: []))
        }
        return AgentDetailScreenViewModel(selection: .init(card: card, companyName: companyName),
                                          agentPlatformService: service,
                                          clientProxy: clientProxy,
                                          mediaProvider: MediaProviderMock(.init()),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          store: store ?? AgentsStore(service: service))
    }
    
    @Test
    func initialLoad_success_prefersFreshHeader() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            $0 == .loaded(Self.readModel, Self.rooms)
        }
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.displayName == "Fresh Name")
        #expect(service.fetchAgentReadModelAgentIDReceivedAgentID == "agent-1")
        #expect(service.fetchAgentRoomsAgentIDReceivedAgentID == "agent-1")
    }
    
    @Test
    func initialLoad_failure_showsFailureButKeepsCardHeader() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.forbidden)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 == .failure }
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.displayName == "Personal Assistant")
    }
    
    /// Review I7 L4: an agent deleted elsewhere closes its screen instead of a
    /// failure under its stale header.
    @Test
    func anAgentDeletedElsewhereClosesTheScreen() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 == .loaded(Self.readModel, Self.rooms) }
        try await loaded.fulfill()

        let gone = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .gone = action { true } else { false }
        }
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.notFound)
        store.apply([.agentUpdated(agentID: Self.card.agentID, spaceID: nil)])
        try await gone.fulfill()
    }

    /// The stream's change reads the agent again; a read that fails keeps what is shown.
    @Test
    func aFailedRereadKeepsTheShownDetail() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        let store = AgentsStore(service: service)
        
        let viewModel = makeViewModel(service: service, store: store)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            $0 == .loaded(Self.readModel, Self.rooms)
        }
        try await loaded.fulfill()
        
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.transport(underlying: URLError(.timedOut)))
        store.apply([.agentUpdated(agentID: Self.card.agentID, spaceID: nil)])
        await store.settle()
        
        #expect(service.fetchAgentReadModelAgentIDCallsCount == 2)
        #expect(viewModel.context.viewState.detailState == .loaded(Self.readModel, Self.rooms))
    }
    
    @Test
    func selectRoom_emitsAction() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        
        let viewModel = makeViewModel(service: service)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectRoom(let room) = action { return room.roomID == "!dm:host" }
            return false
        }
        viewModel.context.send(viewAction: .selectRoom(Self.rooms[0]))
        try await deferred.fulfill()
    }

    @Test
    func archiveTapped_asksForConfirmation() {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        
        let viewModel = makeViewModel(service: service, card: Self.salesCard)
        viewModel.context.send(viewAction: .archiveTapped)
        
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .confirmArchive)
        #expect(service.archiveAgentAgentIDCallsCount == 0)
    }
    
    @Test
    func confirmArchive_success_emitsArchived() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.archiveAgentAgentIDReturnValue = .success(())
        
        let viewModel = makeViewModel(service: service, card: Self.salesCard)
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .archived = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .confirmArchive)
        try await deferred.fulfill()
        
        #expect(service.archiveAgentAgentIDReceivedAgentID == "agent-2")
    }
    
    /// Decision 153: the personal assistant lives as long as the account.
    @Test
    func thePersonalAssistantIsNotArchived() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.archiveAgentAgentIDReturnValue = .success(())
        
        let viewModel = makeViewModel(service: service)
        #expect(!viewModel.context.viewState.canArchive)
        
        viewModel.context.send(viewAction: .archiveTapped)
        viewModel.context.send(viewAction: .confirmArchive)
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
        #expect(service.archiveAgentAgentIDCallsCount == 0)
    }
    
    /// A 409 means the server keeps the agent: said once, not offered as a retry.
    @Test
    func aRefusedArchiveSaysTheAgentStays() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.archiveAgentAgentIDReturnValue = .failure(.conflict(detail: "HTTP 409"))
        
        let viewModel = makeViewModel(service: service, card: Self.salesCard)
        let refused = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .archiveRefused }
        viewModel.context.send(viewAction: .confirmArchive)
        try await refused.fulfill()
        
        #expect(service.archiveAgentAgentIDCallsCount == 1)
    }
    
    // MARK: - B7: the owner DM reads as the owner's chat
    
    @Test
    func theOwnerDMIsTitledAsTheOwnersChat() async throws {
        let ownerDM = AgentRoomEntry(roomID: "!owner-dm:host", displayName: "Personal Assistant", kind: "dm", activeTools: [])
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success([ownerDM] + Self.rooms)
        let clientProxy = ClientProxyMock(.init())
        clientProxy.directRoomForUserIDReturnValue = .success("!owner-dm:host")
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await deferred.fulfill()
        
        #expect(clientProxy.directRoomForUserIDReceivedUserID == Self.card.matrixUserID)
        // The titles the loaded rows render.
        guard case .loaded(_, let rooms) = viewModel.context.viewState.detailState else {
            Issue.record("Expected loaded rooms")
            return
        }
        #expect(rooms.map { viewModel.context.viewState.title(for: $0) } == [UntranslatedL10n.screenAgentRoomOwnerDm, "Alice"])
    }
    
    @Test
    func withoutAKnownDMEveryRoomKeepsItsName() async throws {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        
        let viewModel = makeViewModel(service: service)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.ownerDMRoomID == nil)
        #expect(viewModel.context.viewState.title(for: Self.rooms[0]) == "Alice")
        #expect(AgentRoomEntry(roomID: "!x:host", displayName: nil, kind: "group", activeTools: []).title(ownerDMRoomID: nil, agentName: "A", deviceName: nil)
            == L10n.commonNoRoomName)
    }
    
    /// A visitor's DM with the assistant is titled by the visitor, never
    /// «<agent> and <person>» in English.
    @Test
    func aVisitorsDMIsTitledByTheVisitor() {
        let agent = "Анна Ковальчук's Assistant"
        let dm = { (name: String) in AgentRoomEntry(roomID: "!v:host", displayName: name, kind: "dm", activeTools: []) }
        #expect(dm("\(agent) and Максим Петров").title(ownerDMRoomID: nil, agentName: agent, deviceName: nil) == "Максим Петров")
        #expect(dm("Bob and \(agent)").title(ownerDMRoomID: nil, agentName: agent, deviceName: nil) == "Bob")
        // A group keeps the name it was given, «and» or not.
        let group = AgentRoomEntry(roomID: "!g:host", displayName: "\(agent) and Bob", kind: "group", activeTools: [])
        #expect(group.title(ownerDMRoomID: nil, agentName: agent, deviceName: nil) == "\(agent) and Bob")
    }
    
    /// A chat on this device reads as it does there; the backend's name is for a chat this device isn't in (357 item 5).
    @Test
    func aChatOnThisDeviceReadsAsItDoesThere() {
        let room = AgentRoomEntry(roomID: "!dm:host", displayName: "Anna's Assistant and Stage A", kind: "unknown", activeTools: [])
        #expect(room.title(ownerDMRoomID: nil, agentName: "Anna's Assistant", deviceName: "Stage A") == "Stage A")
        #expect(room.title(ownerDMRoomID: nil, agentName: "Anna's Assistant", deviceName: nil) == "Anna's Assistant and Stage A")
        #expect(room.title(ownerDMRoomID: "!dm:host", agentName: "Anna's Assistant", deviceName: "Anna's Assistant") == UntranslatedL10n.screenAgentRoomOwnerDm)
    }
    
    // MARK: - Step B
    
    @Test
    func theKindLineNamesTheRoleAndTheCompany() {
        let service = Self.loadedService()
        #expect(makeViewModel(service: service).context.viewState.kindLine == UntranslatedL10n.screenAgentDetailKindPersonalAssistant)
        let sales = makeViewModel(service: Self.loadedService(), card: Self.salesCard, companyName: "Coffee Bean")
        #expect(sales.context.viewState.kindLine == "\(UntranslatedL10n.screenCreateAgentRoleSales) · Coffee Bean")
    }
    
    @Test
    func messageAndAddToChatAreActions() async throws {
        let viewModel = makeViewModel(service: Self.loadedService())
        let message = deferFulfillment(viewModel.actionsPublisher) { if case .message = $0 { true } else { false } }
        viewModel.context.send(viewAction: .message)
        try await message.fulfill()
        
        let addToChat = deferFulfillment(viewModel.actionsPublisher) { if case .addToChat = $0 { true } else { false } }
        viewModel.context.send(viewAction: .addToChat)
        try await addToChat.fulfill()
    }
    
    /// «В чат» hands the picker the chats the agent is already in.
    @Test
    func addToChatCarriesTheAgentsChats() async throws {
        let viewModel = makeViewModel(service: Self.loadedService())
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        
        let addToChat = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .addToChat(let roomIDs) = action { roomIDs == ["!dm:host"] } else { false }
        }
        viewModel.context.send(viewAction: .addToChat)
        try await addToChat.fulfill()
    }
    
    /// The picker offers groups the owner is in, and nothing the agent can't
    /// usefully join.
    @Test
    func thePickerOffersOnlyChatsTheAgentCanJoin() {
        let agentID = Self.card.matrixUserID
        func offers(_ summary: RoomSummary, agentRoomIDs: Set<String> = []) -> Bool {
            summary.canTakeAgent(matrixUserID: agentID, agentRoomIDs: agentRoomIDs)
        }
        
        #expect(offers(Self.summary(id: "!group")))
        #expect(offers(Self.summary(id: "!bigDM", isDirect: true, activeMembersCount: 3)))
        
        #expect(!offers(Self.summary(id: "!space", isSpace: true)))
        #expect(!offers(Self.summary(id: "!dm", isDirect: true, activeMembersCount: 2)))
        #expect(!offers(Self.summary(id: "!in"), agentRoomIDs: ["!in"]))
        #expect(!offers(Self.summary(id: "!hero", heroes: [UserProfile(userID: agentID)])))
        #expect(!offers(Self.summary(id: "!invite", joinRequestType: .invite(inviter: nil))))
        #expect(!offers(Self.summary(id: "!old", isTombstoned: true)))
    }
    
    @Test
    func theChatPickerShowsOnlyWhatItsFilterKeeps() {
        let provider = RoomSummaryProviderMock(.init(state: .loaded([Self.summary(id: "!group"), Self.summary(id: "!space", isSpace: true)])))
        let picker = RoomSelectionScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                                  roomSummaryProvider: provider,
                                                  roomFilter: { $0.canTakeAgent(matrixUserID: Self.card.matrixUserID, agentRoomIDs: []) })
        #expect(picker.context.viewState.rooms.map(\.id) == ["!group"])
    }
    
    /// «В чат» with no chat the agent can join says why, not a blank list;
    /// a search that matches nothing stays blank.
    @Test
    func theChatPickerExplainsWhenNothingFits() {
        let provider = RoomSummaryProviderMock(.init(state: .loaded([Self.summary(id: "!dm", isDirect: true, activeMembersCount: 2)])))
        let emptyState = RoomSelectionScreenEmptyState(title: "None", message: "Why")
        let filter: (RoomSummary) -> Bool = { $0.canTakeAgent(matrixUserID: Self.card.matrixUserID, agentRoomIDs: []) }
        let picker = RoomSelectionScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                                  roomSummaryProvider: provider,
                                                  roomFilter: filter,
                                                  emptyState: emptyState)
        #expect(picker.context.viewState.rooms.isEmpty)
        #expect(picker.context.viewState.showsEmptyState)
        
        picker.context.searchQuery = "team"
        #expect(!picker.context.viewState.showsEmptyState)
    }
    
    private static func summary(id: String,
                                joinRequestType: RoomSummary.JoinRequestType? = nil,
                                isDirect: Bool = false,
                                isSpace: Bool = false,
                                heroes: [UserProfile] = [],
                                activeMembersCount: UInt = 5,
                                isTombstoned: Bool = false) -> RoomSummary {
        RoomSummary(room: RoomSDKMock(), id: id, joinRequestType: joinRequestType, isJoined: true, name: id, isDirect: isDirect, isSpace: isSpace,
                    avatarURL: nil, heroes: heroes, activeMembersCount: activeMembersCount, lastMessage: nil, lastMessageDate: nil,
                    lastMessageState: nil, unreadMessagesCount: 0, unreadMentionsCount: 0, unreadNotificationsCount: 0,
                    notificationMode: nil, canonicalAlias: nil, alternativeAliases: [], hasOngoingCall: false, activeCallIntent: nil,
                    isMarkedUnread: false, isFavourite: false, isTombstoned: isTombstoned)
    }
    
    /// «В чат»: the owner invites, the agent accepts (ADR-0017).
    @Test
    func addingToAChatInvitesThenAccepts() async throws {
        let service = Self.loadedService()
        service.joinRoomAgentIDRoomIDReturnValue = .success(())
        let roomProxy = JoinedRoomProxyMock(.init(id: "!team:host"))
        roomProxy.inviteUserIDReturnValue = .success(())
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        let added = deferFulfillment(viewModel.actionsPublisher) { if case .addedToChat = $0 { true } else { false } }
        await viewModel.addToChat(roomID: "!team:host")
        try await added.fulfill()
        
        #expect(roomProxy.inviteUserIDReceivedUserID == Self.card.matrixUserID)
        #expect(service.joinRoomAgentIDRoomIDReceivedArguments?.agentID == Self.card.agentID)
        #expect(service.joinRoomAgentIDRoomIDReceivedArguments?.roomID == "!team:host")
    }
    
    /// An invite that fails (already invited or in) still lets the accept
    /// decide; a failed accept says so instead of claiming success.
    @Test
    func aFailedAcceptSaysSo() async {
        let service = Self.loadedService()
        service.joinRoomAgentIDRoomIDReturnValue = .failure(.forbidden)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!team:host"))
        roomProxy.inviteUserIDReturnValue = .failure(.sdkError(ClientProxyMockError.generic))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }
        
        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        await viewModel.addToChat(roomID: "!team:host")
        
        #expect(service.joinRoomAgentIDRoomIDCallsCount == 1)
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .addToChatFailed)
        // The invite wasn't this attempt's, so it isn't taken back.
        #expect(!roomProxy.kickUserReasonCalled)
    }

    /// A failed accept after a sent invite takes the invite back, so the
    /// chat isn't left inviting an agent that never comes.
    @Test
    func aFailedAcceptWithdrawsTheInvite() async {
        let service = Self.loadedService()
        service.joinRoomAgentIDRoomIDReturnValue = .failure(.forbidden)
        let roomProxy = JoinedRoomProxyMock(.init(id: "!team:host"))
        roomProxy.inviteUserIDReturnValue = .success(())
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }

        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        await viewModel.addToChat(roomID: "!team:host")

        #expect(roomProxy.kickUserReasonReceivedArguments?.userID == Self.card.matrixUserID)
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .addToChatFailed)
    }

    /// A chat the agent is already in says so; nothing is sent.
    @Test
    func aChatTheAgentIsInSaysSo() async {
        let service = Self.loadedService()
        let agent = RoomMemberProxyMock(with: .init(userID: Self.card.matrixUserID, membership: .join))
        let roomProxy = JoinedRoomProxyMock(.init(id: "!team:host", members: [agent]))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomForIdentifierClosure = { _ in .joined(roomProxy) }

        let viewModel = makeViewModel(service: service, clientProxy: clientProxy)
        await viewModel.addToChat(roomID: "!team:host")

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .alreadyInChat)
        #expect(!roomProxy.inviteUserIDCalled)
        #expect(!service.joinRoomAgentIDRoomIDCalled)
    }
    
    /// Decision 194: the switch and the badge follow the read-model's pause,
    /// over a card that was read before it.
    @Test
    func thePauseFollowsTheReadModel() async throws {
        let viewModel = makeViewModel(service: Self.loadedService(paused: true))
        #expect(viewModel.context.viewState.paused == false)
        #expect(!viewModel.context.viewState.isPaused)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.paused == true)
        #expect(viewModel.context.viewState.isPaused)
    }
    
    // MARK: - The shape comes from the card (Brief 0083, question 359)
    
    /// The rows stand before the read, so nothing under them moves when it lands.
    @Test
    func theAssistantsRowsComeFromTheCard() {
        let (service, _) = Self.heldService()
        let state = makeViewModel(service: service).context.viewState
        #expect(state.detailState == .loading)
        #expect(state.showsPeopleSettings)
        #expect(state.showsCallsSettings)
        #expect(state.showInSearch == nil)
        #expect(!state.canArchive)
        #expect(!state.showsQueue)
    }
    
    @Test
    func aRoleAgentsRowsComeFromTheCard() {
        let (service, _) = Self.heldService()
        let state = makeViewModel(service: service, card: Self.salesCard).context.viewState
        #expect(state.detailState == .loading)
        #expect(!state.showsPeopleSettings)
        #expect(!state.showsCallsSettings)
        #expect(state.showInSearch == true)
        #expect(state.canArchive)
    }
    
    /// Question 396: the outreach queue is a company role's, hidden with the companies.
    @Test
    func anOutreachAgentHasNoQueueWhileCompaniesAreHidden() {
        let (service, _) = Self.heldService()
        let outreachCard = AgentSpaceAgentCard(agentID: "agent-3", matrixUserID: "@agent-outreach:spiral.md", displayName: "Outreach",
                                               avatarMXC: nil, kind: "outreach", visibility: "public", lifecycleState: "active",
                                               roomCount: 0, activeToolCount: 0)
        let state = makeViewModel(service: service, card: outreachCard).context.viewState
        #expect(!state.showsQueue)
    }
    
    /// A switch shows the card's value at once, and a tap before the read writes nothing.
    @Test
    func aSwitchWritesOnlyOverARead() async throws {
        let (service, release) = Self.heldService()
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel)
        var pausedCard = Self.salesCard
        pausedCard.isPaused = true
        let viewModel = makeViewModel(service: service, card: pausedCard)
        #expect(viewModel.context.viewState.paused)
        #expect(viewModel.context.viewState.showInSearch == true)
        #expect(!viewModel.context.viewState.canWriteSwitches)
        
        viewModel.context.send(viewAction: .setPaused(false))
        viewModel.context.send(viewAction: .setShowInSearch(false))
        try await Task.sleep(for: .milliseconds(20))
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        release()
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.canWriteSwitches)
        #expect(!service.editAgentAgentIDPatchCalled)
    }
    
    /// A failed read is not «no calls» and not a value to write over: the rows stay, the switches stay shut.
    @Test
    func aFailedReadKeepsTheRowsAndWritesNothing() async throws {
        let service = Self.loadedService()
        service.fetchAgentRoomsAgentIDReturnValue = .failure(.serverError(status: 503))
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel)
        let viewModel = makeViewModel(service: service, store: AgentsStore(service: service, retryDelays: []))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 == .failure }
        try await failed.fulfill()
        #expect(viewModel.context.viewState.showsCallsSettings)
        #expect(!viewModel.context.viewState.canWriteSwitches)
        
        viewModel.context.send(viewAction: .setPaused(true))
        try await Task.sleep(for: .milliseconds(20))
        #expect(!service.editAgentAgentIDPatchCalled)
    }
    
    /// A count's slot holds a placeholder while its read is on its way, and then its number.
    @Test
    func theCountsSlotsWaitForTheirReads() async throws {
        let viewModel = makeViewModel(service: Self.loadedService())
        #expect(viewModel.context.viewState.isReadingBlocked)
        #expect(viewModel.context.viewState.isReadingPendingApprovals)
        
        let blocked = deferFulfillment(viewModel.context.observe(\.viewState.isReadingBlocked)) { !$0 }
        try await blocked.fulfill()
        #expect(viewModel.context.viewState.blockedCount == .exactly(0))
        
        let pending = deferFulfillment(viewModel.context.observe(\.viewState.isReadingPendingApprovals)) { !$0 }
        try await pending.fulfill()
        #expect(viewModel.context.viewState.pendingApprovalsCount == 0)
    }
    
    /// A failed read of a count stops the placeholder and shows no number, never a made-up `0`.
    @Test
    func aFailedCountReadLeavesItsSlotEmpty() async throws {
        let service = Self.loadedService()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 500))
        service.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeViewModel(service: service, store: AgentsStore(service: service, retryDelays: []))
        
        let blocked = deferFulfillment(viewModel.context.observe(\.viewState.isReadingBlocked)) { !$0 }
        try await blocked.fulfill()
        #expect(viewModel.context.viewState.blockedCount == nil)
        
        let pending = deferFulfillment(viewModel.context.observe(\.viewState.isReadingPendingApprovals)) { !$0 }
        try await pending.fulfill()
        #expect(viewModel.context.viewState.pendingApprovalsCount == nil)
    }
    
    /// «Звонки» shows only for an assistant whose read-model has a call language.
    @Test
    func theCallsRowNeedsACallLanguage() async throws {
        var withVoice = Self.readModel
        withVoice.voiceLanguage = .uk
        let service = Self.loadedService()
        service.fetchAgentReadModelAgentIDReturnValue = .success(withVoice)
        let voiced = makeViewModel(service: service)
        let loaded = deferFulfillment(voiced.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        #expect(voiced.context.viewState.showsCallsSettings)
        
        let silent = makeViewModel(service: Self.loadedService())
        let silentLoaded = deferFulfillment(silent.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await silentLoaded.fulfill()
        #expect(!silent.context.viewState.showsCallsSettings)
    }
    
    /// A role agent's only people setting is «Показывать в поиске», so it
    /// is a switch on the agent screen; the assistant keeps its screen.
    @Test
    func aRoleAgentsSearchSwitchIsOnTheAgentScreen() async throws {
        let service = Self.loadedService()
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel)
        let viewModel = makeViewModel(service: service, card: Self.salesCard)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        #expect(!viewModel.context.viewState.showsPeopleSettings)
        #expect(viewModel.context.viewState.showInSearch == true)
        
        let changed = deferFulfillment(viewModel.actionsPublisher) { if case .changed = $0 { true } else { false } }
        viewModel.context.send(viewAction: .setShowInSearch(false))
        try await changed.fulfill()
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(visibility: "private"))
        
        let assistant = makeViewModel(service: Self.loadedService())
        let assistantLoaded = deferFulfillment(assistant.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await assistantLoaded.fulfill()
        #expect(assistant.context.viewState.showsPeopleSettings)
        #expect(assistant.context.viewState.showInSearch == nil)
    }
    
    @Test
    func pausingWritesOnlyThePause() async throws {
        let service = Self.loadedService(paused: false)
        service.editAgentAgentIDPatchReturnValue = .success(Self.readModel)
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        
        let changed = deferFulfillment(viewModel.actionsPublisher) { if case .changed = $0 { true } else { false } }
        viewModel.context.send(viewAction: .setPaused(true))
        try await changed.fulfill()
        
        #expect(service.editAgentAgentIDPatchReceivedArguments?.patch == AgentEditPatch(paused: true))
    }
    
    /// A 500 on a pause means it is stored but a call was not left: the same
    /// request goes once more, and a second failure is only a quiet toast.
    @Test
    func aFailedPauseIsSentOnceMore() async throws {
        let service = Self.loadedService(paused: false)
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        
        let done = deferFulfillment(viewModel.context.observe(\.viewState.isPausing)) { !$0 && service.editAgentAgentIDPatchCallsCount > 0 }
        viewModel.context.send(viewAction: .setPaused(true))
        try await done.fulfill()
        
        #expect(service.editAgentAgentIDPatchCallsCount == 2)
        #expect(service.editAgentAgentIDPatchReceivedInvocations.map(\.patch) == [AgentEditPatch(paused: true), AgentEditPatch(paused: true)])
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }
    
    /// A resume that fails is not sent again: nothing about it is half done.
    @Test
    func aFailedResumeIsNotRetried() async throws {
        let service = Self.loadedService(paused: true)
        service.editAgentAgentIDPatchReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        
        let done = deferFulfillment(viewModel.context.observe(\.viewState.isPausing)) { !$0 && service.editAgentAgentIDPatchCallsCount > 0 }
        viewModel.context.send(viewAction: .setPaused(false))
        try await done.fulfill()
        
        #expect(service.editAgentAgentIDPatchCallsCount == 1)
    }
    
    @Test
    func aPausedAgentIsShownAsPaused() {
        let paused = AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-sales:spiral.md", displayName: "Sales", avatarMXC: nil,
                                         kind: "sales", visibility: "public", lifecycleState: "suspended", roomCount: 0, activeToolCount: 0, isPaused: true)
        let service = Self.loadedService()
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 500))
        #expect(makeViewModel(service: service, card: paused).context.viewState.isPaused)
        #expect(!makeViewModel(service: service, card: Self.salesCard).context.viewState.isPaused)
    }
    
    /// «Заблокированные» counts this agent's own blocks from the first page.
    @Test
    func theBlockedCountIsTheAgentsOwn() async throws {
        let service = Self.loadedService()
        let block = AgentBlockedContact(contactMXID: "@bob:host", displayName: nil, blockedAt: .now)
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [block, block], nextCursor: "c1"))
        let viewModel = makeViewModel(service: service)
        let counted = deferFulfillment(viewModel.context.observe(\.viewState.blockedCount)) { $0 == .atLeast(2) }
        try await counted.fulfill()
        #expect(service.listBlockedContactsAgentIDCursorLimitReceivedArguments?.agentID == Self.card.agentID)
    }
    
    /// A failed count shows no number, and a later failure keeps the last one.
    @Test
    func aFailedCountIsNeverZero() async throws {
        let service = Self.loadedService()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeViewModel(service: service)
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.blockedCount == nil)
        
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [.init(contactMXID: "@bob:host", displayName: nil, blockedAt: .now)],
                                                                                  nextCursor: nil))
        await viewModel.reload()
        #expect(viewModel.context.viewState.blockedCount == .exactly(1))
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 500))
        await viewModel.reload()
        #expect(viewModel.context.viewState.blockedCount == .exactly(1))
    }
    
    @Test
    func thePendingCountIsThisAgentsApprovals() async throws {
        let service = Self.loadedService()
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: [
            .approval(.init(id: "a1", agentID: Self.card.agentID, draftBody: "x", targetRoomID: "!r:host", createdAt: .now)),
            .approval(.init(id: "a2", agentID: "someone-else", draftBody: "y", targetRoomID: "!r:host", createdAt: .now))
        ]))
        let viewModel = makeViewModel(service: service)
        let counted = deferFulfillment(viewModel.context.observe(\.viewState.pendingApprovalsCount)) { $0 == 1 }
        try await counted.fulfill()
    }
    
    /// «Контроль» shows both counts, «0» included, once they are known.
    @Test
    func theControlCountsShowZero() async throws {
        let service = Self.loadedService()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [], nextCursor: nil))
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        // The screen renders the store's answers on its next turn: wait for the screen, not the store.
        let counted = deferFulfillment(viewModel.context.observe(\.viewState.blockedCount)) { $0 != nil }
        try await counted.fulfill()
        let pending = deferFulfillment(viewModel.context.observe(\.viewState.pendingApprovalsCount)) { $0 != nil }
        try await pending.fulfill()
        #expect(viewModel.context.viewState.pendingApprovalsCount == 0)
        #expect(viewModel.context.viewState.blockedCount?.text == "0")
    }
    
    /// What waits could not be read: no count, not «0».
    @Test
    func aFailedReadOfWhatWaitsGivesNoPendingCount() async throws {
        let service = Self.loadedService()
        service.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 500))
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        // The store's reads end before the screen renders them (its next turn): wait for the screen.
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) { $0 != .loading }
        try await loaded.fulfill()
        await store.settle()
        #expect(store.needsAction == nil)
        #expect(viewModel.context.viewState.pendingApprovalsCount == nil)
    }
    
    /// The count follows `approval.changed` while the screen is shown.
    @Test
    func thePendingCountFollowsApprovalChanged() async throws {
        let service = Self.loadedService()
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        await store.settle()
        
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: [
            .approval(.init(id: "a1", agentID: Self.card.agentID, draftBody: "x", targetRoomID: "!r:host", createdAt: .now))
        ]))
        let counted = deferFulfillment(viewModel.context.observe(\.viewState.pendingApprovalsCount)) { $0 == 1 }
        store.apply([.approvalChanged(approvalID: "a1")])
        try await counted.fulfill()
    }
    
    /// The header follows the list's card: the agent paused on another device shows here too.
    @Test
    func theHeaderFollowsTheSpacesCard() async throws {
        let service = Self.loadedService()
        let space = AgentSpaceSummary(orgID: "org-personal", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)
        var pausedCard = Self.card
        pausedCard.isPaused = true
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [space], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: space.orgID, name: space.name, kind: .solo, avatarMXC: nil,
                                                                 industry: nil, website: nil, agents: [pausedCard]))
        let store = AgentsStore(service: service)
        let viewModel = makeViewModel(service: service, store: store)
        #expect(!viewModel.context.viewState.card.isPaused)
        
        let paused = deferFulfillment(viewModel.context.observe(\.viewState.card.isPaused)) { $0 }
        store.show(.spaces, by: service)
        try await paused.fulfill()
    }
    
    private static func snapshot(needsAction: [NeedsActionItem]) -> NotificationsSnapshot {
        NotificationsSnapshot(needsAction: needsAction, activity: [], nextActivityCursor: nil, lastSeenAt: nil, unseenCount: 0)
    }
    
    /// A service whose read of the agent stays on its way until `release` is called.
    private static func heldService() -> (service: AgentPlatformServiceMock, release: () -> Void) {
        let service = loadedService()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        service.fetchAgentRoomsAgentIDClosure = { _ in
            for await _ in gate { }
            return .success(Self.rooms)
        }
        return (service, { continuation.finish() })
    }
    
    private static func loadedService(paused: Bool = false) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        var readModel = Self.readModel
        readModel.paused = paused
        service.fetchAgentReadModelAgentIDReturnValue = .success(readModel)
        service.fetchAgentRoomsAgentIDReturnValue = .success(Self.rooms)
        return service
    }
}

/// Bug reports carry the logs: a view action names a room by its ID, never by its name, a person's in a DM.
struct AgentScreenViewActionLogTests {
    @Test
    func aSelectedRoomIsLoggedByItsIDOnly() {
        let dm = AgentRoomEntry(roomID: "!dm:host", displayName: "Olena Petrenko", kind: "dm", activeTools: [])

        #expect(String(describing: AgentDetailScreenViewAction.selectRoom(dm)) == "selectRoom(!dm:host)")
        #expect(String(describing: AgentChatsScreenViewAction.selectRoom(dm)) == "selectRoom(!dm:host)")
        #expect("\(AgentDetailScreenViewAction.openSettings(.people))" == "openSettings(people)")
    }
}
