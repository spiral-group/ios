//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM: Agent platform feature, not present upstream.

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct OutreachQueueListScreenViewModelTests {
    // MARK: - Loading paths

    @Test
    func appearedAction_landsLoadedOnFetchSuccess() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([Self.entry(id: "row-1", status: .queued)])

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.listState.items.count == 1)
    }

    @Test
    func appearedAction_landsLoadedEmptyWhenZeroRows() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.listState.items.isEmpty)
    }

    @Test
    func appearedAction_conflict409MapsToUnavailable() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .failure(.conflict(detail: "not Outreach"))

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .unavailable = $0 { return true }
            return false
        }
        try await deferred.fulfill()
    }

    @Test
    func appearedAction_notFoundMapsToUnavailable() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .failure(.notFound)

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .unavailable = $0 { return true }
            return false
        }
        try await deferred.fulfill()
    }

    @Test
    func appearedAction_transportFailureSurfacesFailedState() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .failure(.serverError(status: 500))

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        try await deferred.fulfill()
    }

    /// Walk F4, now by the stream: an add (here or elsewhere) is
    /// `agent.outreach`, which reads the queue again and keeps its rows meanwhile.
    @Test
    func theStreamsChangeReadsTheQueueAgainWithoutBlankingIt() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])
        let store = AgentsStore(service: service)
        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1", store: store)
        await store.settle()

        let added = Self.entry(id: "row-2", status: .queued)
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([added])
        var states: [OutreachQueueListState] = []
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { state in
            states.append(state)
            return state == .loaded([added])
        }
        store.apply([.agentOutreach(agentID: "agent-1")])
        try await reloaded.fulfill()

        #expect(service.listOutreachQueueAgentIDStatusLimitCallsCount == 2)
        #expect(!states.contains(.loading))
    }

    @Test
    func aFailedRereadKeepsTheRows() async throws {
        let service = AgentPlatformServiceMock()
        let shown = Self.entry(id: "row-1", status: .queued)
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([shown])
        let store = AgentsStore(service: service)
        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1", store: store)
        await store.settle()

        service.listOutreachQueueAgentIDStatusLimitReturnValue = .failure(.serverError(status: 500))
        store.apply([.agentOutreach(agentID: "agent-1")])
        await store.settle()

        #expect(service.listOutreachQueueAgentIDStatusLimitCallsCount == 2)
        #expect(viewModel.context.viewState.listState == .loaded([shown]))
    }

    // MARK: - Filter

    @Test
    func selectFilterAction_triggersRefetchWithStatusQueryParam() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded(let items) = $0 { return items.isEmpty }
            return false
        }
        viewModel.context.send(viewAction: .selectFilter(.pendingApproval))
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.statusFilter == .pendingApproval)
        #expect(service.listOutreachQueueAgentIDStatusLimitReceivedArguments?.status == .pendingApproval)
    }

    @Test
    func selectFilterNilAction_clearsFilterAndRefetches() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])

        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service),
                                                         initialFilter: .sent)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.statusFilter)) { $0 == nil }
        viewModel.context.send(viewAction: .selectFilter(nil))
        try await deferred.fulfill()

        #expect(service.listOutreachQueueAgentIDStatusLimitReceivedArguments?.status == nil)
    }

    // MARK: - Coordinator emission

    @Test
    func openAddTargetsAction_emitsCoordinatorAction() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])
        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .openAddTargets = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .openAddTargets)
        try await deferred.fulfill()
    }

    @Test
    func dismissAction_emitsDismissedCoordinatorAction() async throws {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitReturnValue = .success([])
        let viewModel = OutreachQueueListScreenViewModel(agentID: "agent-1",
                                                         store: AgentsStore(service: service))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .dismiss)
        try await deferred.fulfill()
    }

    // MARK: - Fixtures

    static func entry(id: String, status: OutreachTargetStatus) -> OutreachQueueEntry {
        OutreachQueueEntry(id: id,
                           targetMXID: "@\(id):spiral.md",
                           status: status,
                           approvalID: nil,
                           draftBody: nil,
                           errorMessage: nil,
                           createdAt: Date(),
                           updatedAt: Date())
    }
}

@MainActor
struct OutreachQueueAddScreenViewModelTests {
    // MARK: - Parsing (pure)

    @Test
    func parseLines_splitsOnNewlinesAndTrimsAndDropsEmpty() {
        let raw = "\n  @bob:host  \n\n@carol:host\n   \n@dave:host\n"
        let parsed = OutreachQueueAddScreenViewState.parseLines(raw)
        #expect(parsed == ["@bob:host", "@carol:host", "@dave:host"])
    }

