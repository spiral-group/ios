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

@testable import ElementX
import Foundation
import Testing

@MainActor
struct ToolMemberPickerScreenViewModelTests {
    @Test
    func projectMembers_dropsInactiveAndAgentAndSorts() {
        let members: [RoomMemberProxyProtocol] = [
            Self.member("@charlie:host", name: "Charlie", isActive: true),
            Self.member("@alice:host", name: "Alice", isActive: true),
            Self.member("@agent:host", name: "Agent", isActive: true),
            Self.member("@left:host", name: "Gone", isActive: false)
        ]

        let items = ToolMemberPickerScreenViewModel.projectMembers(members, excluding: "@agent:host", ownUserID: "@owner:host")

        #expect(items.map(\.userID) == ["@alice:host", "@charlie:host"])
    }

    /// Re-walk R4: the picker listed the agent whose tool was being armed
    /// («…'s Assistant, Already a member»). No platform agent is a person a
    /// tool can be scoped to — this server's agents are left out even when
    /// the form couldn't name its own; another server's `@assistant-…` is a
    /// person.
    @Test
    func projectMembers_dropsThisServersAgents() {
        let members: [RoomMemberProxyProtocol] = [
            Self.member("@alice:host", name: "Alice", isActive: true),
            Self.member("@assistant-owner:host", name: "Owner's Assistant", isActive: true),
            Self.member("@agent-acme-sales:host", name: "Acme Sales", isActive: true),
            Self.member("@assistant-bob:elsewhere", name: "Bob", isActive: true)
        ]

        let items = ToolMemberPickerScreenViewModel.projectMembers(members, excluding: nil, ownUserID: "@owner:host")

        #expect(items.map(\.userID) == ["@alice:host", "@assistant-bob:elsewhere"])
    }

    @Test
    func toggleMember_addsThenRemoves() async throws {
        let viewModel = Self.makeViewModel(preselected: [])
        viewModel.context.send(viewAction: .toggleMember(userID: "@bob:host"))
        #expect(viewModel.context.viewState.isSelected("@bob:host"))
        viewModel.context.send(viewAction: .toggleMember(userID: "@bob:host"))
        #expect(!viewModel.context.viewState.isSelected("@bob:host"))
    }

    @Test
    func preselectedMembers_areTicked() {
        let viewModel = Self.makeViewModel(preselected: ["@alice:host"])
        #expect(viewModel.context.viewState.isSelected("@alice:host"))
        #expect(viewModel.context.viewState.selectionCount == 1)
    }

    @Test
    func canConfirm_requiresAtLeastOneMember() {
        let viewModel = Self.makeViewModel(preselected: [])
        #expect(!viewModel.context.viewState.canConfirm)
        viewModel.context.send(viewAction: .toggleMember(userID: "@bob:host"))
        #expect(viewModel.context.viewState.canConfirm)
    }

    @Test
    func confirm_emitsSelectedMembers() async throws {
        let viewModel = Self.makeViewModel(preselected: ["@alice:host"])
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .confirm(let members) = action { return members == ["@alice:host"] }
            return false
        }
        viewModel.context.send(viewAction: .confirm)
        try await deferred.fulfill()
    }

    @Test
    func searchQuery_filtersByNameOrMXID() async throws {
        let viewModel = Self.makeViewModel(preselected: [],
                                           members: [Self.member("@alice:host", name: "Alice", isActive: true),
                                                     Self.member("@bob:host", name: "Bob", isActive: true)])
        // Let the members publisher populate.
        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        viewModel.context.searchQuery = "ali"
        #expect(viewModel.context.viewState.visibleMembers.map(\.userID) == ["@alice:host"])

        viewModel.context.searchQuery = "@bob"
        #expect(viewModel.context.viewState.visibleMembers.map(\.userID) == ["@bob:host"])
    }

    // MARK: - Helpers

    private static func member(_ userID: String, name: String, isActive: Bool) -> RoomMemberProxyMock {
        RoomMemberProxyMock(with: .init(userID: userID, displayName: name, membership: isActive ? .join : .leave))
    }

    private static func makeViewModel(preselected: [String],
                                      members: [RoomMemberProxyMock] = .allMembers) -> ToolMemberPickerScreenViewModel {
        ToolMemberPickerScreenViewModel(roomProxy: JoinedRoomProxyMock(.init(members: members)),
                                        agentMatrixUserID: nil,
                                        preselectedMemberIDs: preselected)
    }
}
