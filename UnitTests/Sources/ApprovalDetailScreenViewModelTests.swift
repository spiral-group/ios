//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct ApprovalDetailScreenViewModelTests {
    @Test
    func appearedAction_fetchesAndSettlesToLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        if case .loaded(let detail) = viewModel.context.viewState.loadState {
            #expect(detail.id == "appr-1")
        } else {
            Issue.record("Expected .loaded state, got \(viewModel.context.viewState.loadState)")
        }
    }

    /// Coverage walk F9: the card names the room the draft goes to, never its ID.
    @Test
    func theTargetRoomIsNamedNotShownByID() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { .mock(id: $0, name: "Book club") }
        
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: clientProxy)
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.targetRoomName == "Book club")
    }
    
    /// Brief 0083, question 359: the decision bar holds its place during the read, and a tap there decides nothing.
    @Test
    func aDecisionWaitsForTheCard() async throws {
        let service = AgentPlatformServiceMock()
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        service.fetchApprovalIdClosure = { _ in
            for await _ in gate { }
            return .success(Self.genericFixture)
        }
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture, delivery: .sent(eventID: "$event-1")))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        
        viewModel.context.send(viewAction: .approve)
        viewModel.context.send(viewAction: .reject)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.context.viewState.loadState == .loading)
        #expect(viewModel.context.viewState.decideState == .idle)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { $0 == .loaded(Self.genericFixture) }
        continuation.finish()
        try await loaded.fulfill()
        #expect(!service.decideApprovalIdDecisionCalled)
    }
    
    @Test
    func aFailedReadDecidesNothing() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .failure(.serverError(status: 503))
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture, delivery: .sent(eventID: "$event-1")))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) { if case .failed = $0 { true } else { false } }
        viewModel.context.send(viewAction: .appeared)
        try await failed.fulfill()
        
        viewModel.context.send(viewAction: .approve)
        try await Task.sleep(for: .milliseconds(20))
        #expect(!service.decideApprovalIdDecisionCalled)
    }
    
    @Test
    func approveAction_finalisesOnSuccess() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture, delivery: .sent(eventID: "$event-1")))

        let viewModel: ApprovalDetailScreenViewModelProtocol =
            ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                          agentPlatformService: service,
                                          clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        // Wait for fetch.
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .approve)
        try await deferred.fulfill()

        #expect(service.decideApprovalIdDecisionCallsCount == 1)
    }

    @Test
    func rejectAction_finalisesOnNotSent() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture, delivery: .notSent))

        let viewModel: ApprovalDetailScreenViewModelProtocol =
            ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                          agentPlatformService: service,
                                          clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .reject)
        try await deferred.fulfill()
    }

    @Test
    func sendFailedDelivery_keepsScreenOpenAndExposesRetry() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture,
                                                                                      delivery: .sendFailed(reason: "homeserver down")))

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.decideState)) {
            if case .sendFailed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .approve)
        try await deferred.fulfill()

        if case .sendFailed(let decision, let reason) = viewModel.context.viewState.decideState {
            #expect(reason == "homeserver down")
            if case .approve = decision { /* ok */ } else {
                Issue.record("Expected .approve decision in send-failed state")
            }
        }
    }

    @Test
    func beginEdit_seedsBufferFromDraftBody() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .beginEdit)
        #expect(viewModel.context.viewState.bindings.isEditing)
        #expect(viewModel.context.viewState.bindings.editBuffer == Self.genericFixture.draftBody)
    }

    @Test
    func commitEdit_rejectsEmptyBody() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: Self.genericFixture, delivery: .sent(eventID: "$e")))

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .beginEdit)
        viewModel.context.editBuffer = "   "
        viewModel.context.send(viewAction: .commitEdit)
        try await Task.sleep(for: .milliseconds(20))

        // No decide call should have fired for whitespace-only.
        #expect(service.decideApprovalIdDecisionCallsCount == 0)
    }

    @Test
    func commitEdit_submitsTrimmedBody() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        var capturedDecision: ApprovalDecision?
        service.decideApprovalIdDecisionClosure = { _, decision in
            capturedDecision = decision
            return .success(ApprovalDecisionResult(approval: Self.genericFixture,
                                                   delivery: .sent(eventID: "$edit-event")))
        }

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .beginEdit)
        viewModel.context.editBuffer = "  Edited body  "
        viewModel.context.send(viewAction: .commitEdit)
        try await Task.sleep(for: .milliseconds(50))

        if case .edit(let body) = capturedDecision {
            #expect(body == "Edited body")
        } else {
            Issue.record("Expected .edit decision, got \(String(describing: capturedDecision))")
        }
    }

    @Test
    func retryDecide_replaysOriginalDecision() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        var attempt = 0
        service.decideApprovalIdDecisionClosure = { _, _ in
            attempt += 1
            if attempt == 1 {
                return .success(ApprovalDecisionResult(approval: Self.genericFixture,
                                                       delivery: .sendFailed(reason: "first try")))
            }
            return .success(ApprovalDecisionResult(approval: Self.genericFixture,
                                                   delivery: .sent(eventID: "$retry")))
        }

        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1",
                                                      agentPlatformService: service,
                                                      clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .approve)
        // Wait for send-failed transition.
        try await Task.sleep(for: .milliseconds(50))

        viewModel.context.send(viewAction: .retryDecide)
        try await Task.sleep(for: .milliseconds(50))

        #expect(attempt == 2)
        if case .succeeded = viewModel.context.viewState.decideState { /* ok */ } else {
            Issue.record("Expected .succeeded after retry, got \(viewModel.context.viewState.decideState)")
        }
    }

    // MARK: - A refused approve (backend audit A16)

    /// The owner blocked the person this card would write to: the platform
    /// refused the approve and closed the card. The owner reads why, with no
    /// retry, and OK leaves the card.
    @Test
    func anApproveToABlockedPersonSaysNotSentAndLeavesTheCard() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.coldOutreachFixture)
        service.decideApprovalIdDecisionReturnValue = .failure(.targetBlocked)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-outreach", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 == .targetBlocked }
        viewModel.context.send(viewAction: .approve)
        try await alerted.fulfill()

        let alert = viewModel.context.viewState.bindings.alertInfo
        #expect(alert?.title == UntranslatedL10n.screenApprovalDetailTargetBlockedTitle)
        #expect(alert?.message == UntranslatedL10n.screenApprovalDetailTargetBlockedMessage)
        #expect(alert?.secondaryButton == nil)
        #expect(!viewModel.context.viewState.isDecideInFlight)

        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        alert?.primaryButton.action?()
        try await finalised.fulfill()
        #expect(service.decideApprovalIdDecisionCallsCount == 1)
    }

    /// Decision 194: an approve of a paused agent's card is refused and the
    /// card stays — the owner hears why and how, not a generic error.
    @Test
    func anApproveWhilePausedSaysToResumeAndKeepsTheCard() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.coldOutreachFixture)
        service.decideApprovalIdDecisionReturnValue = .failure(.agentPaused)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-outreach", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 == .agentPaused }
        viewModel.context.send(viewAction: .approve)
        try await alerted.fulfill()

        let alert = viewModel.context.viewState.bindings.alertInfo
        #expect(alert?.title == UntranslatedL10n.screenApprovalDetailAgentPausedTitle)
        #expect(alert?.message == UntranslatedL10n.screenApprovalDetailAgentPausedMessage)
        #expect(!viewModel.context.viewState.isDecideInFlight)
    }

    /// A 404 `/errors/approval-not-found` on decide means the card is gone (its
    /// person was erased, so the platform deleted it; nothing was sent). It
    /// showed a generic error and kept the card open. It is final, for an
    /// approve, an edit or a reject.
    @Test(arguments: [ApprovalDecision.approve, .edit(newBody: "Edited"), .reject])
    func aDecideOfACardThatIsGoneSaysSoAndLeavesTheCard(decision: ApprovalDecision) async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .failure(.approvalNotFound)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        switch decision {
        case .approve: viewModel.context.send(viewAction: .approve)
        case .reject: viewModel.context.send(viewAction: .reject)
        case .edit(let body):
            viewModel.context.send(viewAction: .beginEdit)
            viewModel.context.editBuffer = body
            viewModel.context.send(viewAction: .commitEdit)
        }
        try await alerted.fulfill()

        let alert = viewModel.context.viewState.bindings.alertInfo
        #expect(alert?.id == .notFound)
        #expect(alert?.title == UntranslatedL10n.screenApprovalDetailNotFoundTitle)
        #expect(alert?.message == UntranslatedL10n.screenApprovalDetailNotFoundMessage)
        #expect(alert?.secondaryButton == nil)
        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        alert?.primaryButton.action?()
        try await finalised.fulfill()
    }

    /// A card opened after it was deleted (its person erased; a push, a stale
    /// list) has nothing to retry: it says so, and OK leaves it.
    @Test
    func aCardThatIsGoneWhenItOpensSaysSoAndOKLeavesIt() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .failure(.approvalNotFound)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .appeared)
        try await alerted.fulfill()

        let alert = viewModel.context.viewState.bindings.alertInfo
        #expect(alert?.id == .notFound)
        #expect(alert?.title == UntranslatedL10n.screenApprovalDetailNotFoundTitle)
        #expect(alert?.message == UntranslatedL10n.screenApprovalDetailNotFoundMessage)
        #expect(alert?.secondaryButton == nil, "no retry")
        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        alert?.primaryButton.action?()
        try await finalised.fulfill()
        #expect(service.fetchApprovalIdCallsCount == 1)
    }

    /// A bare 404 on the fetch keeps the generic error with its retry.
    @Test
    func aBareNotFoundWhenTheCardOpensOffersARetry() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .failure(.notFound)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .appeared)
        try await alerted.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .fetchFailed)
    }

    /// A bare `/errors/not-found` says nothing about the card (a route the
    /// platform does not serve answers it too): the generic error, the card stays.
    @Test
    func aBareNotFoundOnDecideKeepsTheGenericError() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.genericFixture)
        service.decideApprovalIdDecisionReturnValue = .failure(.notFound)
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-1", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.loadState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 != nil }
        viewModel.context.send(viewAction: .approve)
        try await alerted.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .decideFailed)
    }

    // MARK: - Block requests (decision 38)

    /// The card names the person and their group, which the snapshot carries by ID only.
    @Test
    func aBlockRequestNamesThePersonAndTheGroup() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.blockRequest(isDirectMessage: false))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(.init(userID: "@spam:example.com", displayName: " Spam Bot "))
        clientProxy.roomSummaryForIdentifierReturnValue = .mock(id: "!group:example.com", name: "Book club")
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: clientProxy)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.blockTargetDisplayName)) { $0 != nil }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.blockTargetDisplayName == "Spam Bot")
        #expect(viewModel.context.viewState.blockRoomName == "Book club")
        #expect(clientProxy.profileForReceivedUserID == "@spam:example.com")
        #expect(clientProxy.roomSummaryForIdentifierReceivedIdentifier == "!group:example.com")
    }

    /// Coverage review: the block card's group goes through the same room label,
    /// so a group named only by its ID falls back to the card's own wording.
    @Test
    func aBlockRequestsGroupNamedByItsIDIsNotNamedByIt() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.blockRequest(isDirectMessage: false))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(.init(userID: "@spam:example.com", displayName: "Spam Bot"))
        clientProxy.roomSummaryForIdentifierClosure = { .mock(id: $0, name: $0) }
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: clientProxy)
        
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.blockTargetDisplayName)) { $0 != nil }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
        
        #expect(viewModel.context.viewState.blockRoomName == nil)
    }
    
    /// A visitor's DM with the agent is not the owner's room; a profile
    /// without a name leaves the MXID to speak for itself.
    @Test
    func aBlockRequestInADirectChatLooksUpNoRoom() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.blockRequest(isDirectMessage: true))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(.init(userID: "@spam:example.com", displayName: nil))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: clientProxy)

        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(50))

        #expect(clientProxy.profileForCalled)
        // Only the card's target-room label asks (coverage walk F9); the block names no room.
        #expect(clientProxy.roomSummaryForIdentifierCallsCount == 1)
        #expect(viewModel.context.viewState.targetRoomName == UntranslatedL10n.commonAConversation)
        #expect(viewModel.context.viewState.blockTargetDisplayName == nil)
        #expect(viewModel.context.viewState.blockRoomName == nil)
    }

    /// `applied` keeps the card up reading "Blocked"; Done leaves it.
    @Test
    func approvingABlockRequestShowsItBlocked() async throws {
        let service = AgentPlatformServiceMock()
        let detail = Self.blockRequest(isDirectMessage: true)
        service.fetchApprovalIdReturnValue = .success(detail)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: detail, delivery: .applied))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let blocked = deferFulfillment(viewModel.context.observe(\.viewState.isBlocked)) { $0 }
        let staysOpen = deferFailure(viewModel.actionsPublisher, timeout: .milliseconds(100)) { _ in true }
        viewModel.context.send(viewAction: .approve)
        try await blocked.fulfill()
        try await staysOpen.fulfill()

        #expect(service.decideApprovalIdDecisionReceivedArguments?.decision == .approve)

        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .done)
        try await finalised.fulfill()
    }

    /// A 500 means the block was not saved: the card stays actionable and
    /// the alert's Retry approves again.
    @Test
    func aBlockThatWasNotSavedLeavesTheCardActionable() async throws {
        let service = AgentPlatformServiceMock()
        let detail = Self.blockRequest(isDirectMessage: true)
        service.fetchApprovalIdReturnValue = .success(detail)
        service.decideApprovalIdDecisionReturnValue = .failure(.serverError(status: 500))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let alerted = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo?.id)) { $0 == .blockFailed }
        viewModel.context.send(viewAction: .approve)
        try await alerted.fulfill()

        #expect(viewModel.context.viewState.decideState == .idle)
        #expect(!viewModel.context.viewState.isDecideInFlight)
        #expect(!viewModel.context.viewState.isBlocked)
        #expect(viewModel.context.viewState.loadState == .loaded(detail))

        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: detail, delivery: .applied))
        let blocked = deferFulfillment(viewModel.context.observe(\.viewState.isBlocked)) { $0 }
        viewModel.context.viewState.bindings.alertInfo?.primaryButton.action?()
        try await blocked.fulfill()
        #expect(service.decideApprovalIdDecisionCallsCount == 2)
    }

    /// Rejecting blocks nobody and finishes like any other rejection.
    @Test
    func rejectingABlockRequestFinalises() async throws {
        let service = AgentPlatformServiceMock()
        let detail = Self.blockRequest(isDirectMessage: true)
        service.fetchApprovalIdReturnValue = .success(detail)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: detail, delivery: .notSent))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .reject)
        try await finalised.fulfill()

        #expect(service.decideApprovalIdDecisionReceivedArguments?.decision == .reject)
        #expect(!viewModel.context.viewState.isBlocked)
    }

    /// A block request without its person falls back to the generic card,
    /// which has no "Blocked" state: `applied` finishes it like any decision.
    @Test
    func anAppliedGenericCardFinalises() async throws {
        let service = AgentPlatformServiceMock()
        let detail = ApprovalDetail(id: "appr-block",
                                    agentID: "agent-1",
                                    ownerUserID: "@alice:example.com",
                                    draftBody: "Sends the same advert again and again.",
                                    targetRoomID: "!visitor:example.com",
                                    state: .pending,
                                    context: .unknown(rawKind: "block_sender"),
                                    createdAt: Date(),
                                    updatedAt: Date(),
                                    expiresAt: nil,
                                    decidedAt: nil,
                                    decidedBy: nil,
                                    escalationReason: "block_sender")
        service.fetchApprovalIdReturnValue = .success(detail)
        service.decideApprovalIdDecisionReturnValue = .success(ApprovalDecisionResult(approval: detail, delivery: .applied))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let finalised = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decisionFinalised = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .approve)
        try await finalised.fulfill()
    }

    /// The platform refuses to edit a block request; the card offers no edit.
    @Test
    func aBlockRequestCannotBeEdited() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchApprovalIdReturnValue = .success(Self.blockRequest(isDirectMessage: true))
        let viewModel = ApprovalDetailScreenViewModel(approvalID: "appr-block", agentPlatformService: service, clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .beginEdit)
        viewModel.context.send(viewAction: .commitEdit)
        try await Task.sleep(for: .milliseconds(20))

        #expect(!viewModel.context.viewState.bindings.isEditing)
        #expect(service.decideApprovalIdDecisionCallsCount == 0)
    }

    // MARK: - Fixtures

    static let genericFixture = ApprovalDetail(id: "appr-1",
                                               agentID: "agent-1",
                                               ownerUserID: "@alice:example.com",
                                               draftBody: "Hi, the original draft body.",
                                               targetRoomID: "!room:example.com",
                                               state: .pending,
                                               context: .generic(senderMXID: nil),
                                               createdAt: Date(),
                                               updatedAt: Date(),
                                               expiresAt: nil,
                                               decidedAt: nil,
                                               decidedBy: nil,
                                               escalationReason: nil)

    static let coldOutreachFixture = ApprovalDetail(id: "appr-outreach",
                                                    agentID: "agent-1",
                                                    ownerUserID: "@alice:example.com",
                                                    draftBody: "Hi Carol, Alice asked me to get in touch.",
                                                    targetRoomID: "!outreach:example.com",
                                                    state: .pending,
                                                    context: .coldOutreach(targetMXID: "@carol:example.com", warnings: []),
                                                    createdAt: Date(),
                                                    updatedAt: Date(),
                                                    expiresAt: nil,
                                                    decidedAt: nil,
                                                    decidedBy: nil,
                                                    escalationReason: "cold_outreach")

    static func blockRequest(isDirectMessage: Bool) -> ApprovalDetail {
        let roomID = isDirectMessage ? "!visitor:example.com" : "!group:example.com"
        return ApprovalDetail(id: "appr-block",
                              agentID: "agent-1",
                              ownerUserID: "@alice:example.com",
                              draftBody: "Sends the same advert again and again.",
                              targetRoomID: roomID,
                              state: .pending,
                              context: .blockSender(.init(targetMXID: "@spam:example.com",
                                                          roomID: roomID,
                                                          isDirectMessage: isDirectMessage,
                                                          reason: "Sends the same advert again and again.",
                                                          userMessage: "BUY NOW")),
                              createdAt: Date(),
                              updatedAt: Date(),
                              expiresAt: nil,
                              decidedAt: nil,
                              decidedBy: nil,
                              escalationReason: "block_sender")
    }
}
