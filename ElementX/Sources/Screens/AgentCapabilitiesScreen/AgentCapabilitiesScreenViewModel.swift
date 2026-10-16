//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.
//

import Combine
import SwiftUI

typealias AgentCapabilitiesScreenViewModelType = StateStoreViewModelV2<AgentCapabilitiesScreenViewState, AgentCapabilitiesScreenViewAction>

/// Drives `AgentCapabilitiesScreen`. Pulls
/// `GET /rooms/:room_id/tools` once on `.appeared` and again on
/// `.retry`, projecting the caller's own agent entry into the per-
/// capability on/off state the list renders, and the catalog's
/// `available_tool_kinds` into the rows it offers. No SSE / push wiring — a
/// room's armed tool set changes rarely and only in response to the
/// owner's own actions from this same screen, so a fetch on entry (plus
/// a re-fetch after an arm/disable round-trips through the coordinator)
/// is sufficient.
class AgentCapabilitiesScreenViewModel: AgentCapabilitiesScreenViewModelType, AgentCapabilitiesScreenViewModelProtocol {
    private let roomID: String
    private let agentID: String
    private let agentPlatformService: any RoomToolsServiceProtocol
    /// Bumped by every load. A read that answers after a newer load started
    /// is dropped, so a slow first fetch can't undo a refresh.
    private var loadGeneration = 0

    private let actionsSubject: PassthroughSubject<AgentCapabilitiesScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentCapabilitiesScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         agentID: String,
         agentDisplayName: String,
         showsDoneButton: Bool = true,
         agentPlatformService: any RoomToolsServiceProtocol) {
        self.roomID = roomID
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService

        let state = AgentCapabilitiesScreenViewState(agentDisplayName: agentDisplayName,
                                                     showsDoneButton: showsDoneButton,
                                                     bindings: AgentCapabilitiesScreenViewStateBindings())
        super.init(initialViewState: state)
    }

    // MARK: - Public

    override func process(viewAction: AgentCapabilitiesScreenViewAction) {
        MXLog.info("AgentCapabilitiesScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Refetch on entry unless a prior load already succeeded with
            // content — on `.failed` (or a fresh `.loading`) we retry.
            if case .loaded = state.listState {
                return
            }
            Task { await loadTools() }
        case .retry:
            Task { await loadTools() }
        case .selectCapability(let capability):
            if state.isUnavailable(capability), let active = state.activeTool(for: capability) {
                // The arm form would offer to turn it on again, which the
                // server refuses (decision 168): only off, as in the tools list.
                state.bindings.alertInfo = AlertInfo(id: .unavailable,
                                                     title: UntranslatedL10n.screenAgentCapabilitiesUnavailable,
                                                     message: UntranslatedL10n.screenAgentToolsListUnavailableMessage,
                                                     primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                                     secondaryButton: .init(title: UntranslatedL10n.screenArmToolTurnOff, role: .destructive) { [weak self] in
                                                         Task { await self?.turnOff(toolIDs: active.toolIDs) }
                                                     })
                return
            }
            actionsSubject.send(.selectCapability(capability, active: state.activeTool(for: capability)))
        case .done:
            actionsSubject.send(.dismiss)
        }
    }

    /// Re-pull the tool state — called by the coordinator after an
    /// arm/disable form dismisses, so the on/off rows reflect the change.
    func reload() {
        Task { await loadTools() }
    }

    // MARK: - Private

    private func turnOff(toolIDs: [String]) async {
        for toolID in toolIDs {
            if case .failure(let error) = await agentPlatformService.disableTool(agentID: agentID, roomID: roomID, toolID: toolID) {
                MXLog.error("Failed to turn off tool \(toolID): \(error)")
                state.bindings.alertInfo = AlertInfo(id: .turnOffFailed,
                                                     title: L10n.commonError,
                                                     message: error.roomToolMessage)
                await loadTools()
                return
            }
        }
        MXLog.info("Turned off \(toolIDs.count) tool(s) that can't fire here")
        await loadTools()
    }

    private func loadTools() async {
        loadGeneration += 1
        let generation = loadGeneration
        state.listState = .loading

        let catalog = await agentPlatformService.fetchToolsCatalog(agentID: agentID, roomID: roomID)
        guard generation == loadGeneration else { return }
        let roomTools = await agentPlatformService.fetchRoomTools(roomID: roomID)
        guard generation == loadGeneration else { return }

        switch (catalog, roomTools) {
        case (.success(let catalog), .success(let roomTools)):
            let fireHere = AgentCapability.offered(availableToolKinds: catalog.availableToolKinds)
            let active = Self.projectActiveTools(from: roomTools, ownAgentID: agentID)
            // An active tool stays listed so it can be turned off, even when it
            // can't fire here; its row then says it won't run.
            state.offeredCapabilities = AgentCapability.allCases.filter { fireHere.contains($0) || active[$0] != nil }
            state.firingCapabilities = fireHere
            state.listState = .loaded(active: active)
            MXLog.info("Loaded room tools: \(active.count) active capabilit(ies) for agent \(agentID)")
        case (.failure(let error), _), (_, .failure(let error)):
            // Without the catalog nothing says what fires for this agent — a
            // company agent's call tools don't (decision 168) — so a failed
            // read of either is "couldn't check", never a guess.
            MXLog.error("Failed to load the tools catalog or the room tools: \(error)")
            state.listState = .failed
            state.bindings.alertInfo = AlertInfo(id: .loadFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadTools() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    /// Project the room-wide read model onto per-capability active state
    /// for the caller's own agent. Kept static so previews and tests can
    /// build view states directly without instantiating the service
    /// stack.
    static func projectActiveTools(from roomTools: RoomToolsView,
                                   ownAgentID: String) -> [AgentCapability: ActiveCapabilityTool] {
        guard let entry = roomTools.agents.first(where: { $0.agentID == ownAgentID }) else {
            return [:]
        }

        var result: [AgentCapability: ActiveCapabilityTool] = [:]
        for capability in AgentCapability.allCases {
            let tools = entry.tools.filter { capability.toolKinds.contains($0.toolKind) }
            guard !tools.isEmpty else { continue }
            result[capability] = ActiveCapabilityTool(toolIDs: tools.compactMap(\.toolID),
                                                      summary: summary(for: capability, tools: tools),
                                                      count: tools.count)
        }
        return result
    }

    /// Build the one-line subtitle for an active capability from its
    /// tools. Reads the typed params where present (own-agent slice),
    /// falling back to a plain count.
    private static func summary(for capability: AgentCapability, tools: [RoomToolView]) -> String {
        switch capability {
        case .translateMessages:
            let languages = tools.compactMap { tool -> String? in
                if case .translate(let language) = tool.params { return language }
                return nil
            }
            if let language = languages.first, tools.count == 1 {
                return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
            }
            return UntranslatedL10n.screenAgentsToolCount(tools.count)
        case .liveCallTranslation:
            let languages = tools.flatMap { tool -> [String] in
                if case .liveTranslate(let targetLanguages, _) = tool.params { return targetLanguages }
                return []
            }
            if let language = languages.first, languages.count == 1 {
                return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
            }
            return UntranslatedL10n.screenAgentsToolCount(tools.count)
        case .callSummary:
            return UntranslatedL10n.screenAgentCapabilitiesCallSummaryActive
        case .callRecording:
            return UntranslatedL10n.screenAgentCapabilitiesCallRecordingActive
        }
    }
}
