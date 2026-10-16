//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.
// Brief 0041 D3 — notifications hub ViewModel.

@testable import ElementX
import Foundation
import Testing

@MainActor
struct NotificationsHubScreenViewModelTests {
    // MARK: - appeared

    @Test
    func appearedAction_loadsActivityConnectsAndMarksSeen() async throws {
        let (viewModel, streamService, platformService) = Self.makeViewModel(activity: [Self.executedEntry],
                                                                             nextCursor: nil)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.activityItems.count == 1)
        #expect(viewModel.context.viewState.activityItems[0].outcome == .executed)
        #expect(viewModel.context.viewState.sentinel == nil)
        // Opening the hub is the "seen" gesture.
        #expect(streamService.markSeenCallsCount == 1)
        #expect(streamService.connectCallsCount == 1)
        // First page = nil cursor.
        #expect(platformService.fetchNotificationsActivityCursorLimitReceivedArguments?.activityCursor == nil)
    }

    @Test
    func needsActionSection_mirrorsStreamService() async throws {
        // The mock's stored properties aren't @Observable, so the
        // mirror can't see post-init mutations — configure BEFORE
        // constructing the VM (init does a synchronous refresh).
        let (viewModel, _, _) = Self.makeViewModel(activity: [],
                                                   nextCursor: nil,
                                                   needsAction: [.approval(Self.approvalSummary),
                                                                 .verification(Self.verificationSummary)])

        let items = viewModel.context.viewState.needsAction
        #expect(items.map(\.kind) == [.approval, .verification])
        #expect(items[0].subjectID == "approval-1")
        #expect(items[0].preview == "draft body")
        // Coverage walk F9: never the room id; the owner isn't in a visitor's chat.
        #expect(items[0].detail == UntranslatedL10n.commonAConversation)
        #expect(items[1].subjectID == "verification-1")
        #expect(items[1].preview == "@alice:spiral.md")
    }

    @Test
    func selectNeedsAction_routesByFamily() async throws {
        let (viewModel, _, _) = Self.makeViewModel(activity: [],
                                                   nextCursor: nil,
                                                   needsAction: [.approval(Self.approvalSummary),
                                                                 .verification(Self.verificationSummary)])
        #expect(viewModel.context.viewState.needsAction.count == 2)

        var actions: [NotificationsHubScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .selectNeedsAction(id: "approval-approval-1"))
        viewModel.context.send(viewAction: .selectNeedsAction(id: "verification-verification-1"))

        #expect(actions.count == 2)
        guard case .selectApproval(let approvalID) = actions[0] else {
            Issue.record("expected selectApproval"); return
        }
        #expect(approvalID == "approval-1")
        guard case .selectVerification(let verificationID) = actions[1] else {
            Issue.record("expected selectVerification"); return
        }
        #expect(verificationID == "verification-1")
    }

    // MARK: - pagination

    @Test
    func loadMore_appendsNextPageAndExhausts() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [Self.executedEntry],
                                                                 nextCursor: "cursor-1")

        let firstPage = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded(_, .idle) = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await firstPage.fulfill()
        #expect(viewModel.context.viewState.sentinel == .idle(cursor: "cursor-1"))

        // Page 2 resolves with no cursor → exhausted.
        platformService.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [],
                                                                                          activity: [Self.deniedEntry],
                                                                                          nextActivityCursor: nil,
                                                                                          lastSeenAt: nil,
                                                                                          unseenCount: 0))
        let secondPage = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded(let items, .exhausted) = $0, items.count == 2 { return true }
            return false
        }
        viewModel.context.send(viewAction: .loadMore)
        try await secondPage.fulfill()

        #expect(viewModel.context.viewState.activityItems.map(\.id) == ["row-executed", "row-denied"])
        #expect(platformService.fetchNotificationsActivityCursorLimitReceivedArguments?.activityCursor == "cursor-1")
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    @Test
    func loadMoreFailure_preservesItemsAndCursor() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [Self.executedEntry],
                                                                 nextCursor: "cursor-1")
        let firstPage = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded(_, .idle) = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await firstPage.fulfill()

        platformService.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 500))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded(_, .failed) = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .loadMore)
        try await failed.fulfill()

        // Items stay; cursor preserved for the retry tap.
        #expect(viewModel.context.viewState.activityItems.count == 1)
        #expect(viewModel.context.viewState.sentinel == .failed(cursor: "cursor-1"))
    }

    @Test
    func firstPageFailure_surfacesErrorState() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [], nextCursor: nil)
        platformService.fetchNotificationsActivityCursorLimitReturnValue = .failure(.serverError(status: 500))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    /// Coverage walk F9: the hub showed `!VthLDa…:localhost`. A room this
    /// device knows is named; one it doesn't is "A conversation"; a roomless
    /// row names none.
    @Test
    func roomsAreNamedNeverShownByID() async throws {
        let (viewModel, _, _) = Self.makeViewModel(activity: [Self.executedEntry, Self.deniedEntry],
                                                   nextCursor: nil,
                                                   needsAction: [.approval(Self.approvalSummary)],
                                                   roomNames: ["!room:spiral.md": "Book club"])
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.activityItems.map(\.roomName) == ["Book club", nil])
        #expect(viewModel.context.viewState.needsAction.map(\.detail) == [UntranslatedL10n.commonAConversation])
    }
    
    /// Coverage review: every visitor's card read "A conversation", so two
    /// pending cards for different people looked the same. A card names its
    /// person: their display name, else their Matrix ID; only a card that
    /// names nobody falls back to the room label.
    @Test
    func pendingCardsNameTheirPerson() async throws {
        let bob = ApprovalSummary(id: "approval-bob", agentID: "agent-1", draftBody: "to bob", targetRoomID: "!bob-dm:spiral.md",
                                  createdAt: Date(timeIntervalSinceNow: -60), counterpartMXID: "@bob:spiral.md")
        let carol = ApprovalSummary(id: "approval-carol", agentID: "agent-1", draftBody: "to carol", targetRoomID: "!carol-dm:spiral.md",
                                    createdAt: Date(timeIntervalSinceNow: -120), counterpartMXID: "@carol:spiral.md")
        let nameless = ApprovalSummary(id: "approval-dave", agentID: "agent-1", draftBody: "to dave", targetRoomID: "!dave-dm:spiral.md",
                                       createdAt: Date(timeIntervalSinceNow: -180), counterpartMXID: "@dave:spiral.md")
        let (viewModel, _, _) = Self.makeViewModel(activity: [],
                                                   nextCursor: nil,
                                                   needsAction: [.approval(bob), .approval(carol), .approval(nameless), .approval(Self.approvalSummary)],
                                                   profileNames: ["@bob:spiral.md": "Bob", "@carol:spiral.md": "Carol"])
        
        let named = deferFulfillment(viewModel.context.observe(\.viewState.needsAction)) { items in
            items.map(\.detail) == ["Bob", "Carol", "@dave:spiral.md", UntranslatedL10n.commonAConversation]
        }
        try await named.fulfill()
    }
    
    @Test
    func aRoomWhoseNameIsItsIDIsNotNamedByIt() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { .mock(id: $0, name: $0) }
        
        #expect(AgentRoomLabel.text(for: "!abc:localhost", clientProxy: clientProxy) == UntranslatedL10n.commonAConversation)
        #expect(AgentRoomLabel.text(for: "", clientProxy: clientProxy) == nil)
        #expect(AgentRoomLabel.text(for: nil, clientProxy: clientProxy) == nil)
    }
    
    // MARK: - People the assistants don't answer (decisions 194-196)

    static let message = VisitorMessage(id: "v1", kind: .message, agentID: "agent-1", visitorMXID: "@bob:spiral.md",
                                        roomID: "!bob:spiral.md", body: "Are we on for Friday?", createdAt: Date(timeIntervalSince1970: 1_760_000_000))
    static let missedCall = VisitorMessage(id: "v2", kind: .missedCall, agentID: "agent-1", visitorMXID: "@carol:spiral.md",
                                           roomID: "!carol:spiral.md", body: "", createdAt: Date(timeIntervalSince1970: 1_759_990_000))
    static let assistant = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-me:spiral.md", displayName: "Assistant",
                                               avatarMXC: nil, kind: "personal_assistant", visibility: "private", lifecycleState: "active",
                                               presence: .online, roomCount: 1, activeToolCount: 0)

    private func appeared(_ viewModel: NotificationsHubScreenViewModel) async throws {
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.activityState)) { if case .loaded = $0 { true } else { false } }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
    }

    @Test
    func visitorsEntriesAreRowsWithTheirNames() async throws {
        let (viewModel, _, _) = Self.makeViewModel(activity: [], nextCursor: nil, profileNames: ["@bob:spiral.md": "Bob"],
                                                   visitorMessages: [Self.message, Self.missedCall])
        try await appeared(viewModel)
        let named = deferFulfillment(viewModel.context.observe(\.viewState.visitorMessages)) { $0.first?.visitorName == "Bob" }
        try await named.fulfill()

        let rows = viewModel.context.viewState.visitorMessages
        #expect(rows.map(\.title) == [UntranslatedL10n.screenNotificationsHubVisitorNewMessage,
                                      UntranslatedL10n.screenNotificationsHubVisitorMissedCall])
        #expect(rows.map(\.visitorName) == ["Bob", "@carol:spiral.md"])
        #expect(rows.map(\.body) == ["Are we on for Friday?", nil])
        #expect(!viewModel.context.viewState.isEmpty)
    }

    /// Decision 96: a kind newer than this build is a generic row asking to update.
    @Test
    func aNewerKindIsAGenericRow() async throws {
        let newer = VisitorMessage(id: "v3", kind: .init(serverValue: "voicemail"), agentID: "agent-1", visitorMXID: "@dave:spiral.md",
                                   roomID: "!dave:spiral.md", body: "…", createdAt: .now)
        let (viewModel, _, _) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [newer])
        try await appeared(viewModel)

        let row = try #require(viewModel.context.viewState.visitorMessages.first)
        #expect(row.title == UntranslatedL10n.screenNotificationsHubVisitorOther)
        #expect(row.visitorName == "@dave:spiral.md")
        #expect(row.body == UntranslatedL10n.screenNotificationsHubVisitorOtherBody)
    }

    @Test
    func aTapOpensTheChatWhenThisDeviceHasIt() async throws {
        let (viewModel, _, _) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [Self.message],
                                                   joinedRoomIDs: [Self.message.roomID])
        try await appeared(viewModel)

        let opened = deferFulfillment(viewModel.actionsPublisher) { if case .openRoom(roomID: Self.message.roomID) = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectVisitorMessage(id: Self.message.id))
        try await opened.fulfill()
    }

    @Test
    func aTapOpensTheAssistantsPeopleSettingsOtherwise() async throws {
        let (viewModel, _, _) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [Self.message], agents: [Self.assistant])
        try await appeared(viewModel)

        let opened = deferFulfillment(viewModel.actionsPublisher) {
            if case .showVisitorSettings(let agent) = $0 { agent == Self.assistant } else { false }
        }
        viewModel.context.send(viewAction: .selectVisitorMessage(id: Self.message.id))
        try await opened.fulfill()
    }

    @Test
    func aDismissRemovesTheRowAndAsksTheServer() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [Self.message, Self.missedCall])
        platformService.dismissVisitorMessageIdReturnValue = .success(())
        try await appeared(viewModel)

        viewModel.context.send(viewAction: .dismissVisitorMessage(id: Self.message.id))
        let removed = deferFulfillment(viewModel.context.observe(\.viewState.visitorMessages)) { $0.map(\.id) == [Self.missedCall.id] }
        try await removed.fulfill()
        while !platformService.dismissVisitorMessageIdCalled {
            await Task.yield()
        }
        #expect(platformService.dismissVisitorMessageIdReceivedId == Self.message.id)
    }

    /// A refused dismiss puts the row back where it was.
    @Test
    func aFailedDismissReverts() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [Self.message, Self.missedCall])
        platformService.dismissVisitorMessageIdReturnValue = .failure(.serverError(status: 500))
        try await appeared(viewModel)

        let reverted = deferFulfillment(viewModel.context.observe(\.viewState.visitorMessages)) { rows in
            platformService.dismissVisitorMessageIdCalled && rows.map(\.id) == [Self.message.id, Self.missedCall.id]
        }
        viewModel.context.send(viewAction: .dismissVisitorMessage(id: Self.message.id))
        try await reverted.fulfill()
    }

    /// One already gone on the server (dismissed elsewhere, expired) stays gone.
    @Test
    func aDismissOfAnEntryAlreadyGoneStaysGone() async throws {
        let (viewModel, _, platformService) = Self.makeViewModel(activity: [], nextCursor: nil, visitorMessages: [Self.message])
        platformService.dismissVisitorMessageIdReturnValue = .failure(.notFound)
        try await appeared(viewModel)

        viewModel.context.send(viewAction: .dismissVisitorMessage(id: Self.message.id))
        while !platformService.dismissVisitorMessageIdCalled {
            await Task.yield()
        }
        await Task.yield()
        #expect(viewModel.context.viewState.visitorMessages.isEmpty)
    }

    // MARK: - Fixtures

    static func makeViewModel(activity: [AgentActivityEntry],
                              nextCursor: String?,
                              needsAction: [NeedsActionItem] = [],
                              roomNames: [String: String] = [:],
                              profileNames: [String: String] = [:],
                              visitorMessages: [VisitorMessage] = [],
                              joinedRoomIDs: Set<String> = [],
                              agents: [AgentSpaceAgentCard] = []) -> (NotificationsHubScreenViewModel, ApprovalsStreamServiceMock, AgentPlatformServiceMock) {
        let streamService = ApprovalsStreamServiceMock()
        streamService.needsAction = needsAction
        streamService.underlyingPendingCount = 0
        streamService.underlyingUnseenCount = 0
        streamService.underlyingConnectionState = .connected
        streamService.connectClosure = {}
        streamService.reseedClosure = {}
        streamService.markSeenClosure = {}

        let platformService = AgentPlatformServiceMock()
        platformService.fetchNotificationsActivityCursorLimitReturnValue = .success(.init(needsAction: [],
                                                                                          activity: activity,
                                                                                          nextActivityCursor: nextCursor,
                                                                                          lastSeenAt: nil,
                                                                                          unseenCount: 0,
                                                                                          visitorMessages: visitorMessages))
        platformService.markNotificationsSeenReturnValue = .success(Date())
        if agents.isEmpty {
            platformService.listMyAgentSpacesReturnValue = .success(.init(spaces: [], provisioningStatus: .ready))
        } else {
            platformService.listMyAgentSpacesReturnValue = .success(.init(spaces: [.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                                         agentCount: agents.count)],
                                                                          provisioningStatus: .ready))
            platformService.fetchAgentSpaceOrgIDReturnValue = .success(.init(orgID: "org-1", name: "Personal", kind: .solo, avatarMXC: nil,
                                                                             industry: nil, website: nil, agents: agents))
        }

        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { roomID in roomNames[roomID].map { .mock(id: roomID, name: $0) } }
        clientProxy.profileForClosure = { userID in .success(UserProfile(userID: userID, displayName: profileNames[userID])) }
        clientProxy.roomForIdentifierClosure = { roomID in joinedRoomIDs.contains(roomID) ? .joined(JoinedRoomProxyMock(.init(id: roomID))) : nil }
        let viewModel = NotificationsHubScreenViewModel(approvalsStreamService: streamService,
                                                        agentPlatformService: platformService,
                                                        clientProxy: clientProxy,
                                                        userIndicatorController: UserIndicatorControllerMock())
        return (viewModel, streamService, platformService)
    }

    static let approvalSummary = ApprovalSummary(id: "approval-1",
                                                 agentID: "agent-1",
                                                 draftBody: "draft body",
                                                 targetRoomID: "!visitor:spiral.md",
                                                 createdAt: Date(timeIntervalSinceNow: -60))

    static let verificationSummary = VerificationSummary(id: "verification-1",
                                                         requesterUserID: "@alice:spiral.md",
                                                         requesterDeviceID: "IPHONE15",
                                                         state: .pendingOwner,
                                                         createdAt: Date(timeIntervalSinceNow: -180),
                                                         deadlineAt: Date(timeIntervalSinceNow: 600))

    static let executedEntry = AgentActivityEntry(id: "row-executed",
                                                  agentID: "agent-1",
                                                  roomID: "!room:spiral.md",
                                                  capabilityName: "messenger.reply_in_room",
                                                  inputRedacted: [:],
                                                  reasoningSummary: "replied",
                                                  policyDecision: .allowedDirect,
                                                  policyReason: "relationship_approved",
                                                  approvalID: nil,
                                                  longFlowID: nil,
                                                  outcome: .executed,
                                                  outcomeEventID: "$ev",
                                                  createdAt: Date(timeIntervalSinceNow: -3600),
                                                  resolvedAt: Date(timeIntervalSinceNow: -3595))

    static let deniedEntry = AgentActivityEntry(id: "row-denied",
                                                agentID: "agent-1",
                                                roomID: nil,
                                                capabilityName: "messenger.reply_in_room",
                                                inputRedacted: [:],
                                                reasoningSummary: "blocked",
                                                policyDecision: .denied,
                                                policyReason: "blocked_visitor",
                                                approvalID: nil,
                                                longFlowID: nil,
                                                outcome: .denied,
                                                outcomeEventID: nil,
                                                createdAt: Date(timeIntervalSinceNow: -7200),
                                                resolvedAt: Date(timeIntervalSinceNow: -7200))
}
