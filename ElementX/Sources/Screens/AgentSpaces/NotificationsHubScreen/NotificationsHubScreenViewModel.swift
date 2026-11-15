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
/// AGENT-PLATFORM: platform sync (decision 289). Everything comes from the
/// session's `AgentsStore`:
///
/// 1. **Needs action** and the visitors' entries — `.needsAction`, the same
///    read the tab badge holds, read again on `approval.changed`,
///    `verification.changed` and `notification.*`; the activity's answer
///    carries it too. A failed read with nothing shown is a retry row.
/// 2. **Activity** — `.hubActivity`, read again on `agent.activity` with as
///    many rows as it holds; the bottom sentinel appends the next page.
/// 3. **Agent names** — the spaces' cards, shared with the tab root.
///
/// The hub appearing PUTs the last-seen marker — opening the hub IS the "I
/// saw these" gesture (decision 8, Instagram-style).
class NotificationsHubScreenViewModel: NotificationsHubScreenViewModelType, NotificationsHubScreenViewModelProtocol {
    private let store: AgentsStore
    private let agentPlatformService: any AgentPlatformServiceProtocol
    private let clientProxy: any ClientProxyProtocol
    private let userIndicatorController: any UserIndicatorControllerProtocol
    /// Display names of the people pending cards are about, as their profiles come in.
    private var counterpartNames: [String: String] = [:]
    private var counterpartLookups: Set<String> = []
    /// Visitors' entries dismissed here: gone at once, back when the server refuses.
    private var dismissedVisitorMessageIDs: Set<String> = []
    /// The next activity page on its way, or the last that could not be read.
    private var loadMore: LoadMoreState?

    static let defaultPageSize = 25

    private let actionsSubject: PassthroughSubject<NotificationsHubScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<NotificationsHubScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private let resources: [AgentsResource] = [.needsAction, .hubActivity, .spaces]

    init(store: AgentsStore,
         agentPlatformService: any AgentPlatformServiceProtocol,
         clientProxy: any ClientProxyProtocol,
         userIndicatorController: any UserIndicatorControllerProtocol) {
        self.store = store
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        super.init(initialViewState: NotificationsHubScreenViewState())

        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        for resource in resources {
            store.show(resource, by: self)
        }
    }

    isolated deinit {
        for resource in resources {
            store.stopShowing(resource, by: self)
        }
    }

    // MARK: - Public

    override func process(viewAction: NotificationsHubScreenViewAction) {
        MXLog.info("NotificationsHubScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Opening the hub is the "seen" gesture.
            Task { await store.markNotificationsSeen() }
        case .retry:
            Task { await store.reread(.needsAction) }
            Task { await store.reread(.hubActivity) }
        case .loadMore:
            guard case .loaded(_, let sentinel) = state.activityState else { return }
            switch sentinel {
            case .idle, .failed:
                Task { await loadNextPage() }
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
            guard let entry = store.visitorMessages?.first(where: { $0.id == id }) else { return }
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
        if store.card(agentID: entry.agentID) == nil {
            await store.reread(.spaces)
        }
        guard let agent = store.card(agentID: entry.agentID) else {
            MXLog.error("No agent \(entry.agentID) among the owner's spaces for a visitor's entry")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast, title: L10n.errorUnknown, icon: \.error))
            return
        }
        actionsSubject.send(.showVisitorSettings(agent: agent))
    }

    /// Gone from the list at once; back where it was when the server refuses.
    /// One already gone there (dismissed elsewhere, past its 30 days) stays gone.
    private func dismissVisitorMessage(id: String) async {
        guard dismissedVisitorMessageIDs.insert(id).inserted else { return }
        render()

        switch await agentPlatformService.dismissVisitorMessage(id: id) {
        case .success, .failure(.notFound):
            MXLog.info("Dismissed a visitor's entry")
        case .failure(let error):
            MXLog.error("Failed to dismiss a visitor's entry: \(error)")
            dismissedVisitorMessageIDs.remove(id)
            render()
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenNotificationsHubVisitorDismissFailed,
                                                                  icon: \.error))
        }
    }

    // MARK: - Rendering

    private func render() {
        let agentNames = store.spaces?.cards.mapValues(\.displayName) ?? [:]
        let needsAction = store.needsAction ?? []
        let visitorEntries = (store.visitorMessages ?? []).filter { !dismissedVisitorMessageIDs.contains($0.id) }

        let needsActionItems = needsAction.map {
            Self.mapNeedsActionItem($0, clientProxy: clientProxy, counterpartNames: counterpartNames, agentNames: agentNames)
        }
        if state.needsAction != needsActionItems {
            state.needsAction = needsActionItems
        }
        let visitorItems = visitorEntries.map { entry in
            VisitorMessageListItem(id: entry.id,
                                   kind: entry.kind,
                                   visitorName: counterpartNames[entry.visitorMXID] ?? entry.visitorMXID,
                                   body: Self.visitorBody(entry),
                                   agentID: entry.agentID,
                                   roomID: entry.roomID,
                                   createdAt: entry.createdAt,
                                   agentName: agentNames[entry.agentID])
        }
        if state.visitorMessages != visitorItems {
            state.visitorMessages = visitorItems
        }
        if state.isNeedsActionRead != (store.needsAction != nil) {
            state.isNeedsActionRead = store.needsAction != nil
        }
        // Nothing read of what waits and the read failed: a retry, never «nothing waits».
        let isNeedsActionFailed = if case .failed = store.readState(.needsAction, \.needsAction) { true } else { false }
        if state.isNeedsActionFailed != isNeedsActionFailed {
            state.isNeedsActionFailed = isNeedsActionFailed
        }
        if state.areAgentNamesRead != (store.spaces != nil) {
            state.areAgentNamesRead = store.spaces != nil
        }

        let activityState: NotificationsActivityState = switch store.readState(.hubActivity, \.hubActivity) {
        case .loading: .loading
        case .failed: .failed
        case .loaded(let page):
            .loaded(page.items.map { entry in
                var item = AgentActivityScreenViewModel.mapItem(entry, clientProxy: clientProxy)
                item.agentName = item.agentID.flatMap { agentNames[$0] }
                return item
            }, loadMore: loadMore ?? Self.makeLoadMoreState(from: page.nextCursor))
        }
        if state.activityState != activityState {
            state.activityState = activityState
        }
        if state.syncStatus != store.syncStatus {
            state.syncStatus = store.syncStatus
        }
        lookUpCounterparts(needsAction: needsAction, visitorEntries: visitorEntries)
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

    private func lookUpCounterparts(needsAction: [NeedsActionItem], visitorEntries: [VisitorMessage]) {
        let wanted = needsAction.compactMap { item -> String? in
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
                render()
            }
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

    private func loadNextPage() async {
        guard case .loaded(_, let sentinel) = state.activityState else { return }
        loadMore = .loading
        render()
        let isRead = await store.loadMore(.hubActivity)
        if isRead {
            loadMore = nil
        } else if case .idle(let cursor) = sentinel {
            loadMore = .failed(cursor: cursor)
        } else {
            loadMore = sentinel
        }
        render()
    }

    private static func makeLoadMoreState(from nextCursor: String?) -> LoadMoreState {
        if let cursor = nextCursor { return .idle(cursor: cursor) }
        return .exhausted
    }
}
