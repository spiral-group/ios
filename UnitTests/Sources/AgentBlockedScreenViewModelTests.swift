//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 194): «Заблокированные» — the agent's own blocks,
// page by page, with an unblock per row.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct AgentBlockedScreenViewModelTests {
    private static let agent = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                   displayName: "Assistant", avatarMXC: nil, kind: "personal_assistant",
                                                   visibility: "public", lifecycleState: "active", presence: .online,
                                                   roomCount: 1, activeToolCount: 0)

    private static func block(_ name: String) -> AgentBlockedContact {
        AgentBlockedContact(contactMXID: "@\(name):spiral.md", displayName: name.capitalized, blockedAt: Date(timeIntervalSince1970: 1_760_000_000))
    }

    private func loadedViewModel(service: AgentPlatformServiceMock) async throws -> AgentBlockedScreenViewModel {
        let viewModel = AgentBlockedScreenViewModel(agent: Self.agent,
                                                    agentPlatformService: service,
                                                    userIndicatorController: UserIndicatorControllerMock())
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { $0 != .loading }
        try await loaded.fulfill()
        return viewModel
    }

    @Test
    func theFirstPageIsTheAgentsOwnBlocks() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob")], nextCursor: nil))

        let viewModel = try await loadedViewModel(service: service)

        #expect(viewModel.context.viewState.blocks == [Self.block("bob")])
        #expect(viewModel.context.viewState.sentinel == nil)
        let arguments = service.listBlockedContactsAgentIDCursorLimitReceivedArguments
        #expect(arguments?.agentID == "agent-1")
        #expect(arguments?.cursor == nil)
        #expect(arguments?.limit == AgentBlockedScreenViewModel.pageSize)
    }

    /// A failed read is a failure with a retry, never «nobody is blocked».
    @Test
    func aFailedReadIsNotAnEmptyList() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 500))

        let viewModel = try await loadedViewModel(service: service)
        #expect(viewModel.context.viewState.listState == .failed)

        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob")], nextCursor: nil))
        let reloaded = deferFulfillment(viewModel.context.observe(\.viewState.blocks)) { $0.count == 1 }
        viewModel.context.send(viewAction: .retry)
        try await reloaded.fulfill()
    }

    @Test
    func theNextPageFollowsTheCursor() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob")], nextCursor: "c1"))
        let viewModel = try await loadedViewModel(service: service)
        #expect(viewModel.context.viewState.sentinel == .idle(cursor: "c1"))

        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("eve")], nextCursor: nil))
        let appended = deferFulfillment(viewModel.context.observe(\.viewState.blocks)) { $0.count == 2 }
        viewModel.context.send(viewAction: .loadMore)
        try await appended.fulfill()

        #expect(service.listBlockedContactsAgentIDCursorLimitReceivedArguments?.cursor == "c1")
        #expect(viewModel.context.viewState.blocks.map(\.contactMXID) == ["@bob:spiral.md", "@eve:spiral.md"])
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    /// A failed next page keeps what is shown and offers the same cursor again.
    @Test
    func aFailedNextPageKeepsTheRows() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob")], nextCursor: "c1"))
        let viewModel = try await loadedViewModel(service: service)

        service.listBlockedContactsAgentIDCursorLimitReturnValue = .failure(.serverError(status: 500))
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.sentinel)) { $0 == .failed(cursor: "c1") }
        viewModel.context.send(viewAction: .loadMore)
        try await failed.fulfill()
        #expect(viewModel.context.viewState.blocks == [Self.block("bob")])
    }

    @Test
    func anUnblockAsksThenRemovesTheRow() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob"), Self.block("eve")], nextCursor: nil))
        service.unblockContactForAgentReturnValue = .success(())
        let viewModel = try await loadedViewModel(service: service)

        viewModel.context.send(viewAction: .unblock(contactMXID: "@bob:spiral.md"))
        let alert = try #require(viewModel.context.viewState.bindings.alertInfo)
        #expect(alert.id == .confirmUnblock)
        #expect(!service.unblockContactForAgentCalled)

        let removed = deferFulfillment(viewModel.context.observe(\.viewState.blocks)) { $0.count == 1 }
        alert.primaryButton.action?()
        try await removed.fulfill()

        #expect(service.unblockContactForAgentReceivedArguments?.contactMXID == "@bob:spiral.md")
        #expect(service.unblockContactForAgentReceivedArguments?.agentID == "agent-1")
        #expect(viewModel.context.viewState.blocks == [Self.block("eve")])
    }

    @Test
    func aFailedUnblockKeepsTheRow() async throws {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = .success(.init(blocks: [Self.block("bob")], nextCursor: nil))
        service.unblockContactForAgentReturnValue = .failure(.serverError(status: 500))
        let viewModel = try await loadedViewModel(service: service)

        viewModel.context.send(viewAction: .unblock(contactMXID: "@bob:spiral.md"))
        let done = deferFulfillment(viewModel.context.observe(\.viewState.unblockingMXID)) { $0 == nil && service.unblockContactForAgentCalled }
        viewModel.context.viewState.bindings.alertInfo?.primaryButton.action?()
        try await done.fulfill()

        #expect(viewModel.context.viewState.blocks == [Self.block("bob")])
    }

    // MARK: - The agent screen's count

    @Test
    func theCountSaysWhenThereAreMorePages() {
        #expect(AgentBlockedCount(page: .init(blocks: [Self.block("bob")], nextCursor: nil)).text == "1")
        #expect(AgentBlockedCount(page: .init(blocks: Array(repeating: Self.block("bob"), count: 50), nextCursor: "c")).text == "50+")
        #expect(AgentBlockedCount(page: .init(blocks: [], nextCursor: nil)).text == "0")
    }
}
