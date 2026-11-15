//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.
//

import Foundation
@testable import Spiral
import Testing

@MainActor
struct AgentPickerScreenViewModelTests {
    @Test
    func selectAgent_emitsChosenAgent() async throws {
        let viewModel = Self.makeViewModel()
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .selectAgent(let agent) = action { return agent.agentID == "a2" }
            return false
        }
        viewModel.context.send(viewAction: .selectAgent(id: "a2"))
        try await deferred.fulfill()
    }

    @Test
    func selectUnknownAgent_isIgnored() async throws {
        let viewModel = Self.makeViewModel()
        var received = false
        let cancellable = viewModel.actionsPublisher.sink { _ in received = true }
        viewModel.context.send(viewAction: .selectAgent(id: "does-not-exist"))
        try await Task.sleep(for: .milliseconds(20))
        cancellable.cancel()
        #expect(!received)
    }

    @Test
    func done_emitsDismiss() async throws {
        let viewModel = Self.makeViewModel()
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismiss = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .done)
        try await deferred.fulfill()
    }

    private static func makeViewModel() -> AgentPickerScreenViewModel {
        AgentPickerScreenViewModel(agents: [
            AgentPickerItem(agentID: "a1", matrixUserID: "@one:host", displayName: "One", activeToolCount: 1),
            AgentPickerItem(agentID: "a2", matrixUserID: "@two:host", displayName: "Two", activeToolCount: 0)
        ])
    }
    
    // MARK: - B11: «+» never calls a failed read "no agents"
    
    @Test
    func interactivePostChoice_tellsAFailedReadFromNoAgents() {
        let agent = PersonalAgentSummary(id: "agent-1", matrixUserID: "@assistant-a:host", displayName: "A", avatarMXC: nil, visibility: "public", lifecycleState: "active")
        #expect(InteractivePostAgentChoice(.failure(.serverError(status: 503))) == .readFailed)
        #expect(InteractivePostAgentChoice(.success(.init(agents: [], provisioningStatus: .ready))) == .noAgents)
        #expect(InteractivePostAgentChoice(.success(.init(agents: [agent], provisioningStatus: .ready)))
            == .agents([AgentPickerItem(agentID: "agent-1", matrixUserID: "@assistant-a:host", displayName: "A", activeToolCount: 0)]))
    }
}
