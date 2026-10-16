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
@testable import ElementX
import Foundation
import Testing

@MainActor
struct PublicProfileScreenViewModelTests {
    // MARK: - Self-lookup short-circuit

    @Test
    func appearedAction_selfLookupShortCircuitsBeforeFetch() async throws {
        let service = AgentPlatformServiceMock()
        // Wire a return value so we can prove the service was NOT
        // consulted (count must stay 0).
        service.fetchUserProfileMxidReturnValue = .success(Self.sampleProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@alice:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .selfLookup = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(service.fetchUserProfileMxidCallsCount == 0)
    }

    @Test
    func appearedAction_selfLookupMatchesCaseInsensitive() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .success(Self.sampleProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@Alice:spiral.md",
                                                     currentUserMXID: "@alice:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .selfLookup = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(service.fetchUserProfileMxidCallsCount == 0)
    }

    // MARK: - Loading path

    @Test
    func appearedAction_fetchesProfileAndLandsOnLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .success(Self.sampleProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        if case .loaded(let profile) = viewModel.context.viewState.detailState {
            #expect(profile.mxid == "@alice:spiral.md")
            #expect(profile.publicAgents.count == 1)
            #expect(service.fetchUserProfileMxidReceivedMxid == "@alice:spiral.md")
        } else {
            Issue.record("Expected .loaded, got \(viewModel.context.viewState.detailState)")
        }
    }

    @Test
    func appearedAction_emptyAgentsRenderAsLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .success(Self.emptyProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@charlie:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        if case .loaded(let profile) = viewModel.context.viewState.detailState {
            #expect(profile.publicAgents.isEmpty)
        } else {
            Issue.record("Expected .loaded with empty agents, got \(viewModel.context.viewState.detailState)")
        }
    }

    // MARK: - Error paths

    @Test
    func appearedAction_notFoundMapsToNotFound() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .failure(.notFound)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@ghost:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .notFound = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        // No alert for .notFound — distinct UX from transport
        // failure, see PublicProfileScreen.notFoundSection.
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }

    @Test
    func appearedAction_transportFailureSurfacesFailedStateAndAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .failure(.serverError(status: 500))

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    // MARK: - Refresh path

    @Test
    func refreshAction_refetchesEvenAfterTerminalFetchFailure() async throws {
        let service = AgentPlatformServiceMock()
        // First call: fail. Refresh: succeed.
        var hits = 0
        service.fetchUserProfileMxidClosure = { _ in
            hits += 1
            if hits == 1 {
                return .failure(.serverError(status: 500))
            }
            return .success(Self.sampleProfile)
        }

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let failedDeferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await failedDeferred.fulfill()

        let loadedDeferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .refresh)
        try await loadedDeferred.fulfill()

        #expect(hits == 2)
    }

    // MARK: - Coordinator actions

    @Test
    func contactAgentAction_emitsCoordinatorAction() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .success(Self.sampleProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .contactAgent(let mxid) = action {
                return mxid == "@assistant-alice:spiral.md"
            }
            return false
        }
        viewModel.context.send(viewAction: .contactAgent(matrixUserID: "@assistant-alice:spiral.md"))
        try await deferred.fulfill()
    }

    @Test
    func dismissAction_emitsDismissedAction() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchUserProfileMxidReturnValue = .success(Self.sampleProfile)

        let viewModel = PublicProfileScreenViewModel(targetMXID: "@alice:spiral.md",
                                                     currentUserMXID: "@viewer:spiral.md",
                                                     agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .dismiss)
        try await deferred.fulfill()
    }

    // MARK: - Pure helpers

    @Test
    func isSameUser_isCaseInsensitiveAndTrimsWhitespace() {
        #expect(PublicProfileScreenViewModel.isSameUser(lhs: "@alice:host", rhs: "@ALICE:host"))
        #expect(PublicProfileScreenViewModel.isSameUser(lhs: "  @alice:host\n", rhs: "@alice:host"))
        #expect(!PublicProfileScreenViewModel.isSameUser(lhs: "@alice:host", rhs: "@bob:host"))
    }

    // MARK: - Fixtures

    static let sampleProfile = UserProfileView(mxid: "@alice:spiral.md",
                                               displayName: "Alice",
                                               publicAgents: [
                                                   PublicAgentSummary(id: "agent-1",
                                                                      matrixUserID: "@assistant-alice:spiral.md",
                                                                      displayName: "Alice's assistant",
                                                                      tone: "warm",
                                                                      greeting: "Hi! I'm Alice's assistant.",
                                                                      visitorGreeting: "Alice is offline — I'll relay.",
                                                                      createdAt: Date())
                                               ])

    static let emptyProfile = UserProfileView(mxid: "@charlie:spiral.md",
                                              displayName: "Charlie",
                                              publicAgents: [])
}
