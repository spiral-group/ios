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

typealias AgentActivityScreenViewModelType = StateStoreViewModelV2<AgentActivityScreenViewState, AgentActivityScreenViewAction>

/// Drives `AgentActivityScreen`. Owner-visible audit timeline of
/// the agent's `agent_action_log` rows, fetched via
/// `GET /api/v1/agents/:id/activity` (Phase R3.5 E1, Brief 0002).
///
/// ### Cursor pagination
///
/// First slice on iOS to do real cursor pagination — sibling
/// `VerificationsListScreen` is single-page, `ApprovalsListScreen`
/// uses SSE. The pattern that landed here:
///
/// 1. `.appeared` / `.retry` / `.selectFilter` → first-page fetch
///    (clears any accumulated items first).
/// 2. The View renders a sentinel row at the bottom whenever
///    `.loaded`'s `LoadMoreState` is `.idle` or `.failed`. Its
///    `.onAppear` posts `.loadMore` which fetches the next page
///    and **appends** the items (preserving scroll position).
/// 3. `nextCursor == nil` on a response transitions `LoadMoreState`
///    to `.exhausted`, hiding the sentinel.
///
/// ### Race protection
///
/// Filter changes mid-fetch are common in real usage. The
/// `loadGeneration` counter tracks the most recent intent: any
/// completed fetch whose generation doesn't match the current
/// one is discarded (silently — the in-flight fetch was already
/// outdated when filter changed).
class AgentActivityScreenViewModel: AgentActivityScreenViewModelType, AgentActivityScreenViewModelProtocol {
    private let agentID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol
    private let clientProxy: any ClientProxyProtocol

    /// Default page size. Matches backend's default + the
    /// approvals/voice-sessions list endpoints' `25` for
    /// consistency.
    static let defaultPageSize = 25

    /// Monotonic counter incremented on every operation that
    /// invalidates in-flight fetches (filter change, retry).
    /// Completed fetches compare their captured generation
    /// against the current one and bail if stale.
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<AgentActivityScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentActivityScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(agentID: String,
         initialFilter: ActionOutcomeFilter = .all,
         agentPlatformService: any AgentPlatformServiceProtocol,
         clientProxy: any ClientProxyProtocol) {
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        super.init(initialViewState: AgentActivityScreenViewState(filter: initialFilter, bindings: AgentActivityScreenViewStateBindings()))
    }

    // MARK: - Public

    override func process(viewAction: AgentActivityScreenViewAction) {
        MXLog.info("AgentActivityScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Skip refetch only if a prior load already
            // succeeded with at least one item; on `.failed` /
            // fresh `.loading` we always refetch. (We never
            // re-arm on empty `.loaded` either — that's the
            // "no activity yet" terminal which doesn't change
            // until the agent produces traffic; user can
            // pull-to-refresh.)
            if case .loaded(let items, _) = state.listState, !items.isEmpty {
                return
            }
            Task { await loadFirstPage() }
        case .retry:
            Task { await loadFirstPage() }
        case .loadMore:
            // Sentinel `.onAppear` can fire twice in quick
            // succession when SwiftUI's diffing rebuilds the
            // bottom row. Guard against double-fetch by
            // requiring an `.idle` or `.failed` sentinel.
            guard case .loaded(let items, let loadMore) = state.listState else { return }
            switch loadMore {
            case .idle(let cursor), .failed(let cursor):
                Task { await loadNextPage(currentItems: items, cursor: cursor) }
            case .loading, .exhausted:
                return
            }
        case .selectFilter(let filter):
            guard filter != state.filter else { return }
            state.filter = filter
            Task { await loadFirstPage() }
        case .selectItem(let id):
            guard let item = state.items.first(where: { $0.id == id }) else { return }
            if let approvalID = item.approvalID {
                actionsSubject.send(.openApproval(approvalID: approvalID))
            } else if let roomID = item.roomID {
                actionsSubject.send(.openRoom(roomID: roomID))
            }
        }
    }

    // MARK: - Private

