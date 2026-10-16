//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM: Brief 0037, reworked by the Agents tab step B (decision
// 191): the tab root is one list, a section per space (Personal first, then
// the companies) with the agents straight inside it.

enum AgentSpacesScreenViewModelAction {
    case selectAgent(AgentSelection)
    case showSettings
    case showCreateCompany
    /// A new role agent inside this company.
    case showCreateAgent(AgentSpaceSummary)
    case showEditCompany(AgentSpaceDetail)
    case showNotifications
}

/// An agent as the tab hands it to its screen: the card plus the company it
/// works for, which the agent screen names («Продажи · Кофейня Зерно»).
struct AgentSelection: Equatable {
    let card: AgentSpaceAgentCard
    /// The company's name; `nil` in the Personal space.
    let companyName: String?
}

struct AgentSpacesScreenViewState: BindableState {
    let userID: String
    var userDisplayName: String?
    var userAvatarURL: URL?

    var listState: AgentSpacesScreenListState = .loading
    /// Pending-approvals count for the nav-bar bell badge — mirrored from
    /// `ApprovalsStreamService`.
    var pendingApprovalsCount = 0

    var sections: [AgentSpaceSection] {
        if case .loaded(let sections) = listState { return sections }
        return []
    }

    /// The companies a new role agent can join, for «+» → «Новый агент».
    var companies: [AgentSpaceSummary] {
        sections.map(\.summary).filter { $0.kind == .company }
    }

    /// A ready directory with no space in it: the Personal space hasn't
    /// landed yet, which the list says instead of showing nothing.
    var hasNoSpaces: Bool {
        if case .loaded(let sections) = listState { return sections.isEmpty }
        return false
    }
}

/// One space and what was read of it. A space whose read failed says so
/// with a retry: it is not a space without agents.
struct AgentSpaceSection: Equatable, Identifiable {
    enum Content: Equatable {
        case loaded(AgentSpaceDetail)
        case failed
    }

    let summary: AgentSpaceSummary
    let content: Content

    var id: String {
        summary.orgID
    }

    var agents: [AgentSpaceAgentCard] {
        guard case .loaded(let detail) = content else { return [] }
        return detail.agents.filter { $0.lifecycleState != "archived" }
    }

    var detail: AgentSpaceDetail? {
        if case .loaded(let detail) = content { return detail }
        return nil
    }

    /// The Personal space read fine but its assistant isn't there yet.
    var isAssistantPending: Bool {
        summary.kind == .solo && detail != nil && agents.isEmpty
    }
}

/// The REST-backed list needs explicit loading / failure states —
/// unlike `SpacesScreen`, whose spaces arrive via an SDK publisher.
enum AgentSpacesScreenListState: Equatable {
    case loading
    /// The personal-agent reconcile worker is still provisioning the
    /// owner's Personal space; show a hint instead of an empty list.
    case provisioning
    case loaded([AgentSpaceSection])
    case failure
}

enum AgentSpacesScreenViewAction {
    case selectAgent(agentID: String)
    case showSettings
    case createCompany
    case createAgent(orgID: String)
    case editCompany(orgID: String)
    case showNotifications
    /// Full retry after a failure — flips back to `.loading` first.
    case retry
    /// Silent pull-to-refresh — keeps the current list on screen.
    case refresh
    /// The list is on screen again; it is read again, rows kept meanwhile.
    case appeared
}

extension AgentSpaceAgentCard {
    /// A company agent's role in the app's words; `nil` for the personal
    /// assistant and for a role this build doesn't know.
    var localizedRole: String? {
        switch kind {
        case "sales": UntranslatedL10n.screenCreateAgentRoleSales
        case "outreach": UntranslatedL10n.screenCreateAgentRoleOutreach
        case "support": UntranslatedL10n.screenCreateAgentRoleSupport
        default: nil
        }
    }

    /// The row's one line: a role agent's role, the assistant's chats and
    /// tools, after «В сети» when it is. Offline adds nothing (see
    /// `AgentNameWithPresence`).
    var rowSubtitle: String {
        if isPaused {
            return [localizedRole, UntranslatedL10n.screenAgentsPaused].compactMap(\.self).joined(separator: " · ")
        }
        let online = presence == .online ? UntranslatedL10n.screenAgentSpaceAgentPresenceOnline : nil
        if let role = localizedRole {
            return [role, online].compactMap(\.self).joined(separator: " · ")
        }
        return [online,
                UntranslatedL10n.screenAgentsChatCount(roomCount),
                UntranslatedL10n.screenAgentsToolCount(activeToolCount)].compactMap(\.self).joined(separator: " · ")
    }
}
