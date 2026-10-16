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

typealias NotificationsHubScreenViewModelType = StateStoreViewModelV2<NotificationsHubScreenViewState, NotificationsHubScreenViewAction>

/// Drives `NotificationsHubScreen` (Brief 0041 D3, ADR-0054).
///
/// Two data planes:
///
/// 1. **Needs action** — mirrored live from the UserSession-scoped
///    `ApprovalsStreamServiceProtocol` via `withObservationTracking`
///    (same Combine-free bridge the retired ApprovalsInbox used).
///    The service reseeds itself on every SSE frame, so decided
///    items drop off this section without any pull.
/// 2. **Activity** — cursor-paginated pages of
///    `GET /api/v1/me/notifications` owned by this ViewModel
///    (the AgentActivityScreen pagination canon: LoadMoreState
///    sentinel + `loadGeneration` stale-fetch guard).
///
/// On `.appeared` the ViewModel also PUTs the last-seen marker via
/// `markSeen()` — opening the hub IS the "I saw these" gesture
/// (decision 8, Instagram-style).
class NotificationsHubScreenViewModel: NotificationsHubScreenViewModelType, NotificationsHubScreenViewModelProtocol {
    private let approvalsStreamService: any ApprovalsStreamServiceProtocol
    private let agentPlatformService: any AgentPlatformServiceProtocol
    private let clientProxy: any ClientProxyProtocol
    private let userIndicatorController: any UserIndicatorControllerProtocol
    /// Display names of the people pending cards are about, as their profiles come in.
    private var counterpartNames: [String: String] = [:]
    private var counterpartLookups: Set<String> = []
    /// The owner's agents by id, so each row names its agent (step B.9) and
    /// a visitor's entry can open its assistant's settings.
    private var agentCards: [String: AgentSpaceAgentCard] = [:]
    private var agentNames: [String: String] {
        agentCards.mapValues(\.displayName)
    }
    /// The visitors' entries as the server last sent them; the rows are these, named.
    private var visitorEntries: [VisitorMessage] = []
    private var isLoadingAgentNames = false

    static let defaultPageSize = 25

    /// Monotonic counter guarding in-flight activity fetches
    /// against retry races (see AgentActivityScreenViewModel).
    private var loadGeneration: UInt64 = 0

    private let actionsSubject: PassthroughSubject<NotificationsHubScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<NotificationsHubScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(approvalsStreamService: any ApprovalsStreamServiceProtocol,
         agentPlatformService: any AgentPlatformServiceProtocol,
         clientProxy: any ClientProxyProtocol,
         userIndicatorController: any UserIndicatorControllerProtocol) {
        self.approvalsStreamService = approvalsStreamService
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: NotificationsHubScreenViewState(bindings: NotificationsHubScreenViewStateBindings()))

