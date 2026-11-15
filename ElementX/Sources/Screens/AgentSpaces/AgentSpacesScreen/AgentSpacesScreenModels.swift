//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SpiralComponents

// AGENT-PLATFORM: Brief 0037, reworked by the Agents tab step B (decision
// 191): the tab root is one list, a section per space (Personal first, then
// the companies) with the agents straight inside it.

enum AgentSpacesScreenViewModelAction {
    case selectAgent(AgentSelection)
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
    var listState: AgentSpacesScreenListState = .loading
    /// What waits for the owner, for the nav-bar bell badge (`AgentsStore`).
    var pendingApprovalsCount = 0
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?
    /// S5: moves when the list comes back into view after its rows changed while it was covered; the list's
    /// identity, so its rows are made anew and load what changed.
    var listGeneration = 0

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
    /// The tab came into view: its selection, or the way back from a screen on top.
    case appeared
    /// The tab went out of view: a pushed screen covers it, or another tab took its place.
    case disappeared
    case selectAgent(agentID: String)
    case createCompany
    case createAgent(orgID: String)
    case editCompany(orgID: String)
    case showNotifications
    /// Read again after a failure, or a space that could not be read.
    case retry
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

    /// What the agent is, on its row and on its page.
    var roleLine: String? {
        isPersonalAssistant ? UntranslatedL10n.screenAgentDetailKindPersonalAssistant : localizedRole
    }

    /// The card's status, on the Agents tab and on the agent's own screen: online unless paused or no longer
    /// active, as everywhere else an agent shows. Paused before online: a paused agent answers nobody. `isPaused`
    /// is for a screen that has read the agent since this card was listed.
    func presence(isPaused: Bool? = nil) -> SpiralAgentStatus? {
        if isPaused ?? self.isPaused {
            return .paused(UntranslatedL10n.screenAgentsPaused)
        }
        return lifecycleState == "active" ? .online(UntranslatedL10n.screenAgentSpaceAgentPresenceOnline) : nil
    }

    var chatsAndTools: String {
        [UntranslatedL10n.screenAgentsChatCount(roomCount), UntranslatedL10n.screenAgentsToolCount(activeToolCount)].joined(separator: " · ")
    }

    /// A row's line of facts. A role says what a role agent does; the assistant, and an agent of a kind this build
    /// doesn't know, have their chats and tools instead.
    var rowFacts: String? {
        localizedRole == nil ? chatsAndTools : nil
    }
}
