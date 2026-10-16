//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The room-member multi-select reached from a
// member-carrying audience scope in `ArmToolScreen` ("Specific people…" /
// "Everyone except…"). Sources candidates from the room's own members
// (`roomProxy.membersPublisher`) — this is a within-room selection, so
// unlike `InviteUsersScreen` it needs no user-directory discovery.
//
// Returns the chosen MXIDs to the arm form, which folds them into the
// typed `AudienceScope` (`specific_senders` / `everyone_except`).
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum ToolMemberPickerScreenViewModelAction {
    /// User confirmed a selection — carries the chosen MXIDs.
    case confirm(members: [String])
}

// MARK: - Domain

/// One selectable room member, projected from a `RoomMemberProxyProtocol`.
struct ToolMemberPickerItem: Equatable, Identifiable {
    var id: String { userID }
    let userID: String
    let displayName: String?
    let avatarURL: URL?
}

// MARK: - View ↔ ViewModel state

enum ToolMemberPickerListState: Equatable {
    case loading
    case loaded(members: [ToolMemberPickerItem])
}

struct ToolMemberPickerScreenViewState: BindableState {
    var listState: ToolMemberPickerListState = .loading
    var bindings: ToolMemberPickerScreenViewStateBindings

    /// Members matching the current search query, or all when empty.
    var visibleMembers: [ToolMemberPickerItem] {
        guard case .loaded(let members) = listState else { return [] }
        let query = bindings.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return members }
        return members.filter {
            ($0.displayName?.lowercased().contains(query) ?? false) || $0.userID.lowercased().contains(query)
        }
    }

    func isSelected(_ userID: String) -> Bool {
        bindings.selectedMemberIDs.contains(userID)
    }

    var selectionCount: Int { bindings.selectedMemberIDs.count }

    /// A member-carrying scope requires at least one member.
    var canConfirm: Bool { !bindings.selectedMemberIDs.isEmpty }

    var isLoading: Bool {
        if case .loading = listState { return true }
        return false
    }
}

struct ToolMemberPickerScreenViewStateBindings {
    var searchQuery = ""
    /// Insertion-ordered so the confirmed list is stable; a Set drives
    /// the row checkmarks.
    var selectedMemberIDs: [String] = []
}

// MARK: - View → ViewModel actions

enum ToolMemberPickerScreenViewAction {
    case appeared
    /// Toggle a member in/out of the selection.
    case toggleMember(userID: String)
    /// Confirm the current selection.
    case confirm
}