        refreshFromService()
        rearmObservation()
    }

    // MARK: - Public

    override func process(viewAction: NotificationsHubScreenViewAction) {
        MXLog.info("NotificationsHubScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            if agentCards.isEmpty {
                Task { await loadAgentNames() }
            }
            approvalsStreamService.connect()
            Task { await approvalsStreamService.reseed() }
            // Opening the hub is the "seen" gesture — clear the
            // unseen badge (optimistic local zero + monotonic PUT).
            Task { await approvalsStreamService.markSeen() }
            if case .loaded(let items, _) = state.activityState, !items.isEmpty {
                return
            }
            Task { await loadFirstPage() }
        case .retry:
            Task { await approvalsStreamService.reseed() }
            Task { await loadFirstPage() }
        case .loadMore:
            guard case .loaded(let items, let loadMore) = state.activityState else { return }
            switch loadMore {
            case .idle(let cursor), .failed(let cursor):
                Task { await loadNextPage(currentItems: items, cursor: cursor) }
            case .loading, .exhausted:
                return
            }
        case .selectNeedsAction(let id):
            guard let item = state.needsAction.first(where: { $0.id == id }) else { return }
            switch item.kind {
            case .approval:
                actionsSubject.send(.selectApproval(id: item.subjectID))
            case .verification:
                actionsSubject.send(.selectVerification(id: item.subjectID))
            }
        case .selectVisitorMessage(let id):
            guard let entry = visitorEntries.first(where: { $0.id == id }) else { return }
            Task { await open(entry) }
        case .dismissVisitorMessage(let id):
            Task { await dismissVisitorMessage(id: id) }
        }
    }

    // MARK: - Visitors' entries

    /// The chat when this device has it, else the assistant's «Общение с людьми».
    private func open(_ entry: VisitorMessage) async {
        if case .joined = await clientProxy.roomForIdentifier(entry.roomID) {
            actionsSubject.send(.openRoom(roomID: entry.roomID))
            return
        }
        if agentCards[entry.agentID] == nil {
            await loadAgentNames()
        }
        guard let agent = agentCards[entry.agentID] else {
            MXLog.error("No agent \(entry.agentID) among the owner's spaces for a visitor's entry")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: L10n.errorUnknown, icon: \.error))
            return
        }
        actionsSubject.send(.showVisitorSettings(agent: agent))
    }

    /// Gone from the list at once; back where it was when the server refuses.
    /// One already gone there (dismissed elsewhere, past its 30 days) stays gone.
    private func dismissVisitorMessage(id: String) async {
        guard let index = visitorEntries.firstIndex(where: { $0.id == id }) else { return }
        let entry = visitorEntries.remove(at: index)
        refreshVisitorMessages()

        switch await agentPlatformService.dismissVisitorMessage(id: id) {
        case .success, .failure(.notFound):
            MXLog.info("Dismissed a visitor's entry")
        case .failure(let error):
            MXLog.error("Failed to dismiss a visitor's entry: \(error)")
            visitorEntries.insert(entry, at: min(index, visitorEntries.count))
            refreshVisitorMessages()
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenNotificationsHubVisitorDismissFailed,
                                                                  icon: \.error))
        }
    }

    private func refreshVisitorMessages() {
        state.visitorMessages = visitorEntries.map { entry in
            VisitorMessageListItem(id: entry.id,
                                   kind: entry.kind,
                                   visitorName: counterpartNames[entry.visitorMXID] ?? entry.visitorMXID,
                                   body: Self.visitorBody(entry),
                                   agentID: entry.agentID,
                                   roomID: entry.roomID,
                                   createdAt: entry.createdAt,
                                   agentName: agentNames[entry.agentID])
        }
    }

    // MARK: - Needs-action mirror

    private func rearmObservation() {
        let service = approvalsStreamService
        withObservationTracking {
            _ = service.needsAction
            _ = service.connectionState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                refreshFromService()
                rearmObservation()
            }
        }
    }

    private func refreshFromService() {
        state.needsAction = approvalsStreamService.needsAction.map {
            Self.mapNeedsActionItem($0, clientProxy: clientProxy, counterpartNames: counterpartNames, agentNames: agentNames)
        }
        lookUpCounterparts()

        switch approvalsStreamService.connectionState {
        case .connected, .disconnected:
            state.connectionIndicator = .hidden
        case .connecting:
            state.connectionIndicator = .connecting
        case .reconnecting(let attempt):
            state.connectionIndicator = .reconnecting(attempt: attempt)
        case .failed(let reason):
            state.connectionIndicator = .failed(reason: reason)
        }
    }

    /// A card says whom it is about, so two pending cards for two visitors
    /// read differently: the person's name, else their Matrix ID; a card that
    /// names nobody says where (`AgentRoomLabel`).
    static func mapNeedsActionItem(_ item: NeedsActionItem,
                                   clientProxy: any ClientProxyProtocol,
                                   counterpartNames: [String: String],
                                   agentNames: [String: String] = [:]) -> NeedsActionListItem {
        switch item {
        case .approval(let approval):
            NeedsActionListItem(id: item.id,
                                kind: .approval,
                                subjectID: approval.id,
                                preview: trimPreview(approval.draftBody),
                                detail: approval.counterpartMXID.map { counterpartNames[$0] ?? $0 }
                                    ?? AgentRoomLabel.text(for: approval.targetRoomID, clientProxy: clientProxy),
                                createdAt: approval.createdAt,
                                agentName: agentNames[approval.agentID])
        case .verification(let verification):
            NeedsActionListItem(id: item.id,
                                kind: .verification,
                                subjectID: verification.id,
                                preview: verification.requesterUserID,
                                detail: verification.requesterDeviceID,
                                createdAt: verification.createdAt)
        }
    }

    private func lookUpCounterparts() {
        let wanted = approvalsStreamService.needsAction.compactMap { item -> String? in
            if case .approval(let approval) = item { approval.counterpartMXID } else { nil }
        } + visitorEntries.map(\.visitorMXID)
        for userID in Set(wanted) where counterpartNames[userID] == nil && !counterpartLookups.contains(userID) {
            counterpartLookups.insert(userID)
            Task { [weak self, clientProxy] in
                guard case .success(let profile) = await clientProxy.profile(for: userID),
                      let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty, name != userID, let self else {
                    return
                }
                counterpartNames[userID] = name
                refreshFromService()
                refreshVisitorMessages()
            }
        }
    }

    /// The names come from the owner's spaces. A failed read only leaves
    /// rows without a name; the next appearance reads again.
    private func loadAgentNames() async {
        guard !isLoadingAgentNames else { return }
        isLoadingAgentNames = true
        defer { isLoadingAgentNames = false }
        
        guard case .success(let directory) = await agentPlatformService.listMyAgentSpaces() else { return }
        var cards: [String: AgentSpaceAgentCard] = [:]
        for space in directory.spaces {
            guard case .success(let detail) = await agentPlatformService.fetchAgentSpace(orgID: space.orgID) else { continue }
            for agent in detail.agents {
                cards[agent.agentID] = agent
            }
        }
        agentCards = cards
        refreshFromService()
        refreshVisitorMessages()
        if case .loaded(let items, let loadMore) = state.activityState {
            state.activityState = .loaded(named(items), loadMore: loadMore)
        }
    }
    
    private func named(_ items: [AgentActivityListItem]) -> [AgentActivityListItem] {
        items.map { item in
            var item = item
            item.agentName = item.agentID.flatMap { agentNames[$0] }
            return item
        }
    }

    /// The text they wrote; nothing for a missed call; for a kind newer than
    /// this build, a word to update rather than a guess (decision 96).
    private static func visitorBody(_ entry: VisitorMessage) -> String? {
        switch entry.kind {
        case .message: entry.body.isEmpty ? nil : trimPreview(entry.body)
        case .missedCall: nil
        case .other: UntranslatedL10n.screenNotificationsHubVisitorOtherBody
        }
    }

    /// Same ~160-char preview budget the retired inbox used — two
    /// lines at default Dynamic Type.
    private static func trimPreview(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 160 { return trimmed }
        return String(trimmed.prefix(160)) + "…"
    }

    // MARK: - Activity pagination

    private func loadFirstPage() async {
        loadGeneration += 1
        let generation = loadGeneration
        state.activityState = .loading

        let result = await agentPlatformService.fetchNotifications(activityCursor: nil,
                                                                   limit: Self.defaultPageSize)

        guard generation == loadGeneration else {
            MXLog.info("NotificationsHubScreenViewModel: dropping stale first-page response")
            return
        }

        switch result {
        case .success(let snapshot):
            visitorEntries = snapshot.visitorMessages
            refreshVisitorMessages()
            lookUpCounterparts()
            let mapped = named(snapshot.activity.map { AgentActivityScreenViewModel.mapItem($0, clientProxy: clientProxy) })
            state.activityState = .loaded(mapped, loadMore: Self.makeLoadMoreState(from: snapshot.nextActivityCursor))
            MXLog.info("Loaded \(mapped.count) hub activity entries; next_cursor=\(snapshot.nextActivityCursor != nil ? "present" : "exhausted")")
        case .failure(let error):
            MXLog.error("Failed to load notifications hub: \(error)")
            state.activityState = .failed
            state.bindings.alertInfo = AlertInfo(id: .loadFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadFirstPage() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    private func loadNextPage(currentItems: [AgentActivityListItem], cursor: String) async {
        state.activityState = .loaded(currentItems, loadMore: .loading)
        let generation = loadGeneration

        let result = await agentPlatformService.fetchNotifications(activityCursor: cursor,
                                                                   limit: Self.defaultPageSize)

        guard generation == loadGeneration else {
            MXLog.info("NotificationsHubScreenViewModel: dropping stale next-page response")
            return
        }

        switch result {
        case .success(let snapshot):
            let mapped = named(snapshot.activity.map { AgentActivityScreenViewModel.mapItem($0, clientProxy: clientProxy) })
            let combined = currentItems + mapped
            state.activityState = .loaded(combined, loadMore: Self.makeLoadMoreState(from: snapshot.nextActivityCursor))
            MXLog.info("Appended \(mapped.count) hub activity entries; total=\(combined.count)")
        case .failure(let error):
            MXLog.error("Failed to load hub activity continuation page: \(error)")
            state.activityState = .loaded(currentItems, loadMore: .failed(cursor: cursor))
        }
    }

    private static func makeLoadMoreState(from nextCursor: String?) -> LoadMoreState {
        if let cursor = nextCursor { return .idle(cursor: cursor) }
        return .exhausted
    }
}
