//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// Brief 0041 D3 (ADR-0054) — the notifications hub replaces the
// ApprovalsInbox: one screen with a pinned "Needs action" section
// (pending approvals + verifications) above a
// chronological activity feed (terminal `agent_action_log` rows).

import Foundation

// MARK: - ViewModel → Coordinator actions

enum NotificationsHubScreenViewModelAction {
    /// Route to the approve/reject screen.
    case selectApproval(id: String)
    /// Route to the SAS verification decide screen.
    case selectVerification(id: String)
    /// A visitor's entry, when this device has the chat: open it.
    case openRoom(roomID: String)
    /// A visitor's entry otherwise: the assistant's «Общение с людьми».
    case showVisitorSettings(agent: AgentSpaceAgentCard)
}

// MARK: - View ↔ ViewModel state

/// Display DTO for one pinned needs-action row. Mapped from
/// `NeedsActionItem` (the service-layer union) so the view never
/// imports `AgentPlatformClient`.
struct NeedsActionListItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case approval
        case verification
    }

    /// Family-prefixed (`NeedsActionItem.id`) so ids never collide
    /// across families in one `ForEach`.
    let id: String
    let kind: Kind
    /// Raw family id used for detail routing.
    let subjectID: String
    /// Primary preview line (draft body / requester MXID),
    /// truncated at mapping time to keep cells two lines.
    let preview: String
    /// Optional secondary context (the target room by name / device id).
    let detail: String?
    let createdAt: Date
    /// Which agent asks; `nil` until the names are read, or for a verification.
    var agentName: String?
}

/// One entry an assistant kept about someone it doesn't answer (decisions
/// 194-196): «Новое сообщение» or «Пропущенный звонок», then who, then the
/// text. The name stands on its own line, so no language has to decline it.
struct VisitorMessageListItem: Identifiable, Equatable {
    let id: String
    let kind: VisitorMessage.Kind
    /// The person's display name, else their Matrix ID.
    let visitorName: String
    /// What they wrote; `nil` for a missed call.
    let body: String?
    let agentID: String
    let roomID: String
    let createdAt: Date
    var agentName: String?

    var title: String {
        switch kind {
        case .message: UntranslatedL10n.screenNotificationsHubVisitorNewMessage
        case .missedCall: UntranslatedL10n.screenNotificationsHubVisitorMissedCall
        case .other: UntranslatedL10n.screenNotificationsHubVisitorOther
        }
    }
}

/// State of the chronological activity feed. Same accumulate-pages
/// shape as `AgentActivityListState` (the cursor-pagination canon);
/// reuses `LoadMoreState` + `AgentActivityListItem` from that screen.
enum NotificationsActivityState: Equatable {
    case loading
    case loaded([AgentActivityListItem], loadMore: LoadMoreState)
    case failed
}

struct NotificationsHubScreenViewState: BindableState {
    /// Pinned section, from the session's store.
    var needsAction: [NeedsActionListItem] = []
    /// What waits has been read: before that the hub knows nothing, not «nothing».
    var isNeedsActionRead = false
    /// What waits could not be read and nothing of it is shown.
    var isNeedsActionFailed = false
    /// The rows name their agents once the spaces are read.
    var areAgentNamesRead = false
    /// What the assistants kept about people they don't answer.
    var visitorMessages: [VisitorMessageListItem] = []
    /// Chronological feed, every agent's (cursor pages in the store).
    var activityState: NotificationsActivityState = .loading
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?

    var activityItems: [AgentActivityListItem] {
        if case .loaded(let items, _) = activityState { return items }
        return []
    }

    /// The whole-screen empty state: nothing needs action AND the
    /// activity feed resolved empty-exhausted.
    var isEmpty: Bool {
        guard isNeedsActionRead, needsAction.isEmpty, visitorMessages.isEmpty else { return false }
        if case .loaded(let items, let loadMore) = activityState,
           items.isEmpty,
           case .exhausted = loadMore {
            return true
        }
        return false
    }

    /// Bottom sentinel for the activity feed; `nil` when hidden.
    var sentinel: LoadMoreState? {
        if case .loaded(let items, let loadMore) = activityState, !items.isEmpty {
            switch loadMore {
            case .exhausted: return nil
            default: return loadMore
            }
        }
        return nil
    }
}

// MARK: - View → ViewModel actions

enum NotificationsHubScreenViewAction {
    /// SwiftUI `.onAppear`: PUTs the last-seen marker.
    case appeared
    /// The error retry.
    case retry
    /// The bottom sentinel appeared — fetch the next activity page.
    case loadMore
    /// A pinned needs-action row was tapped.
    case selectNeedsAction(id: String)
    case selectVisitorMessage(id: String)
    /// «Убрать» on a visitor's entry.
    case dismissVisitorMessage(id: String)
}
