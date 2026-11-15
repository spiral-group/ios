//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias AgentSpacesScreenViewModelType = StateStoreViewModelV2<AgentSpacesScreenViewState, AgentSpacesScreenViewAction>

class AgentSpacesScreenViewModel: AgentSpacesScreenViewModelType, AgentSpacesScreenViewModelProtocol {
    // AGENT-PLATFORM: platform sync (decision 289): the list renders from the
    // session's store and moves with the stream; a new space, agent or the
    // Personal space's provisioning comes as `agent.updated` / `space.updated`.
    private let store: AgentsStore
    /// S5: whether the list is on screen, and whether its rows changed while it was covered.
    private var visibility = ListVisibility.notYetShown
    private var changedWhileHidden = false

    private let actionsSubject: PassthroughSubject<AgentSpacesScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSpacesScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(userSession: UserSessionProtocol, store: AgentsStore) {
        self.store = store

        super.init(initialViewState: AgentSpacesScreenViewState(),
                   mediaProvider: userSession.mediaProvider)

        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(.spaces, by: self)

    }

    isolated deinit {
        store.stopShowing(.spaces, by: self)
    }

    // MARK: - Public

    override func process(viewAction: AgentSpacesScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            visibility = .visible
            // S5: a row that changed under a pushed screen may never load its new avatar (`LoadableImage` loads from
            // a `.task` that doesn't start off screen); the rows are made anew, from what is cached, as they show.
            if changedWhileHidden {
                changedWhileHidden = false
                state.listGeneration += 1
            }
            store.refresh(.spaces)
        case .disappeared:
            if visibility == .visible {
                visibility = .hidden
            }
        case .selectAgent(let agentID):
            for section in state.sections {
                if let card = section.agents.first(where: { $0.agentID == agentID }) {
                    actionsSubject.send(.selectAgent(.init(card: card,
                                                           companyName: section.summary.kind == .company ? section.summary.displayName : nil)))
                    return
                }
            }
        case .createCompany:
            guard SpiralFeatures.companySpaces else { return }
            actionsSubject.send(.showCreateCompany)
        case .createAgent(let orgID):
            guard let company = state.companies.first(where: { $0.orgID == orgID }) else { return }
            actionsSubject.send(.showCreateAgent(company))
        case .editCompany(let orgID):
            guard let detail = state.sections.first(where: { $0.id == orgID })?.detail, detail.kind == .company else { return }
            actionsSubject.send(.showEditCompany(detail))
        case .showNotifications:
            actionsSubject.send(.showNotifications)
        case .retry:
            reload()
        }
    }

    /// The person's own change (a company or agent made, an agent archived): read it now, before the stream says so.
    func reload() {
        Task { await store.reread(.spaces) }
    }

    // MARK: - Private

    private func render() {
        let listState = Self.listState(store.readState(.spaces, \.spaces))
        if state.listState != listState {
            state.listState = listState
            if visibility == .hidden {
                changedWhileHidden = true
            }
        }
        // The bell: what waits for the owner, as the session's badge reads it.
        let pending = store.needsAction?.count ?? 0
        if state.pendingApprovalsCount != pending {
            state.pendingApprovalsCount = pending
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
    }

    /// Each space in the directory's order (Personal first); one never read says so with a retry.
    private static func listState(_ read: AgentsReadState<AgentsSpaces>) -> AgentSpacesScreenListState {
        switch read {
        case .loading:
            return .loading
        case .failed:
            return .failure
        case .loaded(let spaces):
            if spaces.directory.spaces.isEmpty, spaces.directory.provisioningStatus == .inProgress {
                return .provisioning
            }
            return .loaded(spaces.directory.spaces.map { summary in
                AgentSpaceSection(summary: summary, content: spaces.details[summary.orgID].map { .loaded($0) } ?? .failed)
            })
        }
    }
}

/// S5: the list's place on screen. Before it first shows it is not hidden: its first rows are made as it shows anyway.
private enum ListVisibility {
    case notYetShown
    case visible
    /// Shown before and now covered: by a pushed screen, or another tab.
    case hidden
}
