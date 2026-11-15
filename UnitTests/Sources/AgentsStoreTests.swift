//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: platform sync, the Agents tab (decision 289, contract § 5
// "Agents", § 7). The session's `AgentsStore`: each kind reads again what it
// names while it is shown, once however many changes come, and only when
// shown; `ready.fresh` and `limited` read again what is shown; a failed read
// keeps what was shown; a change shows on every screen holding the item; the
// badge follows `approval.changed`; the presence dot ages by itself.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentsStoreTests {
    private let service = AgentPlatformServiceMock()
    private let store: AgentsStore
    /// Stands for a screen that shows a resource.
    private let screen = Holder()

    init() {
        store = AgentsStore(service: service)
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDReturnValue = .success(Self.space(agents: [Self.card()]))
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(displayName: "Anna"))
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [], nextCursor: nil))
        service.fetchAgentUsageAgentIDReturnValue = .success(Self.usage)
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [], nextCursor: nil))
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: []))
        service.fetchUserProfileMxidReturnValue = .success(.init(mxid: "@alice:spiral.md", displayName: "Alice", publicAgents: []))
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: Self.roomID, agents: []))
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(Self.catalog)
        service.fetchAIConsentReturnValue = .success(Self.consent(isGranted: true))
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(Self.editSchema)
    }

    // MARK: - Each kind

    /// Each kind reads again the shown resource it names, and nothing else shown.
    @Test(arguments: [
        (AgentsSyncChange.agentUpdated(agentID: agentID, spaceID: spaceID), [AgentsResource.spaces, .agent(agentID: agentID)]),
        (.agentConfig(agentID: agentID), [.spaces, .agent(agentID: agentID)]),
        (.spaceUpdated(spaceID: spaceID), [.spaces]),
        (.agentRooms(agentID: agentID, roomID: roomID), [.spaces, .agent(agentID: agentID), .roomTools(roomID: roomID),
                                                         .toolsCatalog(agentID: agentID, roomID: roomID)]),
        (.agentTools(agentID: agentID, roomID: roomID), [.spaces, .agent(agentID: agentID), .roomTools(roomID: roomID)]),
        (.agentActivity(agentID: agentID), [.activity(agentID: agentID, filter: .all), .hubActivity]),
        (.agentActivity(agentID: nil), [.activity(agentID: agentID, filter: .all), .activity(agentID: otherAgentID, filter: .all), .hubActivity]),
        (.agentUsage(agentID: agentID), [.usage(agentID: agentID)]),
        (.agentUsage(agentID: nil), [.usage(agentID: agentID), .usage(agentID: otherAgentID)]),
        (.agentBlocks(agentID: agentID), [.blocks(agentID: agentID)]),
        (.agentOutreach(agentID: agentID), [.outreach(agentID: agentID, status: nil)]),
        (.approvalChanged(approvalID: "approval-1"), [.needsAction]),
        (.verificationChanged(verificationID: "verification-1", agentID: agentID), [.needsAction, .agent(agentID: agentID)]),
        (.notificationVisitor(messageID: "message-1"), [.needsAction]),
        (.notificationSeen, [.needsAction]),
        (.profilePublic(agentID: agentID), [.publicProfile(userID: "@alice:spiral.md")])
    ])
    func eachKindReadsAgainWhatItNames(change: AgentsSyncChange, named: [AgentsResource]) async {
        for resource in Self.everyResource {
            store.show(resource, by: screen)
        }
        await store.settle()
        let before = readCounts()

        store.apply([change])
        await store.settle()

        let after = readCounts()
        let reread = Set(Self.everyResource.filter { after[$0] != before[$0] })
        #expect(reread == Set(named))
    }

    /// A change of something nobody shows reads nothing; it is read when it shows.
    @Test
    func aChangeOffScreenIsReadWhenItShows() async {
        store.show(.usage(agentID: Self.agentID), by: screen)
        await store.settle()
        store.stopShowing(.usage(agentID: Self.agentID), by: screen)

        store.apply([.agentUsage(agentID: Self.agentID)])
        await store.settle()
        #expect(service.fetchAgentUsageAgentIDCallsCount == 1)
        #expect(store.isStale(.usage(agentID: Self.agentID)))

        store.show(.usage(agentID: Self.agentID), by: screen)
        await store.settle()
        #expect(service.fetchAgentUsageAgentIDCallsCount == 2)
    }

    /// One read on its way and three changes behind it: one more read, not three.
    @Test
    func changesDuringAReadAreReadOnceAfterIt() async {
        let gate = Gate()
        service.fetchAgentUsageAgentIDClosure = { _ in
            await gate.wait()
            return .success(Self.usage)
        }
        store.show(.usage(agentID: Self.agentID), by: screen)
        store.apply([.agentUsage(agentID: Self.agentID)])
        store.apply([.agentUsage(agentID: Self.agentID), .agentUsage(agentID: Self.agentID)])
        gate.open()
        await store.settle()

        #expect(service.fetchAgentUsageAgentIDCallsCount == 2)
    }

    /// A read that fails keeps what was shown; with nothing shown it says it failed, never "nothing".
    @Test
    func aFailedReadKeepsWhatIsShown() async {
        store.show(.usage(agentID: Self.agentID), by: screen)
        await store.settle()

        service.fetchAgentUsageAgentIDReturnValue = .failure(.serverError(status: 503))
        store.apply([.agentUsage(agentID: Self.agentID)])
        await store.settle()

        #expect(store.value(.usage(agentID: Self.agentID)) == .usage(Self.usage))
        guard case .loaded = store.readState(.usage(agentID: Self.agentID), { if case .usage(let usage) = $0 { usage } else { nil } }) else {
            Issue.record("The shown usage went")
            return
        }

        store.show(.usage(agentID: Self.otherAgentID), by: screen)
        await store.settle()
        guard case .failed = store.readState(.usage(agentID: Self.otherAgentID), { if case .usage(let usage) = $0 { usage } else { nil } }) else {
            Issue.record("A failed read with nothing shown must say it failed")
            return
        }
    }

    /// Review I7 L4: an agent deleted elsewhere is gone, not a read to retry:
    /// what was shown of it goes, and the screen hears `.notFound`.
    @Test
    func anAgentDeletedElsewhereIsGone() async throws {
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(10)])
        store.show(.agent(agentID: Self.agentID), by: screen)
        await store.settle()
        #expect(store.value(.agent(agentID: Self.agentID)) != nil)

        service.fetchAgentReadModelAgentIDReturnValue = .failure(.notFound)
        store.apply([.agentUpdated(agentID: Self.agentID, spaceID: nil)])
        await store.settle()
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.value(.agent(agentID: Self.agentID)) == nil)
        guard case .failed(.notFound) = store.readState(.agent(agentID: Self.agentID), \.agent) else {
            Issue.record("A deleted agent must say it is gone")
            return
        }
        #expect(service.fetchAgentReadModelAgentIDCallsCount == 2, "no retry of an answer")
    }

    // MARK: - Retries (review H1)

    /// A shown resource whose read fails is read again after each wait, then left for the next `ready` or foreground.
    @Test
    func aFailedReadIsRetriedAFewTimesThenWaits() async throws {
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(10), .milliseconds(10)])
        service.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 503))
        store.show(.needsAction, by: screen)
        for _ in 0..<100 where service.fetchNotificationsActivityCursorLimitCallsCount < 3 {
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(service.fetchNotificationsActivityCursorLimitCallsCount == 3)

        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: [Self.approval]))
        store.rereadStaleShown()
        await store.settle()
        #expect(store.needsAction?.count == 1)
    }

    /// Nobody shows it any more: no retry.
    @Test
    func theRetryStopsWhenNothingShowsIt() async throws {
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(30)])
        service.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 503))
        store.show(.needsAction, by: screen)
        await store.settle()
        store.stopShowing(.needsAction, by: screen)
        try await Task.sleep(for: .milliseconds(80))

        #expect(service.fetchNotificationsActivityCursorLimitCallsCount == 1)
        store.rereadStaleShown()
        await store.settle()
        #expect(service.fetchNotificationsActivityCursorLimitCallsCount == 1)
    }

    /// The hub's activity answer holds the whole needs-action set: one request serves the hub and the badge (review M1).
    @Test
    func theHubsActivityAnswerIsWhatWaitsToo() async {
        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: [Self.approval]))
        store.show(.hubActivity, by: screen)
        await store.settle()

        #expect(store.needsAction?.count == 1)
        #expect(service.fetchNotificationsActivityCursorLimitCallsCount == 1)
    }

    /// Follow-up review H1: a hub answer to a request made before what waits was read again
    /// (an approval decided meanwhile) must not write the decided approval back.
    @Test
    func anOlderHubAnswerDoesNotOverwriteWhatWaits() async throws {
        let gate = Gate()
        let server = Waiting(items: [Self.approval])
        service.fetchNotificationsActivityCursorLimitClosure = { _, limit in
            if limit > 1 {
                let answer = Self.snapshot(needsAction: server.items) // as the server had it when the request left
                await gate.wait()
                return .success(answer)
            }
            return .success(Self.snapshot(needsAction: server.items))
        }
        store.show(.needsAction, by: screen)
        await store.settle()
        #expect(store.needsAction?.count == 1)

        store.show(.hubActivity, by: screen)
        // The hub's request has left while the approval still waited.
        for _ in 0..<200 where !service.fetchNotificationsActivityCursorLimitReceivedInvocations.contains(where: { $0.limit > 1 }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        server.items = []
        store.apply([.approvalChanged(approvalID: "approval-1")])
        for _ in 0..<200 where store.needsAction?.isEmpty != true {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.needsAction?.isEmpty == true)

        gate.open()
        await store.settle()
        #expect(store.needsAction?.isEmpty == true)
        #expect(!store.isStale(.needsAction))
    }

    /// Follow-up review L3: a hub answer and a badge answer of the same moment are one value.
    @Test
    func aHubAnswerAndABadgeAnswerOfTheSameMomentAreOneValue() async {
        service.fetchNotificationsActivityCursorLimitClosure = { _, limit in
            .success(NotificationsSnapshot(needsAction: [Self.approval], activity: limit > 1 ? [Self.activityEntry(id: "row-1")] : [],
                                           nextActivityCursor: nil, lastSeenAt: nil, unseenCount: limit > 1 ? 1 : 0))
        }
        store.show(.hubActivity, by: screen)
        await store.settle()
        let fromHub = store.value(.needsAction)

        store.show(.needsAction, by: screen)
        await store.reread(.needsAction)
        #expect(store.value(.needsAction) == fromHub)
    }

    // MARK: - Fresh and limited

    /// `ready.fresh` / `limited` read again what is shown now, and the rest only when it shows.
    @Test
    func everythingStaleReadsAgainOnlyWhatIsShown() async {
        let other = Holder()
        store.show(.usage(agentID: Self.agentID), by: screen)
        store.show(.blocks(agentID: Self.agentID), by: other)
        await store.settle()
        store.stopShowing(.blocks(agentID: Self.agentID), by: other)

        store.markEverythingStale()
        #expect(store.syncStatus == nil) // idle: no capsule outside a stream
        await store.settle()

        #expect(service.fetchAgentUsageAgentIDCallsCount == 2)
        #expect(service.listBlockedContactsAgentIDCursorLimitCallsCount == 1)

        store.show(.blocks(agentID: Self.agentID), by: other)
        await store.settle()
        #expect(service.listBlockedContactsAgentIDCursorLimitCallsCount == 2)
    }

    /// The catch-up says "Updating…" at the top of a live stream until it is read.
    @Test
    func theCatchUpSaysUpdating() async {
        let gate = Gate()
        store.show(.usage(agentID: Self.agentID), by: screen)
        await store.settle()
        service.fetchAgentUsageAgentIDClosure = { _ in
            await gate.wait()
            return .success(Self.usage)
        }
        store.connectionState = .live

        store.markEverythingStale()
        #expect(store.syncStatus == .updating)
        gate.open()
        await store.settle()
        #expect(store.syncStatus == nil)
    }

    /// A list scrolled down is read again whole, up to the server's cap.
    @Test
    func aPagedListIsReadAgainAsLongAsItIs() async {
        let firstPage = (0..<25).map { Self.activityEntry(id: "row-\($0)") }
        let secondPage = (25..<40).map { Self.activityEntry(id: "row-\($0)") }
        service.listAgentActivityAgentIDFilterCursorLimitClosure = { _, _, cursor, limit in
            cursor == nil ? .success(.init(items: Array((firstPage + secondPage).prefix(limit)), nextCursor: limit < 40 ? "c" : nil))
                : .success(.init(items: secondPage, nextCursor: nil))
        }
        let resource = AgentsResource.activity(agentID: Self.agentID, filter: .all)
        store.show(resource, by: screen)
        await store.settle()
        await store.loadMore(resource)

        store.apply([.agentActivity(agentID: Self.agentID)])
        await store.settle()

        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.limit == 40)
        guard case .activity(let page)? = store.value(resource) else {
            Issue.record("No activity held")
            return
        }
        #expect(page.items.count == 40)
    }

    // MARK: - The badge

    /// `approval.changed` reads what waits again: the badge counts it.
    @Test
    func theBadgeFollowsApprovalChanged() async {
        store.show(.needsAction, by: screen)
        await store.settle()
        #expect(store.needsAction?.count == 0)

        service.fetchNotificationsActivityCursorLimitReturnValue = .success(Self.snapshot(needsAction: [Self.approval]))
        store.apply([.approvalChanged(approvalID: "approval-1")])
        await store.settle()

        #expect(store.needsAction?.count == 1)
        #expect(service.fetchNotificationsActivityCursorLimitReceivedArguments?.limit == 1)
    }

    /// Before a read what waits is unknown, not zero.
    @Test
    func whatWaitsIsUnknownBeforeARead() {
        #expect(store.needsAction == nil)
    }

    // MARK: - Every screen holding the item

    /// An agent changed elsewhere shows on the list and on the agent's own screen.
    @Test
    func aChangedAgentShowsOnEveryScreenHoldingIt() async throws {
        let list = AgentSpacesScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@owner:spiral.md")))),
                                              store: store)
        let detail = AgentDetailScreenViewModel(selection: .init(card: Self.card(), companyName: nil),
                                                agentPlatformService: service,
                                                clientProxy: ClientProxyMock(.init()),
                                                mediaProvider: MediaProviderMock(.init()),
                                                userIndicatorController: UserIndicatorControllerMock(),
                                                store: store)
        let read = deferFulfillment(detail.context.observe(\.viewState.displayName)) { $0 == "Anna" }
        try await read.fulfill()

        service.fetchAgentSpaceOrgIDReturnValue = .success(Self.space(agents: [Self.card(displayName: "Anna's helper", isPaused: true)]))
        service.fetchAgentReadModelAgentIDReturnValue = .success(Self.readModel(displayName: "Anna's helper", paused: true))
        // The screens render the store's answers on their next turn: wait for each screen.
        let listed = deferFulfillment(list.context.observe(\.viewState.listState)) { state in
            if case .loaded(let sections) = state { sections.first?.agents.first?.displayName == "Anna's helper" } else { false }
        }
        let detailed = deferFulfillment(detail.context.observe(\.viewState.isPaused)) { $0 }
        store.apply([.agentUpdated(agentID: Self.agentID, spaceID: Self.spaceID)])
        try await listed.fulfill()
        try await detailed.fulfill()

        #expect(list.context.viewState.sections.first?.agents.first?.displayName == "Anna's helper")
        #expect(list.context.viewState.sections.first?.agents.first?.isPaused == true)
        #expect(detail.context.viewState.displayName == "Anna's helper")
        #expect(detail.context.viewState.card.isPaused)
        #expect(detail.context.viewState.isPaused)
    }

    /// The room's tools are one read, however many screens show them.
    @Test
    func theRoomsToolsAreSharedByItsScreens() async throws {
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: Self.agentID, roomID: Self.roomID, paramsSchema: [:], triggerSchema: [:],
                                                                                      textTranslationLanguages: [], voiceTranslationLanguages: [],
                                                                                      availableToolKinds: ["summarize"]))
        let sheet = makeSheet()
        let otherSheet = makeSheet()
        let read = deferFulfillment(sheet.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        try await read.fulfill()
        await store.settle()
        #expect(service.fetchRoomToolsRoomIDCallsCount == 1)

        let tool = RoomToolView(toolID: "t1", toolKind: "summarize", triggerKind: "on_message", targetLanguage: nil,
                                params: .summarize, trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1", appliesToViewer: .yes)
        service.fetchRoomToolsRoomIDReturnValue = .success(.init(roomID: Self.roomID,
                                                                 agents: [.init(agentID: Self.agentID, matrixUserID: "@assistant:spiral.md",
                                                                                displayName: "Anna", ownerUserID: "@owner:spiral.md",
                                                                                isMine: true, tools: [tool])]))
        let hasTheTool: @Sendable (AgentSheetListState) -> Bool = { if case .loaded(let mine, _) = $0 { mine.count == 1 } else { false } }
        let sheetUpdated = deferFulfillment(sheet.context.observe(\.viewState.listState), until: hasTheTool)
        let otherUpdated = deferFulfillment(otherSheet.context.observe(\.viewState.listState), until: hasTheTool)
        store.apply([.agentTools(agentID: Self.agentID, roomID: Self.roomID)])
        try await sheetUpdated.fulfill()
        try await otherUpdated.fulfill()

        #expect(service.fetchRoomToolsRoomIDCallsCount == 2)
    }

    // MARK: - A space that could not be read

    /// One space's failed read keeps what was shown, and is a failed read: it is read again (357 item 8).
    /// Taken for a success, the row stayed as it was until a restart.
    @Test
    func aSpaceThatCouldNotBeReadIsReadAgain() async throws {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(Self.directory)
        var reads = 0
        service.fetchAgentSpaceOrgIDClosure = { _ in
            reads += 1
            return switch reads {
            case 1: .success(Self.space(agents: [Self.card(displayName: "Anna")]))
            case 2: .failure(.serverError(status: 429))
            default: .success(Self.space(agents: [Self.card(displayName: "Renamed")]))
            }
        }
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(10)])
        let owner = NSObject()
        store.show(.spaces, by: owner)
        await Self.settle(store)
        #expect(store.card(agentID: Self.agentID)?.displayName == "Anna")

        store.apply([.agentConfig(agentID: Self.agentID)])
        for _ in 0..<200 where store.card(agentID: Self.agentID)?.displayName != "Renamed" {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.card(agentID: Self.agentID)?.displayName == "Renamed")
        #expect(!store.isStale(.spaces))
        store.stopShowing(.spaces, by: owner)
    }

    // MARK: - Whose an agent is

    @Test
    func anAgentInASpaceIsTheOwners() async {
        store.show(.spaces, by: screen)
        await store.settle()

        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
    }

    @Test
    func anAgentInNoSpaceIsSomeoneElsesOnceEverySpaceAnswered() async {
        store.show(.spaces, by: screen)
        await store.settle()

        #expect(store.spaces?.isComplete == true)
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .someoneElses)
    }

    @Test
    func whoseItIsIsUnknownUntilTheFirstAnswer() async {
        let gate = Gate()
        service.listMyAgentSpacesClosure = {
            await gate.wait()
            return .success(Self.directory)
        }
        store.show(.spaces, by: screen)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .unknown(isReading: true))

        gate.open()
        await store.settle()
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
    }

    /// A failed read is no answer, and while a retry is on its way the answer may still come.
    @Test
    func aFailedDirectoryIsNotAnAnswerAndItsRetryIsReading() async throws {
        let retry = Gate()
        var reads = 0
        service.listMyAgentSpacesClosure = {
            reads += 1
            guard reads > 1 else { return .failure(.serverError(status: 503)) }
            await retry.wait()
            return .success(Self.directory)
        }
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(1)])
        store.show(.spaces, by: screen)
        for _ in 0..<200 where reads < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(reads == 2)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .unknown(isReading: true))
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .unknown(isReading: true))

        retry.open()
        await store.settle()
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .someoneElses)
        store.stopShowing(.spaces, by: screen)
    }

    /// A page opening while a retry is out offers nothing the answer could take back. It used to say it wasn't
    /// reading, so a person's own assistant showed Verify and Block, then flipped.
    @Test
    func aPageOpeningDuringARetrySaysItIsReading() async throws {
        let retry = Gate()
        var reads = 0
        service.listMyAgentSpacesClosure = {
            reads += 1
            guard reads > 1 else { return .failure(.serverError(status: 503)) }
            await retry.wait()
            return .success(Self.directory)
        }
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(1)])
        store.show(.spaces, by: screen)
        for _ in 0..<200 where reads < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }

        var answers: [AgentOwnership] = []
        let observation = AgentCardObservation(userID: "@assistant-anna:spiral.md", store: store) { answers.append($0) }

        #expect(answers == [.unknown(isReading: true)])
        observation?.cancel()
        retry.open()
        await store.settle()
        store.stopShowing(.spaces, by: screen)
    }

    /// Retry during the store's own retry: the read on its way answers for it, and the page says so at once. It used to
    /// keep the failure, so a tap on Retry did nothing to see.
    @Test
    func aRetryDuringARetryShowsItHasStarted() async throws {
        let retry = Gate()
        var reads = 0
        let resource = AgentsResource.roomTools(roomID: Self.roomID)
        service.fetchRoomToolsRoomIDClosure = { _ in
            reads += 1
            guard reads > 1 else { return .failure(.serverError(status: 503)) }
            await retry.wait()
            return .success(RoomToolsView(roomID: Self.roomID, agents: []))
        }
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(1)])
        store.show(resource, by: screen)
        for _ in 0..<200 where reads < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        guard case .failed = store.readState(resource, \.roomTools) else {
            Issue.record("The store's own retry leaves the failure up")
            return
        }

        store.refresh(resource)

        guard case .loading = store.readState(resource, \.roomTools) else {
            Issue.record("Retry changed nothing on the page")
            return
        }
        #expect(reads == 2, "the read on its way answers for it")
        retry.open()
        await store.settle()
        store.stopShowing(resource, by: screen)
    }

    /// A person's Retry, or a page opening, is a new start: that page says it is loading.
    @Test
    func aScreenAskingAgainSaysItIsLoading() async {
        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        store.show(.spaces, by: screen)
        await store.settle()
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .unknown(isReading: false))

        let gate = Gate()
        service.listMyAgentSpacesClosure = {
            await gate.wait()
            return .success(Self.directory)
        }
        store.refresh(.spaces)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .unknown(isReading: true))
        gate.open()
        await store.settle()
    }

    /// Question 396: with companies hidden, a company an older account still has is neither read nor listed, so its
    /// agents are nobody's the app knows of.
    @Test
    func aCompanySpaceIsNeitherReadNorListedWhileCompaniesAreHidden() async {
        let company = AgentSpaceSummary(orgID: Self.otherSpaceID, name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace, company], provisioningStatus: .ready))
        store.show(.spaces, by: screen)
        await store.settle()

        #expect(!SpiralFeatures.companySpaces)
        #expect(store.spaces?.directory.spaces == [Self.personalSpace])
        #expect(service.fetchAgentSpaceOrgIDReceivedInvocations == [Self.spaceID])
        #expect(store.spaces?.isComplete == true)
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .someoneElses)
    }

    @Test
    func theShownDirectoryKeepsEverySpaceButACompany() {
        let company = AgentSpaceSummary(orgID: Self.otherSpaceID, name: "Acme", kind: .company, avatarMXC: nil, agentCount: 1)
        let directory = AgentSpacesDirectory(spaces: [company, Self.personalSpace], provisioningStatus: .inProgress)

        #expect(directory.shown == AgentSpacesDirectory(spaces: [Self.personalSpace], provisioningStatus: .inProgress))
    }

    /// A space that wasn't read may hold the agent: never "not yours". What was read still answers.
    @Test
    func aSpaceNeverReadLeavesEveryOtherAgentUnknown() async {
        service.listMyAgentSpacesReturnValue = .success(Self.twoSpaces)
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            orgID == Self.spaceID ? .success(Self.space(agents: [Self.card()])) : .failure(.serverError(status: 503))
        }
        store.show(.spaces, by: screen)
        await store.settle()

        #expect(store.spaces?.isComplete == false)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .unknown(isReading: false))
    }

    /// The older copy a failed space keeps is shown, but it doesn't say an agent added since isn't the person's.
    @Test
    func aSpaceThatFailedAgainIsNotCompleteThoughItKeepsItsCopy() async {
        store.show(.spaces, by: screen)
        await store.settle()
        #expect(store.spaces?.isComplete == true)

        service.fetchAgentSpaceOrgIDClosure = { _ in .failure(.serverError(status: 503)) }
        store.apply([.spaceUpdated(spaceID: Self.spaceID)])
        await store.settle()

        #expect(store.spaces?.details[Self.spaceID] != nil)
        #expect(store.spaces?.isComplete == false)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .unknown(isReading: false))
    }

    /// The same for a directory read that failed after a complete one.
    @Test
    func aDirectoryThatFailedAfterACompleteReadAnswersOnlyForWhatItHeld() async {
        store.show(.spaces, by: screen)
        await store.settle()

        service.listMyAgentSpacesReturnValue = .failure(.serverError(status: 503))
        store.apply([.spaceUpdated(spaceID: Self.spaceID)])
        await store.settle()

        #expect(store.ownership(matrixUserID: Self.ownMXID) == .own(Self.card()))
        #expect(store.ownership(matrixUserID: Self.othersMXID) == .unknown(isReading: false))
    }

    /// While the assistant is set up it isn't listed yet, and it is the person's.
    @Test
    func anAssistantBeingSetUpIsNotSomeoneElses() async {
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: [Self.personalSpace], provisioningStatus: .inProgress))
        service.fetchAgentSpaceOrgIDReturnValue = .success(Self.space(agents: []))
        store.show(.spaces, by: screen)
        await store.settle()

        #expect(store.spaces?.isComplete == false)
        #expect(store.ownership(matrixUserID: Self.ownMXID) == .unknown(isReading: false))
    }

    // MARK: - The AI consent

    @Test
    func theConsentIsReadOnceAndKept() async {
        store.show(.aiConsent, by: screen)
        await store.settle()
        store.stopShowing(.aiConsent, by: screen)
        store.show(.aiConsent, by: screen)
        await store.settle()

        #expect(store.aiConsent == Self.consent(isGranted: true))
        #expect(service.fetchAIConsentCallsCount == 1)
    }

    /// A control writes only what was just read: `reread` waits for a read that left after it was asked, even with
    /// one on its way, and a failure shows beside the value it keeps.
    @Test
    func aFailedReadOfTheConsentKeepsTheValueAndSaysItFailed() async {
        store.show(.aiConsent, by: screen)
        await store.settle()

        service.fetchAIConsentReturnValue = .failure(.serverError(status: 503))
        await store.reread(.aiConsent)

        #expect(store.aiConsent == Self.consent(isGranted: true))
        #expect(store.failures[.aiConsent] != nil)

        service.fetchAIConsentReturnValue = .success(Self.consent(isGranted: false))
        await store.reread(.aiConsent)

        #expect(store.aiConsent == Self.consent(isGranted: false))
        #expect(store.failures[.aiConsent] == nil)
    }

    @Test
    func rereadWaitsForAReadAskedAfterTheOneOnItsWay() async {
        let gate = Gate()
        service.fetchAIConsentClosure = {
            await gate.wait()
            return .success(Self.consent(isGranted: true))
        }
        store.show(.aiConsent, by: screen)

        async let reread: Void = store.reread(.aiConsent)
        await Task.yield()
        gate.open()
        await reread

        #expect(service.fetchAIConsentCallsCount == 2)
    }

    @Test
    func aWriteShowsWithoutARead() async {
        service.setAIConsentGrantedReturnValue = .success(Self.consent(isGranted: true))

        let result = await store.setAIConsent(granted: true)

        #expect((try? result.get()) == Self.consent(isGranted: true))
        #expect(store.aiConsent == Self.consent(isGranted: true))
        #expect(service.setAIConsentGrantedReceivedInvocations == [true])
        #expect(!service.fetchAIConsentCalled)
    }

    /// The answer of a read that left before the write is older than it, also when it fails.
    @Test(arguments: [Result<AIConsent, AgentPlatformError>.success(consent(isGranted: true)), .failure(.serverError(status: 503))])
    func anOlderReadDoesNotOverwriteAWrite(answer: Result<AIConsent, AgentPlatformError>) async {
        service.setAIConsentGrantedReturnValue = .success(Self.consent(isGranted: false))
        let gate = Gate()
        service.fetchAIConsentClosure = {
            await gate.wait()
            return answer
        }
        store.show(.aiConsent, by: screen)

        _ = await store.setAIConsent(granted: false)
        gate.open()
        await store.settle()

        #expect(store.aiConsent == Self.consent(isGranted: false))
        #expect(store.failures[.aiConsent] == nil)
    }

    /// The write may have landed though its answer was lost: what is held is read again.
    @Test
    func aFailedWriteKeepsTheValueAndReadsItAgain() async {
        store.show(.aiConsent, by: screen)
        await store.settle()
        service.setAIConsentGrantedReturnValue = .failure(.serverError(status: 503))
        service.fetchAIConsentReturnValue = .success(Self.consent(isGranted: false))

        let result = await store.setAIConsent(granted: false)
        #expect(store.aiConsent == Self.consent(isGranted: true))
        await store.settle()

        guard case .failure = result else {
            Issue.record("A failed write must say so")
            return
        }
        #expect(store.aiConsent == Self.consent(isGranted: false))
    }

    /// A write that answered is what the server holds: a retry of a failed read has nothing left to do.
    @Test
    func aWriteEndsTheRetryOfAFailedRead() async throws {
        let store = AgentsStore(service: service, retryDelays: [.milliseconds(20)])
        service.fetchAIConsentReturnValue = .failure(.serverError(status: 503))
        service.setAIConsentGrantedReturnValue = .success(Self.consent(isGranted: true))
        store.show(.aiConsent, by: screen)
        await store.settle()

        _ = await store.setAIConsent(granted: true)
        try await Task.sleep(for: .milliseconds(60))

        #expect(service.fetchAIConsentCallsCount == 1)
        #expect(!store.isStale(.aiConsent))
        #expect(store.failures[.aiConsent] == nil)
        store.stopShowing(.aiConsent, by: screen)
    }

    // MARK: - The edit schema

    @Test
    func anEditSchemaIsReadOncePerAgent() async {
        let resource = AgentsResource.editSchema(agentID: Self.agentID)
        store.show(resource, by: screen)
        await store.settle()
        store.stopShowing(resource, by: screen)
        store.show(resource, by: screen)
        await store.settle()

        #expect(store.value(resource)?.editSchema == Self.editSchema)
        #expect(service.fetchAgentEditSchemaAgentIDReceivedInvocations == [Self.agentID])
    }

    @Test
    func aFailedEditSchemaSaysItFailed() async {
        let resource = AgentsResource.editSchema(agentID: Self.agentID)
        service.fetchAgentEditSchemaAgentIDReturnValue = .failure(.serverError(status: 503))
        store.show(resource, by: screen)
        await store.settle()

        guard case .failed = store.readState(resource, \.editSchema) else {
            Issue.record("A failed read with nothing shown must say it failed")
            return
        }
    }

    // MARK: - A screen coming into view

    /// A change the stream never brought shows when the person looks (357 item 8).
    @Test
    func aScreenComingIntoViewReadsWhatItShows() async {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(Self.directory)
        var name = "Anna"
        service.fetchAgentSpaceOrgIDClosure = { _ in .success(Self.space(agents: [Self.card(displayName: name)])) }
        let store = AgentsStore(service: service)
        let owner = NSObject()
        store.show(.spaces, by: owner)
        await Self.settle(store)

        name = "Renamed"
        store.refresh(.spaces)
        await Self.settle(store)

        #expect(store.card(agentID: Self.agentID)?.displayName == "Renamed")
        store.stopShowing(.spaces, by: owner)
    }

    /// The first appearance comes with the first read on its way: no second one.
    @Test
    func aReadOnItsWayIsNotDoubled() async {
        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(Self.directory)
        service.fetchAgentSpaceOrgIDClosure = { _ in .success(Self.space(agents: [Self.card()])) }
        let store = AgentsStore(service: service)
        let owner = NSObject()
        store.show(.spaces, by: owner)

        store.refresh(.spaces)
        await Self.settle(store)

        #expect(service.listMyAgentSpacesCallsCount == 1)
        store.stopShowing(.spaces, by: owner)
    }

    // MARK: - The person's own edit (S5)

    /// A save's answer shows at once on the Agents tab's card and on the agent's screens; the agent's rooms and
    /// verifications stay as read, and both are read again.
    @Test
    func anOwnEditShowsOnTheCardAndTheAgentAtOnce() async {
        let room = AgentRoomEntry(roomID: Self.roomID, displayName: "Team", kind: "group", activeTools: [])
        service.fetchAgentRoomsAgentIDReturnValue = .success([room])
        store.show(.spaces, by: screen)
        store.show(.agent(agentID: Self.agentID), by: screen)
        await store.settle()
        let before = readCounts()

        var edited = Self.readModel(displayName: "Bella", avatarMXC: "mxc://spiral.md/new", paused: true)
        edited.voiceLanguage = .uk
        store.agentEdited(edited)

        let card = store.card(agentID: Self.agentID)
        #expect(card?.displayName == "Bella")
        #expect(card?.avatarMXC == "mxc://spiral.md/new")
        #expect(card?.isPaused == true)
        let detail = store.value(.agent(agentID: Self.agentID))?.agent
        #expect(detail?.readModel == edited)
        #expect(detail?.rooms == [room])
        #expect(detail?.pendingVerifications == [])

        await store.settle()
        let after = readCounts()
        #expect(after[.spaces] == (before[.spaces] ?? 0) + 1)
        #expect(after[.agent(agentID: Self.agentID)] == (before[.agent(agentID: Self.agentID)] ?? 0) + 1)
    }

    /// A read that left before the edit doesn't put the older copy back, even when the read after it fails.
    @Test
    func aReadThatLeftBeforeAnEditDoesNotStepItBack() async {
        store.show(.agent(agentID: Self.agentID), by: screen)
        await store.settle()
        let older = HeldRead<AgentReadModel>(answer: .success(Self.readModel(displayName: "Anna")))
        service.fetchAgentReadModelAgentIDClosure = { _ in await older.answer() }
        store.refresh(.agent(agentID: Self.agentID))
        await older.waitUntilAsked()

        let edited = Self.readModel(displayName: "Bella")
        service.fetchAgentReadModelAgentIDClosure = nil
        service.fetchAgentReadModelAgentIDReturnValue = .failure(.serverError(status: 500))
        store.agentEdited(edited)
        older.release()
        await store.settle()

        #expect(service.fetchAgentReadModelAgentIDCallsCount == 3, "the read after the edit was asked for")
        #expect(store.value(.agent(agentID: Self.agentID))?.agent?.readModel == edited)
    }

    /// An edit of an agent no card holds leaves the spaces as read.
    @Test
    func anEditOfAnAgentNoCardHoldsLeavesTheSpaces() async {
        store.show(.spaces, by: screen)
        await store.settle()
        let spaces = store.spaces

        store.agentEdited(AgentReadModel(agentID: Self.otherAgentID, matrixUserID: Self.othersMXID, displayName: "Other", avatarMXC: "mxc://spiral.md/x",
                                         kind: "personal_assistant", visibility: "public", lifecycleState: "active", organizationID: Self.spaceID,
                                         roomCount: 0, activeToolCount: 0, configVersionNumber: 1, persona: nil))

        #expect(store.spaces == spaces)
        #expect(store.value(.agent(agentID: Self.otherAgentID)) == nil)
    }

    // MARK: - Helpers

    /// The reads running now have ended, without starting one of its own.
    private func makeSheet() -> AgentSheetScreenViewModel {
        AgentSheetScreenViewModel(roomID: Self.roomID,
                                  roomProxy: JoinedRoomProxyMock(.init(id: Self.roomID)),
                                  store: store,
                                  agentPlatformService: service,
                                  clientProxy: ClientProxyMock(.init()))
    }

    private static func settle(_ store: AgentsStore) async {
        for task in store.readTasks.values {
            await task.value
        }
    }

    private nonisolated static let agentID = "0192c3c4-0000-7000-8000-000000000001"
    private nonisolated static let otherAgentID = "0192c3c4-0000-7000-8000-000000000002"
    private nonisolated static let spaceID = "0192c3c4-0000-7000-8000-0000000000aa"
    private nonisolated static let directory = AgentSpacesDirectory(spaces: [.init(orgID: spaceID, name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)],
                                                                    provisioningStatus: .ready)
    private nonisolated static let roomID = "!room:spiral.md"
    private nonisolated static let ownMXID = "@assistant:spiral.md"
    private nonisolated static let othersMXID = "@agent-other:spiral.md"
    private nonisolated static let otherSpaceID = "0192c3c4-0000-7000-8000-0000000000bb"
    private nonisolated static let twoSpaces = AgentSpacesDirectory(spaces: [.init(orgID: spaceID, name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1),
                                                                             .init(orgID: otherSpaceID, name: "Other", kind: .solo, avatarMXC: nil, agentCount: 1)],
                                                                    provisioningStatus: .ready)

    private static let everyResource: [AgentsResource] = [
        .spaces, .agent(agentID: agentID), .activity(agentID: agentID, filter: .all), .activity(agentID: otherAgentID, filter: .all),
        .usage(agentID: agentID), .usage(agentID: otherAgentID), .blocks(agentID: agentID), .outreach(agentID: agentID, status: nil),
        .needsAction, .hubActivity, .publicProfile(userID: "@alice:spiral.md"), .roomTools(roomID: roomID),
        .toolsCatalog(agentID: agentID, roomID: roomID), .aiConsent, .editSchema(agentID: agentID)
    ]

    private static let personalSpace = AgentSpaceSummary(orgID: spaceID, name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)

    private static let usage = AgentUsage(current: .init(period: .week, startsAt: Date(timeIntervalSince1970: 0), resetsAt: Date(timeIntervalSince1970: 0),
                                                         usedPercent: 12, limitReached: false, categories: []),
                                          days: [])

    private static let approval = NeedsActionItem.approval(.init(id: "approval-1", agentID: agentID, draftBody: "Sure.",
                                                                 targetRoomID: roomID, createdAt: Date(timeIntervalSince1970: 0)))

    private static let catalog = ToolsCatalogView(agentID: agentID, roomID: roomID, paramsSchema: [:], triggerSchema: [:],
                                                  textTranslationLanguages: [], voiceTranslationLanguages: [],
                                                  availableToolKinds: ["summarize"])

    private static let editSchema = AgentEditSchema(agentID: agentID, kind: "personal_assistant", displayName: .init(minLength: 1, maxLength: 64), persona: nil)

    private nonisolated static func consent(isGranted: Bool) -> AIConsent {
        AIConsent(isGranted: isGranted, currentVersion: "1", decidedVersion: "1")
    }

    private nonisolated static func card(displayName: String = "Anna", isPaused: Bool = false) -> AgentSpaceAgentCard {
        AgentSpaceAgentCard(agentID: agentID, matrixUserID: "@assistant:spiral.md", displayName: displayName, avatarMXC: nil,
                            kind: "personal_assistant", visibility: "public", lifecycleState: "active", roomCount: 0, activeToolCount: 0, isPaused: isPaused)
    }

    private nonisolated static func space(agents: [AgentSpaceAgentCard]) -> AgentSpaceDetail {
        AgentSpaceDetail(orgID: spaceID, name: "Personal", kind: .solo, avatarMXC: nil, industry: nil, website: nil, agents: agents)
    }

    private static func readModel(displayName: String, avatarMXC: String? = nil, paused: Bool = false) -> AgentReadModel {
        AgentReadModel(agentID: agentID, matrixUserID: "@assistant:spiral.md", displayName: displayName, avatarMXC: avatarMXC,
                       kind: "personal_assistant", visibility: "public", lifecycleState: "active", organizationID: spaceID,
                       roomCount: 0, activeToolCount: 0, configVersionNumber: 1, persona: nil, paused: paused)
    }

    private static func snapshot(needsAction: [NeedsActionItem]) -> NotificationsSnapshot {
        NotificationsSnapshot(needsAction: needsAction, activity: [], nextActivityCursor: nil, lastSeenAt: nil, unseenCount: 0)
    }

    private static func activityEntry(id: String) -> AgentActivityEntry {
        AgentActivityEntry(id: id, agentID: agentID, roomID: nil, capabilityName: "tool.fire", inputRedacted: [:], reasoningSummary: "x",
                           policyDecision: .allowedDirect, policyReason: "tool_armed_by_owner", approvalID: nil, longFlowID: nil,
                           outcome: .executed, outcomeEventID: nil, createdAt: Date(timeIntervalSince1970: 0), resolvedAt: nil)
    }

    /// How often each resource was read, by its service call.
    private func readCounts() -> [AgentsResource: Int] {
        var counts: [AgentsResource: Int] = [:]
        counts[.spaces] = service.listMyAgentSpacesCallsCount
        counts[.agent(agentID: Self.agentID)] = service.fetchAgentReadModelAgentIDCallsCount
        let activity = service.listAgentActivityAgentIDFilterCursorLimitReceivedInvocations
        counts[.activity(agentID: Self.agentID, filter: .all)] = activity.count { $0.agentID == Self.agentID }
        counts[.activity(agentID: Self.otherAgentID, filter: .all)] = activity.count { $0.agentID == Self.otherAgentID }
        let usage = service.fetchAgentUsageAgentIDReceivedInvocations
        counts[.usage(agentID: Self.agentID)] = usage.count { $0 == Self.agentID }
        counts[.usage(agentID: Self.otherAgentID)] = usage.count { $0 == Self.otherAgentID }
        counts[.blocks(agentID: Self.agentID)] = service.listBlockedContactsAgentIDCursorLimitCallsCount
        counts[.outreach(agentID: Self.agentID, status: nil)] = service.listOutreachQueueAgentIDStatusLimitCallsCount
        let notifications = service.fetchNotificationsActivityCursorLimitReceivedInvocations
        counts[.needsAction] = notifications.count { $0.limit == 1 }
        counts[.hubActivity] = notifications.count { $0.limit > 1 }
        counts[.publicProfile(userID: "@alice:spiral.md")] = service.fetchUserProfileMxidCallsCount
        counts[.roomTools(roomID: Self.roomID)] = service.fetchRoomToolsRoomIDCallsCount
        counts[.toolsCatalog(agentID: Self.agentID, roomID: Self.roomID)] = service.fetchToolsCatalogAgentIDRoomIDCallsCount
        counts[.aiConsent] = service.fetchAIConsentCallsCount
        counts[.editSchema(agentID: Self.agentID)] = service.fetchAgentEditSchemaAgentIDCallsCount
        return counts
    }
}

/// Stands for a screen that holds a resource.
private final class Holder { }

/// What waits on the server, as a test changes it.
private final class Waiting {
    var items: [NeedsActionItem]

    init(items: [NeedsActionItem]) {
        self.items = items
    }
}

/// Holds a read until the test opens it.
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

extension AgentsStore {
    /// Waits until no read runs, those a read started included.
    func settle() async {
        while let task = readTasks.values.first {
            await task.value
            // Let the finished task take itself out before looking again.
            await Task.yield()
        }
    }
}