    /// Fetch the first page. Always clears accumulated items
    /// before the request fires so the loading skeleton renders
    /// even when the user already had data on screen (pull-to-
    /// refresh, filter change).
    private func loadFirstPage() async {
        loadGeneration += 1
        let generation = loadGeneration
        state.listState = .loading

        let result = await agentPlatformService.listAgentActivity(agentID: agentID,
                                                                  filter: state.filter,
                                                                  cursor: nil,
                                                                  limit: Self.defaultPageSize)

        // Stale-fetch guard: if filter changed (or retry fired)
        // while this request was in flight, drop the response on
        // the floor — a fresh fetch is already running.
        guard generation == loadGeneration else {
            MXLog.info("AgentActivityScreenViewModel: dropping stale first-page response (gen=\(generation), current=\(loadGeneration))")
            return
        }

        switch result {
        case .success(let page):
            let mapped = page.items.map { Self.mapItem($0, clientProxy: clientProxy) }
            state.listState = .loaded(mapped, loadMore: Self.makeLoadMoreState(from: page.nextCursor))
            MXLog.info("Loaded \(mapped.count) activity entries for agent \(agentID); next_cursor=\(page.nextCursor != nil ? "present" : "exhausted")")
        case .failure(let error):
            MXLog.error("Failed to load agent activity: \(error)")
            state.listState = .failed
            state.bindings.alertInfo = AlertInfo(id: .loadFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadFirstPage() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    /// Append a continuation page to the accumulated items. Does
    /// NOT clear anything on failure — the previous items stay on
    /// screen and the sentinel flips to `.failed(cursor:)` so the
    /// user can retry without losing place.
    private func loadNextPage(currentItems: [AgentActivityListItem], cursor: String) async {
        // Mark sentinel as loading BEFORE awaiting so the user
        // sees the spinner immediately.
        state.listState = .loaded(currentItems, loadMore: .loading)
        let generation = loadGeneration

        let result = await agentPlatformService.listAgentActivity(agentID: agentID,
                                                                  filter: state.filter,
                                                                  cursor: cursor,
                                                                  limit: Self.defaultPageSize)

        // Race-guard: a filter change mid-paginate invalidates
        // this fetch. The first-page fetch that filter change
        // queued is already in flight; let it take over.
        guard generation == loadGeneration else {
            MXLog.info("AgentActivityScreenViewModel: dropping stale next-page response (gen=\(generation), current=\(loadGeneration))")
            return
        }

        switch result {
        case .success(let page):
            let mapped = page.items.map { Self.mapItem($0, clientProxy: clientProxy) }
            let combined = currentItems + mapped
            state.listState = .loaded(combined, loadMore: Self.makeLoadMoreState(from: page.nextCursor))
            MXLog.info("Appended \(mapped.count) activity entries for agent \(agentID); total=\(combined.count)")
        case .failure(let error):
            MXLog.error("Failed to load activity continuation page: \(error)")
            // Preserve the cursor on failure so the sentinel's
            // retry tap can reuse it.
            state.listState = .loaded(currentItems, loadMore: .failed(cursor: cursor))
        }
    }

    /// Wire the per-row preview shape. Defined as a static so
    /// preview providers + tests can synthesise items without
    /// instantiating a full ViewModel.
    static func mapItem(_ entry: AgentActivityEntry, clientProxy: any ClientProxyProtocol) -> AgentActivityListItem {
        AgentActivityListItem(id: entry.id,
                              capabilityName: entry.capabilityName,
                              policyDecision: entry.policyDecision,
                              outcome: entry.outcome,
                              title: AgentActivityLabels.action(forCapability: entry.capabilityName),
                              reason: AgentActivityLabels.reason(forPolicyReason: entry.policyReason, capabilityName: entry.capabilityName),
                              roomName: AgentRoomLabel.text(for: entry.roomID, clientProxy: clientProxy),
                              createdAt: entry.createdAt,
                              // Only a chat this device has opens; a visitor's chat
                              // with the agent, which the owner isn't in, doesn't.
                              roomID: entry.roomID.flatMap { clientProxy.roomSummaryForIdentifier($0) != nil ? $0 : nil },
                              approvalID: entry.approvalID,
                              agentID: entry.agentID)
    }

    /// Translate the wire `nextCursor` into a sentinel state.
    /// `nil` → `.exhausted` (no more rows); otherwise `.idle`
    /// carrying the cursor for the next `.loadMore` action.
    private static func makeLoadMoreState(from nextCursor: String?) -> LoadMoreState {
        if let cursor = nextCursor { return .idle(cursor: cursor) }
        return .exhausted
    }
}
