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

typealias AgentToolsListScreenViewModelType = StateStoreViewModelV2<AgentToolsListScreenViewState, AgentToolsListScreenViewAction>

/// Drives `AgentToolsListScreen`. Reads `GET /rooms/:room_id/tools` on
/// entry + retry, projects the caller's own agent's armed tools into the
/// per-tool list the edit surface renders, and turns a tool off via
/// `disableTool`. The flow coordinator re-pulls after an edit dismisses.
class AgentToolsListScreenViewModel: AgentToolsListScreenViewModelType, AgentToolsListScreenViewModelProtocol {
    private let roomID: String
    private let agentID: String
    private let agentPlatformService: any RoomToolsServiceProtocol

    private let actionsSubject: PassthroughSubject<AgentToolsListScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentToolsListScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(roomID: String,
         agentID: String,
         agentDisplayName: String,
         agentPlatformService: any RoomToolsServiceProtocol) {
        self.roomID = roomID
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService

        let state = AgentToolsListScreenViewState(agentDisplayName: agentDisplayName,
                                                  bindings: AgentToolsListScreenViewStateBindings())
        super.init(initialViewState: state)
    }

    // MARK: - Public

    override func process(viewAction: AgentToolsListScreenViewAction) {
        MXLog.info("AgentToolsListScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            if case .loaded = state.listState { return }
            Task { await loadTools() }
        case .retry:
            Task { await loadTools() }
        case .selectTool(let id):
            guard let tool = state.tools.first(where: { $0.id == id }) else { return }
            guard tool.canFire else {
                // Editing would arm it again, which the server refuses: only off.
                state.bindings.alertInfo = AlertInfo(id: .unavailable,
                                                     title: UntranslatedL10n.screenAgentCapabilitiesUnavailable,
                                                     message: UntranslatedL10n.screenAgentToolsListUnavailableMessage,
                                                     primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                                     secondaryButton: .init(title: UntranslatedL10n.screenArmToolTurnOff, role: .destructive) { [weak self] in
                                                         self?.process(viewAction: .turnOffTool(id: id))
                                                     })
                return
            }
            guard tool.isEditable else {
                // Turning it off removes the whole tool, knowingly.
                state.bindings.alertInfo = AlertInfo(id: .needsUpdate,
                                                     title: UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle,
                                                     message: UntranslatedL10n.screenAgentToolsListNeedsUpdateMessage,
                                                     primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                                     secondaryButton: .init(title: UntranslatedL10n.screenArmToolTurnOff, role: .destructive) { [weak self] in
                                                         self?.process(viewAction: .turnOffTool(id: id))
                                                     })
                return
            }
            actionsSubject.send(.editTool(tool))
        case .turnOffTool(let id):
            Task { await turnOff(id: id) }
        case .addTool:
            actionsSubject.send(.addTool)
        case .done:
            actionsSubject.send(.dismiss)
        }
    }

    /// Re-pull the tool list — called by the coordinator after an edit /
    /// create form dismisses.
    func reload() {
        Task { await loadTools() }
    }

    // MARK: - Private

    private func loadTools() async {
        state.listState = .loading
        let catalog = await agentPlatformService.fetchToolsCatalog(agentID: agentID, roomID: roomID)
        let roomTools = await agentPlatformService.fetchRoomTools(roomID: roomID)
        switch (catalog, roomTools) {
        case (.success(let catalog), .success(let roomTools)):
            let firing = Set(catalog.availableToolKinds)
            let tools = Self.projectTools(from: roomTools, ownAgentID: agentID).map { tool in
                var tool = tool
                tool.canFire = firing.contains(tool.params.kind)
                return tool
            }
            state.listState = .loaded(tools: tools)
        case (.failure(let error), _), (_, .failure(let error)):
            // Without the catalogue nothing says which listed tools run here,
            // so a failed read of either is "couldn't check".
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

    private func turnOff(id: String) async {
        switch await agentPlatformService.disableTool(agentID: agentID, roomID: roomID, toolID: id) {
        case .success:
            MXLog.info("Turned off tool \(id)")
            await loadTools()
        case .failure(let error):
            MXLog.error("Failed to turn off tool \(id): \(error)")
            state.bindings.alertInfo = AlertInfo(id: .turnOffFailed,
                                                 title: L10n.commonError,
                                                 message: error.roomToolMessage)
        }
    }

    // MARK: - Projection

    /// Project the room-wide read model into the caller's own agent's armed
    /// tools, one `ActiveToolDetail` per tool (own tools carry `toolID` +
    /// typed params/trigger). Static so previews + tests build states
    /// without the service stack.
    static func projectTools(from roomTools: RoomToolsView, ownAgentID: String) -> [ActiveToolDetail] {
        guard let entry = roomTools.agents.first(where: { $0.agentID == ownAgentID }) else {
            return []
        }

        return entry.tools.compactMap { tool -> ActiveToolDetail? in
            guard let toolID = tool.toolID,
                  let params = tool.params,
                  let trigger = tool.trigger,
                  let capability = AgentCapability.capability(forToolKind: tool.toolKind) else {
                return nil
            }
            return ActiveToolDetail(toolID: toolID,
                                    capability: capability,
                                    params: params,
                                    trigger: trigger,
                                    title: title(for: params),
                                    subtitle: subtitle(for: trigger, kind: params.kind))
        }
    }

    /// A short human title from the typed params.
    static func title(for params: ToolParams) -> String {
        switch params {
        case .translate(let language):
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        case .simplify:
            return UntranslatedL10n.screenArmToolKindSimplify
        case .correct:
            return UntranslatedL10n.screenArmToolKindCorrect
        case .rephrase(let instruction):
            return UntranslatedL10n.screenAgentToolsListTitleRephrase(instruction)
        case .summarize:
            return UntranslatedL10n.screenArmToolKindSummarize
        case .custom:
            return UntranslatedL10n.screenArmToolKindCustom
        case .liveTranslate(let languages, _):
            let names = languages.map { TranslationLanguageDisplayName.localizedName(for: $0) }
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(names.joined(separator: ", "))
        case .callSummary:
            return UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle
        case .callRecording:
            return UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
        case .unknown:
            return UntranslatedL10n.screenAgentToolsListTitleUnknown
        }
    }

    /// When it runs and for whom, in the words every tool row uses.
    static func subtitle(for trigger: TriggerKind, kind: String) -> String {
        switch trigger {
        case .onMessage(let scope), .onVoiceCall(let scope):
            // A scope newer than this build: the row says to update, as an edit would.
            if case .unknown = scope { return UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle }
            return AgentToolTrigger.line(forKind: kind, audience: scope) ?? UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle
        case .unknown:
            return UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle
        }
    }
}
