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

typealias ArmToolScreenViewModelType = StateStoreViewModelV2<ArmToolScreenViewState, ArmToolScreenViewAction>

/// Drives `ArmToolScreen`. Builds a typed `ToolParams` (WHAT) + typed
/// `TriggerKind` (WHEN) from the form bindings and arms them through the
/// gate via `armTool`, or turns the capability off via `disableTool`.
/// The capabilities screen re-pulls the room tools after the sheet
/// dismisses, so this ViewModel only reports success — it doesn't hold
/// the read model.
class ArmToolScreenViewModel: ArmToolScreenViewModelType, ArmToolScreenViewModelProtocol {
    private let roomID: String
    private let agentID: String
    private let agentPlatformService: any RoomToolsServiceProtocol
    /// Set when editing an existing tool — the arm carries it and the backend
    /// turns it off in the same transaction (ADR-0088). `nil` when creating.
    private let replacingToolID: String?
    private var selectedLanguageIndex: Int?

    /// The transport-specific translation language sets, fetched once from
    /// `GET /tools/catalog`. The language picker is populated from the set
    /// that matches the capability: `voice` for live translation (an
    /// off-list code crashes the runtime), `text` otherwise. Empty until
    /// the catalog resolves; a picker tap before then still works but shows
    /// no rows, so the fetch is kicked off at init.
    private var textLanguages: [AgentLanguage] = []
    private var voiceLanguages: [AgentLanguage] = []
    /// The catalogue's `available_tool_kinds`, once read (live translation
    /// only): says whether a refused call tool means this agent doesn't join
    /// calls (decision 168) or this room doesn't take it.
    private var availableToolKinds: Set<String>?

    private let actionsSubject: PassthroughSubject<ArmToolScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ArmToolScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// Create a tool. `active` (if any) drives the bulk "Turn off".
    convenience init(roomID: String,
                     agentID: String,
                     agentDisplayName: String,
                     capability: AgentCapability,
                     active: ActiveCapabilityTool?,
                     agentPlatformService: any RoomToolsServiceProtocol) {
        self.init(roomID: roomID,
                  agentID: agentID,
                  agentDisplayName: agentDisplayName,
                  capability: capability,
                  activeToolIDs: active?.toolIDs ?? [],
                  editing: nil,
                  agentPlatformService: agentPlatformService)
    }

    /// Edit an existing tool — the form is seeded from its typed params /
    /// trigger and submit replaces it.
    convenience init(roomID: String,
                     agentID: String,
                     agentDisplayName: String,
                     editing tool: ActiveToolDetail,
                     agentPlatformService: any RoomToolsServiceProtocol) {
        self.init(roomID: roomID,
                  agentID: agentID,
                  agentDisplayName: agentDisplayName,
                  capability: tool.capability,
                  activeToolIDs: [tool.toolID],
                  editing: tool,
                  agentPlatformService: agentPlatformService)
    }

    private init(roomID: String,
                 agentID: String,
                 agentDisplayName: String,
                 capability: AgentCapability,
                 activeToolIDs: [String],
                 editing: ActiveToolDetail?,
                 agentPlatformService: any RoomToolsServiceProtocol) {
        self.roomID = roomID
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        replacingToolID = editing?.toolID

        var bindings = ArmToolScreenViewStateBindings()
        if let editing {
            Self.seed(&bindings, from: editing)
        }
        let state = ArmToolScreenViewState(capability: capability,
                                           activeToolIDs: activeToolIDs,
                                           isEditing: editing != nil,
                                           agentDisplayName: agentDisplayName,
                                           bindings: bindings)
        super.init(initialViewState: state)

        // Translation capabilities need the catalog's per-transport language
        // allow-lists so the picker offers only supported languages (Brief
        // 0047 / ADR-0062). Non-translation capabilities never open the
        // picker, so skip the fetch.
        if capability == .translateMessages || capability == .liveCallTranslation {
            Task { await loadTranslationLanguages() }
        }
    }

    /// Resolve the per-transport translation language sets from the catalog.
    /// A failure leaves the sets empty — the picker then shows no rows rather
    /// than the whole ISO catalogue, keeping an unsupported language
    /// unselectable.
    private func loadTranslationLanguages() async {
        switch await agentPlatformService.fetchToolsCatalog(agentID: agentID, roomID: roomID) {
        case .success(let catalog):
            textLanguages = catalog.textTranslationLanguages
            voiceLanguages = catalog.voiceTranslationLanguages
            availableToolKinds = Set(catalog.availableToolKinds)
        case .failure(let error):
            MXLog.error("Failed to load tool catalog languages: \(error)")
        }
    }

