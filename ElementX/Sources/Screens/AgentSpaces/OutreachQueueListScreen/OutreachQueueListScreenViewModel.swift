//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.

import Combine
import SwiftUI

typealias OutreachQueueListScreenViewModelType = StateStoreViewModelV2<OutreachQueueListScreenViewState, OutreachQueueListScreenViewAction>

/// Drives `OutreachQueueListScreen`. Fetches the outreach
/// queue for one agent on `.appeared`; supports a status
/// filter via toolbar menu picker (`.all` → no `?status=`
/// query param, otherwise pass the wire tag).
///
/// ### Filter changes drive a fresh fetch
///
/// We could filter the in-memory `[OutreachQueueEntry]` list
/// client-side, but two reasons we re-fetch from the backend
/// instead:
///
/// * The queue can be long (up to 500 rows). Server-side
///   filtering is cheaper than streaming everything to the
///   client.
/// * Status transitions happen on the backend (outreach
///   worker flips `queued → pending_approval → sent`); a
///   filter-change is also a natural "refresh me" trigger.
///
/// ### Per-filter race protection
///
/// Mirrors `AgentActivityScreenViewModel`'s monotonic
/// `loadGeneration` counter so a quick filter toggle that
/// races mid-fetch discards the stale response. The S170
/// LEARNING entry "list-screens with mutable filters need a
/// monotonic generation guard" applies here too.
class OutreachQueueListScreenViewModel: OutreachQueueListScreenViewModelType, OutreachQueueListScreenViewModelProtocol {
    private let agentID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol

    private var loadGeneration: UInt = 0

    private let actionsSubject: PassthroughSubject<OutreachQueueListScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<OutreachQueueListScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(agentID: String,
         agentPlatformService: any AgentPlatformServiceProtocol,
         initialState: OutreachQueueListState = .loading,
         initialFilter: OutreachTargetStatus? = nil) {
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        let bindings = OutreachQueueListScreenViewStateBindings()
        var initial = OutreachQueueListScreenViewState(agentID: agentID, bindings: bindings)
        initial.listState = initialState
        initial.statusFilter = initialFilter
        super.init(initialViewState: initial)
    }

    override func process(viewAction: OutreachQueueListScreenViewAction) {
        MXLog.info("OutreachQueueListScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Walk F4: back from Add targets (or anywhere) the
            // queue may have changed, so it is read again; rows
            // already shown stay until the answer replaces them.
            Task { await load(keepingRows: true) }
        case .refresh:
            Task { await load() }
        case .selectFilter(let filter):
            // Filter change always triggers a fresh fetch.
            // Stale loaded data flickers briefly into skeleton
            // — acceptable trade-off for "user changed intent,
            // show them the right rows".
            state.statusFilter = filter
            Task { await load() }
        case .openAddTargets:
            actionsSubject.send(.openAddTargets)
        case .dismiss:
            actionsSubject.send(.dismissed)
        }
    }

    private func load(keepingRows: Bool = false) async {
        loadGeneration &+= 1
        let myGeneration = loadGeneration
        let isShowingRows = if case .loaded = state.listState { true } else { false }
        let keepsRows = keepingRows && isShowingRows
        if !keepsRows {
            state.listState = .loading
        }

        let filter = state.statusFilter
        let result = await agentPlatformService.listOutreachQueue(agentID: agentID,
                                                                  status: filter,
                                                                  limit: 100)
        // Stale-generation guard.
        guard myGeneration == loadGeneration else { return }

        switch result {
        case .success(let entries):
            state.listState = .loaded(entries)
        case .failure(let error):
            switch error {
            case .conflict(let detail):
                state.listState = .unavailable(reason: detail)
            case .notFound:
                state.listState = .unavailable(reason: "agent not found")
            default:
                MXLog.error("OutreachQueueListScreenViewModel: load failed: \(error)")
                // The rows shown are older, not wrong: they stay, the alert says the read failed.
                if !keepsRows {
                    state.listState = .failed(reason: error.description)
                }
                state.bindings.alertInfo = AlertInfo(id: .fetchFailed,
                                                     title: L10n.commonError,
                                                     message: L10n.errorUnknown,
                                                     primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                         Task { await self?.load() }
                                                     },
                                                     secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
            }
        }
    }
}