    @Test
    func parseLines_emptyBufferReturnsEmpty() {
        #expect(OutreachQueueAddScreenViewState.parseLines("").isEmpty)
        #expect(OutreachQueueAddScreenViewState.parseLines("   \n   ").isEmpty)
    }

    @Test
    func parsedCount_reflectsTrimmedNonEmptyLines() {
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialText: "@bob:host\n@carol:host")
        #expect(viewModel.context.viewState.parsedCount == 2)
        #expect(!viewModel.context.viewState.isOverLimit)
    }

    @Test
    func parsedCount_over200FlipsIsOverLimit() {
        let lines = (0..<201).map { "@user\($0):host" }.joined(separator: "\n")
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialText: lines)
        #expect(viewModel.context.viewState.parsedCount == 201)
        #expect(viewModel.context.viewState.isOverLimit)
    }

    // MARK: - Submit

    @Test
    func submitAction_sendsParsedLinesAndLandsResults() async throws {
        let service = AgentPlatformServiceMock()
        let result = EnqueueOutreachResult(items: [
            EnqueueOutreachItem(targetMXID: "@bob:host", outcome: .queued(id: "target-1")),
            EnqueueOutreachItem(targetMXID: "@carol:host", outcome: .duplicate)
        ], accepted: 1, rejected: 1)
        service.enqueueOutreachTargetsAgentIDMxidsReturnValue = .success(result)

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: "@bob:host\n@carol:host")

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .results = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        #expect(service.enqueueOutreachTargetsAgentIDMxidsReceivedArguments?.mxids == ["@bob:host", "@carol:host"])
    }

    @Test
    func submitAction_emitsEnqueuedCoordinatorAction() async throws {
        let service = AgentPlatformServiceMock()
        service.enqueueOutreachTargetsAgentIDMxidsReturnValue = .success(EnqueueOutreachResult(items: [], accepted: 0, rejected: 0))

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: "@bob:host")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .enqueued = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()
    }

    @Test
    func submitAction_emptyBufferIsNoOp() async throws {
        let service = AgentPlatformServiceMock()

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: "")
        viewModel.context.send(viewAction: .submit)
        try await Task.sleep(for: .milliseconds(30))

        #expect(service.enqueueOutreachTargetsAgentIDMxidsCallsCount == 0)
    }

    @Test
    func submitAction_over200BufferShortCircuitsBeforeServiceCall() async throws {
        let service = AgentPlatformServiceMock()
        let lines = (0..<201).map { "@user\($0):host" }.joined(separator: "\n")

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: lines)
        viewModel.context.send(viewAction: .submit)
        try await Task.sleep(for: .milliseconds(30))

        #expect(service.enqueueOutreachTargetsAgentIDMxidsCallsCount == 0)
    }

    @Test
    func submitAction_409SurfacesAsUnavailable() async throws {
        let service = AgentPlatformServiceMock()
        service.enqueueOutreachTargetsAgentIDMxidsReturnValue = .failure(.conflict(detail: "not Outreach"))

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: "@bob:host")

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .unavailable = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()
    }

    @Test
    func submitAction_transientFailurePreservesBuffer() async throws {
        let service = AgentPlatformServiceMock()
        service.enqueueOutreachTargetsAgentIDMxidsReturnValue = .failure(.serverError(status: 500))

        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: service,
                                                        initialText: "@bob:host")

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .submit)
        try await deferred.fulfill()

        // Buffer survives so the user can retry.
        #expect(viewModel.context.viewState.bindings.draftText == "@bob:host")
        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    // MARK: - Cancel

    @Test
    func cancelAction_dismissesImmediatelyWhenBufferEmpty() async throws {
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialText: "")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .cancel)
        try await deferred.fulfill()
    }

    @Test
    func cancelAction_raisesUnsavedAlertWhenBufferDirty() {
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialText: "@bob:host")
        viewModel.context.send(viewAction: .cancel)
        #expect(viewModel.context.viewState.bindings.alertInfo?.id == .unsavedChanges)
    }

    @Test
    func cancelAction_dismissesImmediatelyOnResultsTerminalState() async throws {
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialState: .results(EnqueueOutreachResult(items: [], accepted: 0, rejected: 0)),
                                                        initialText: "@bob:host")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .cancel)
        try await deferred.fulfill()
    }

    @Test
    func discardChangesAction_emitsDismissed() async throws {
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "agent-1",
                                                        agentPlatformService: AgentPlatformServiceMock(),
                                                        initialText: "@bob:host")

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .discardChanges)
        try await deferred.fulfill()
    }
}