    /// The language set the picker should offer for this capability: the
    /// voice allow-list for live translation, the text set otherwise.
    private var languagesForCapability: [AgentLanguage] {
        state.isLiveTranslation ? voiceLanguages : textLanguages
    }

    /// Reverse-map a tool's typed params + trigger into the form bindings —
    /// the inverse of `buildParams` / `buildScope`.
    private static func seed(_ bindings: inout ArmToolScreenViewStateBindings, from tool: ActiveToolDetail) {
        switch tool.params {
        case .translate(let language):
            bindings.kind = .translate
            bindings.language = language
        case .simplify:
            bindings.kind = .simplify
        case .correct:
            bindings.kind = .correct
        case .rephrase(let instruction):
            bindings.kind = .rephrase
            bindings.instruction = instruction
        case .summarize:
            bindings.kind = .summarize
        case .custom(let instruction):
            bindings.kind = .custom
            bindings.instruction = instruction
        case .liveTranslate(let languages, let style):
            bindings.targetLanguages = languages
            bindings.liveStyle = style
        case .callSummary, .callRecording:
            break
        case .unknown:
            break
        }

        let scope: AudienceScope? = {
            switch tool.trigger {
            case .onMessage(let scope), .onVoiceCall(let scope): return scope
            case .unknown: return nil
            }
        }()
        if let scope {
            switch scope {
            case .anyone: bindings.scope = .anyone
            case .nonSelfNonOwner: bindings.scope = .nonSelfNonOwner
            case .ownerOnly: bindings.scope = .ownerOnly
            case .specificSenders(let members):
                bindings.scope = .specificSenders
                bindings.members = members
            case .everyoneExcept(let members):
                bindings.scope = .everyoneExcept
                bindings.members = members
            case .unknown:
                break
            }
        }
    }

    // MARK: - Public

