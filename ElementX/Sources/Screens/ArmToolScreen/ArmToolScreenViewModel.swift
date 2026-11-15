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
/// gate via `armTool`, or turns the edited tool off via `disableTool`. The
/// screen under it reads the tools again, so this only reports success.
class ArmToolScreenViewModel: ArmToolScreenViewModelType, ArmToolScreenViewModelProtocol {
    private let roomID: String
    private let agentID: String
    private let agentPlatformService: any RoomToolsServiceProtocol
    private let store: AgentsStore
    /// Set when editing an existing tool — the arm carries it and the backend
    /// turns it off in the same transaction (ADR-0088). `nil` when creating.
    private let replacingToolID: String?

    private let actionsSubject: PassthroughSubject<ArmToolScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ArmToolScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private var catalogResource: AgentsResource {
        .toolsCatalog(agentID: agentID, roomID: roomID)
    }

    /// A new tool: the same form without "Turn off".
    convenience init(roomID: String,
                     agentID: String,
                     agentDisplayName: String,
                     kind: AgentToolKind,
                     agentPlatformService: any RoomToolsServiceProtocol,
                     store: AgentsStore) {
        self.init(roomID: roomID,
                  agentID: agentID,
                  agentDisplayName: agentDisplayName,
                  kind: kind,
                  editing: nil,
                  agentPlatformService: agentPlatformService,
                  store: store)
    }

    /// Edit an existing tool — the form is seeded from its typed params /
    /// trigger and submit replaces it. Only a tool of a known kind gets here.
    convenience init?(roomID: String,
                      agentID: String,
                      agentDisplayName: String,
                      editing tool: ActiveToolDetail,
                      agentPlatformService: any RoomToolsServiceProtocol,
                      store: AgentsStore) {
        guard let kind = tool.kind else { return nil }
        self.init(roomID: roomID,
                  agentID: agentID,
                  agentDisplayName: agentDisplayName,
                  kind: kind,
                  editing: tool,
                  agentPlatformService: agentPlatformService,
                  store: store)
    }

    private init(roomID: String,
                 agentID: String,
                 agentDisplayName: String,
                 kind: AgentToolKind,
                 editing: ActiveToolDetail?,
                 agentPlatformService: any RoomToolsServiceProtocol,
                 store: AgentsStore) {
        self.roomID = roomID
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        self.store = store
        replacingToolID = editing?.toolID

        var bindings = ArmToolScreenViewStateBindings()
        if let editing {
            Self.seed(&bindings, from: editing)
        }
        super.init(initialViewState: ArmToolScreenViewState(kind: kind,
                                                            isEditing: editing != nil,
                                                            agentDisplayName: agentDisplayName,
                                                            bindings: bindings))

        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
        store.show(catalogResource, by: self)
    }

    isolated deinit {
        store.stopShowing(catalogResource, by: self)
    }

    /// Reverse-map a tool's typed params + trigger into the form bindings —
    /// the inverse of `buildParams` / `buildScope`.
    private static func seed(_ bindings: inout ArmToolScreenViewStateBindings, from tool: ActiveToolDetail) {
        switch tool.params {
        case .translate(let language):
            bindings.language = language
        case .rephrase(let instruction), .custom(let instruction):
            bindings.instruction = instruction
        case .simplify, .correct, .summarize, .liveTranslate, .callSummary, .callRecording, .unknown:
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
        case .selectLanguage:
            selectLanguage()
        }
    }

    func applyMemberSelection(_ members: [String]) {
        state.bindings.members = members
    }

    func applyLanguageSelection(_ code: String) {
        state.bindings.language = code
    }

    // MARK: - Private

    /// The languages come only from the catalogue: an off-list code crashes a call's session (Brief 0047 / ADR-0062).
    /// So a catalogue that can't be read says so and reads again, rather than opening an empty picker.
    private func selectLanguage() {
        switch store.readState(catalogResource, \.toolsCatalog) {
        case .loading:
            break
        case .failed:
            state.bindings.alertInfo = AlertInfo(id: .languagesFailed, title: L10n.commonError, message: L10n.errorUnknown)
            store.refresh(catalogResource)
        case .loaded(let catalog):
            actionsSubject.send(.selectLanguage(languages: catalog.textTranslationLanguages, current: state.bindings.language))
        }
    }

    private func render() {
        let isLoadingLanguages = if case .loading = store.readState(catalogResource, \.toolsCatalog) { true } else { false }
        if state.isLoadingLanguages != isLoadingLanguages {
            state.isLoadingLanguages = isLoadingLanguages
        }
    }

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
    /// their refusal can mean only this.
    private var agentDoesNotJoinCalls: Bool {
        state.kind == .callSummary || state.kind == .callRecording
    }

    /// Re-walk R5: one tap on "Turn off" used to turn the room's tool off for
    /// everyone, and it could land there by mistake.
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
        guard let replacingToolID else { return }
        state.isSubmitting = true
        defer { state.isSubmitting = false }

        switch await agentPlatformService.disableTool(agentID: agentID, roomID: roomID, toolID: replacingToolID) {
        case .success:
            MXLog.info("Disabled tool \(replacingToolID)")
            actionsSubject.send(.finished)
        case .failure(let error):
            MXLog.error("Failed to disable tool \(replacingToolID): \(error)")
            state.bindings.alertInfo = AlertInfo(id: .disableFailed,
                                                 title: L10n.commonError,
                                                 message: error.roomToolMessage)
        }
    }

    /// Map the form bindings to a typed `ToolParams`.
    private func buildParams() -> ToolParams {
        let bindings = state.bindings
        let language = bindings.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = bindings.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        switch state.kind {
        case .translate: return .translate(targetLanguage: language)
        case .simplify: return .simplify
        case .correct: return .correct
        case .rephrase: return .rephrase(instruction: instruction)
        case .summarize: return .summarize
        case .custom: return .custom(instruction: instruction)
        case .liveTranslate: return .liveTranslate(language: language)
        case .callSummary: return .callSummary
        case .callRecording: return .callRecording
        }
    }

    /// Map the form bindings to a typed `TriggerKind`. Text transforms arm an
    /// `on_message` trigger; the call tools an `on_voice_call`, for everyone.
    private func buildTrigger() -> TriggerKind {
        guard state.kind.firesOnCalls else {
            return .onMessage(senderScope: buildScope())
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