    override func process(viewAction: ArmToolScreenViewAction) {
        MXLog.info("ArmToolScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .submit:
            Task { await arm() }
        case .turnOff:
            confirmTurnOff()
        case .selectMembers:
            actionsSubject.send(.selectMembers(current: state.bindings.members))
        case .selectLanguage(let index):
            selectedLanguageIndex = index
            let current = index.flatMap { state.bindings.targetLanguages[safe: $0] } ?? state.bindings.language
            actionsSubject.send(.selectLanguage(languages: languagesForCapability, current: current))
        case .removeLanguage(let index):
            guard state.bindings.targetLanguages.indices.contains(index) else { return }
            state.bindings.targetLanguages.remove(at: index)
        case .moveLanguages(let fromOffsets, let toOffset):
            state.bindings.targetLanguages.move(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func applyMemberSelection(_ members: [String]) {
        state.bindings.members = members
    }

    func applyLanguageSelection(_ code: String) {
        guard state.isLiveTranslation else {
            state.bindings.language = code
            return
        }

        if let selectedLanguageIndex,
           state.bindings.targetLanguages.indices.contains(selectedLanguageIndex) {
            if let duplicateIndex = state.bindings.targetLanguages.firstIndex(of: code), duplicateIndex != selectedLanguageIndex {
                state.bindings.targetLanguages.remove(at: selectedLanguageIndex)
            } else {
                state.bindings.targetLanguages[selectedLanguageIndex] = code
            }
        } else if !state.bindings.targetLanguages.contains(code) {
            state.bindings.targetLanguages.append(code)
        }
        selectedLanguageIndex = nil
    }

    // MARK: - Private

    private func arm() async {
        guard state.canSubmit else { return }
        state.isSubmitting = true
        defer { state.isSubmitting = false }

        let params = buildParams()
        let trigger = buildTrigger()

        switch await agentPlatformService.armTool(agentID: agentID, roomID: roomID, params: params, trigger: trigger, replacesToolID: replacingToolID) {
        case .success:
            MXLog.info("Armed tool \(params.kind) with trigger \(trigger.kind), replacing \(replacingToolID ?? "nothing")")
            actionsSubject.send(.finished)
        case .failure(.replacedGone):
            // The edited tool was turned off elsewhere: this form's id is stale
            // and a retry can't land. Say so, then close so the list reloads.
            MXLog.info("Edit of \(replacingToolID ?? "nothing") refused: the tool is gone")
            state.bindings.alertInfo = AlertInfo(id: .armFailed,
                                                 title: L10n.commonError,
                                                 message: UntranslatedL10n.screenArmToolErrorReplacedGone,
                                                 primaryButton: .init(title: L10n.actionOk) { [weak self] in
                                                     self?.actionsSubject.send(.finished)
                                                 })
        case .failure(let error):
            MXLog.error("Failed to arm tool: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .armFailed,
                                                 title: L10n.commonError,
                                                 message: message(for: error))
        }
    }

    private func message(for error: RoomToolArmError) -> String {
        switch error {
        case .refused(.doesNotFireHere) where agentDoesNotJoinCalls:
            UntranslatedL10n.screenArmToolErrorAgentDoesNotJoinCalls
        case .refused(let refusal): refusal.message
        case .replacedGone: UntranslatedL10n.screenArmToolErrorReplacedGone
        case .failed(let error): error.roomToolMessage
        }
    }

    /// Decision 168: a company agent joins no call, so the arm refuses its
    /// call tools. Told from data, not the refusal's English detail: the call
    /// artifacts fire in every kind of room for an agent that joins calls, so
    /// their refusal can mean only this; for live translation (also refused
    /// in a 1:1 room) the catalogue says so by naming no call artifact.
    private var agentDoesNotJoinCalls: Bool {
        switch state.capability {
        case .callSummary, .callRecording:
            true
        case .liveCallTranslation:
            availableToolKinds.map { $0.isDisjoint(with: ["call_summary", "call_recording"]) } ?? false
        case .translateMessages:
            false
        }
    }

    /// Re-walk R5: one tap on the bulk "Turn off" used to turn the room's
    /// tool off for everyone, and it could land there by mistake.
    private func confirmTurnOff() {
        state.bindings.alertInfo = AlertInfo(id: .confirmTurnOff,
                                             title: UntranslatedL10n.screenArmToolTurnOffConfirmTitle,
                                             message: UntranslatedL10n.screenArmToolTurnOffConfirmMessage,
                                             primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                             secondaryButton: .init(title: UntranslatedL10n.screenArmToolTurnOff, role: .destructive) { [weak self] in
                                                 Task { await self?.turnOff() }
                                             })
    }

    private func turnOff() async {
        state.isSubmitting = true
        defer { state.isSubmitting = false }

        // Disable every active tool for this capability; report success
        // only if they all applied.
        for toolID in state.activeToolIDs {
            switch await agentPlatformService.disableTool(agentID: agentID, roomID: roomID, toolID: toolID) {
            case .success:
                continue
            case .failure(let error):
                MXLog.error("Failed to disable tool \(toolID): \(error)")
                state.bindings.alertInfo = AlertInfo(id: .disableFailed,
                                                     title: L10n.commonError,
                                                     message: error.roomToolMessage)
                return
            }
        }
        MXLog.info("Disabled \(state.activeToolIDs.count) tool(s)")
        actionsSubject.send(.finished)
    }

    /// Map the form bindings to a typed `ToolParams`.
    private func buildParams() -> ToolParams {
        let bindings = state.bindings
        let language = bindings.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = bindings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if state.isLiveTranslation {
            return .liveTranslate(targetLanguages: bindings.targetLanguages, style: bindings.liveStyle)
        }
        if state.capability == .callSummary { return .callSummary }
        if state.capability == .callRecording { return .callRecording }
        switch bindings.kind {
        case .translate: return .translate(targetLanguage: language)
        case .simplify: return .simplify
        case .correct: return .correct
        case .rephrase: return .rephrase(instruction: instruction)
        case .summarize: return .summarize
        case .custom: return .custom(instruction: instruction)
        }
    }

    /// Map the form bindings to a typed `TriggerKind`. Text transforms
    /// arm an `on_message` trigger; live translation an `on_voice_call`.
    private func buildTrigger() -> TriggerKind {
        if state.capability == .translateMessages {
            return .onMessage(senderScope: buildScope())
        }
        if state.capability == .liveCallTranslation {
            return .onVoiceCall(speakerScope: buildScope())
        }
        return .onVoiceCall(speakerScope: .anyone)
    }

    private func buildScope() -> AudienceScope {
        let members = state.bindings.members
        switch state.bindings.scope {
        case .anyone: return .anyone
        case .nonSelfNonOwner: return .nonSelfNonOwner
        case .ownerOnly: return .ownerOnly
        case .specificSenders: return .specificSenders(members: members)
        case .everyoneExcept: return .everyoneExcept(members: members)
        }
    }
}
