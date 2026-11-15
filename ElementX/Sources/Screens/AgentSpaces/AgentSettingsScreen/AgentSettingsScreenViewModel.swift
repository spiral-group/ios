//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import SwiftUI

typealias AgentSettingsScreenViewModelType = StateStoreViewModelV2<AgentSettingsScreenViewState, AgentSettingsScreenViewAction>

protocol AgentSettingsScreenViewModelProtocol {
    var actionsPublisher: AnyPublisher<AgentSettingsScreenViewModelAction, Never> { get }
    var context: AgentSettingsScreenViewModelType.Context { get }
}

class AgentSettingsScreenViewModel: AgentSettingsScreenViewModelType, AgentSettingsScreenViewModelProtocol {
    private let agentPlatformService: AgentPlatformServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    // AGENT-PLATFORM (Brief 0083, question 359): the values were on the agent's screen already, so the form opens filled.
    private let store: AgentsStore
    /// The last read the store answered. A write's answer is newer, so only a later read is adopted.
    private var storeReadModel: AgentReadModel?

    private let actionsSubject: PassthroughSubject<AgentSettingsScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<AgentSettingsScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(agent: AgentSpaceAgentCard,
         section: AgentSettingsSection,
         agentPlatformService: AgentPlatformServiceProtocol,
         store: AgentsStore,
         userIndicatorController: UserIndicatorControllerProtocol) {
        self.agentPlatformService = agentPlatformService
        self.store = store
        self.userIndicatorController = userIndicatorController

        super.init(initialViewState: AgentSettingsScreenViewState(card: agent, section: section))

        // Before the first render, which then shows a read on its way rather than the last opening's failure.
        for resource in shownResources {
            store.show(resource, by: self)
        }
        store.refresh(agentResource)
        render()
        store.observe { [weak self] in
            guard let self else { return false }
            render()
            return true
        }
    }

    isolated deinit {
        for resource in shownResources {
            store.stopShowing(resource, by: self)
        }
    }

    private var agentResource: AgentsResource {
        .agent(agentID: state.card.agentID)
    }

    private var limitsResource: AgentsResource {
        .editSchema(agentID: state.card.agentID)
    }

    private var shownResources: [AgentsResource] {
        state.needsPersonaBounds ? [agentResource, limitsResource] : [agentResource]
    }

    override func process(viewAction: AgentSettingsScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")

        // The choices are disabled while a write is out; a tap that slips
        // through is dropped, so two PATCHes never race.
        if state.isWriting, viewAction.writesAtOnce { return }

        switch viewAction {
        case .setVisitorPolicy(let policy):
            guard let current = state.readModel?.visitorPolicy, current != policy else { return }
            state.bindings.visitorPolicy = policy
            Task { await apply(AgentEditPatch(visitorPolicy: policy)) }
        case .setShowInSearch(let isOn):
            let visibility = isOn ? "public" : "private"
            guard let current = state.readModel?.visibility, current != visibility else { return }
            state.bindings.showInSearch = isOn
            Task { await apply(AgentEditPatch(visibility: visibility)) }
        case .setVoiceLanguage(let language):
            guard let current = state.readModel?.voiceLanguage, current != language else { return }
            state.bindings.voiceLanguage = language
            Task { await apply(AgentEditPatch(voiceLanguage: language)) }
        case .selectTone(let choice):
            guard state.isTextEditable else { return }
            if let value = choice.value {
                // A preset is a choice: it applies at once, with only the tone.
                state.bindings.isCustomTone = false
                state.bindings.tone = value
                guard state.personaDidChange(.tone) else { return }
                Task { await apply(AgentEditPatch(persona: .init(tone: value))) }
            } else {
                state.bindings.isCustomTone = true
            }
        case .save:
            Task { await save() }
        case .cancel:
            cancel()
        case .retry:
            retry()
        }
    }

    // MARK: - Private

    private func retry() {
        if state.loadState.isAgentUnavailable {
            store.refresh(agentResource)
        }
        if state.loadState.hasFailedLimits {
            store.refresh(limitsResource)
        }
        render()
    }

    private func render() {
        renderAgent()
        if state.needsPersonaBounds {
            renderLimits()
        }
    }

    /// Seeds once; every later read goes through `adopt`, which never overwrites an edit.
    private func renderAgent() {
        switch store.readState(agentResource, \.agent) {
        case .loading:
            state.loadState.isAgentUnavailable = false
        case .failed:
            state.loadState.isAgentUnavailable = state.readModel == nil
        case .loaded(let detail):
            state.loadState.isAgentUnavailable = false
            guard detail.readModel != storeReadModel else { return }
            storeReadModel = detail.readModel
            // Its answer, or the read after a failure, is newer than this.
            guard !state.isWriting else { return }
            if state.readModel == nil {
                seedText(from: detail.readModel)
                state.loadState.readModel = detail.readModel
            } else {
                adopt(detail.readModel)
            }
        }
    }

    private func renderLimits() {
        switch store.readState(limitsResource, \.editSchema) {
        case .loading:
            state.loadState.hasFailedLimits = false
        case .failed:
            state.loadState.hasFailedLimits = true
        case .loaded(let schema):
            state.loadState.personaBounds = schema.persona
            state.loadState.hasFailedLimits = schema.persona == nil
        }
    }

    private func seedText(from readModel: AgentReadModel) {
        if let persona = readModel.persona {
            for field in AgentEditPersonaField.allCases {
                state.bindings[persona: field] = field.value(in: persona)
            }
            state.bindings.isCustomTone = AgentToneChoice.preset(matching: persona.tone) == nil
        }
        state.bindings.roleBrief = readModel.roleBrief ?? ""
        seedChoices(from: readModel)
    }
    
    private func seedChoices(from readModel: AgentReadModel) {
        state.bindings.showInSearch = readModel.visibility == "public"
        if let visitorPolicy = readModel.visitorPolicy {
            state.bindings.visitorPolicy = visitorPolicy
        }
        if let voiceLanguage = readModel.voiceLanguage {
            state.bindings.voiceLanguage = voiceLanguage
        }
    }

    /// Moves the baseline to what the server holds. A text the user hasn't
    /// edited follows the server; an edited one keeps the edit, so the next
    /// Save sends only what still differs.
    private func adopt(_ readModel: AgentReadModel) {
        guard let old = state.readModel else { return }
        if let oldPersona = old.persona, let persona = readModel.persona {
            for field in AgentEditPersonaField.allCases
                where state.bindings[persona: field].trimmedForPersona == field.value(in: oldPersona).trimmedForPersona {
                state.bindings[persona: field] = field.value(in: persona)
            }
        }
        if state.bindings.roleBrief.trimmedForPersona == (old.roleBrief ?? "").trimmedForPersona {
            state.bindings.roleBrief = readModel.roleBrief ?? ""
        }
        seedChoices(from: readModel)
        state.loadState.readModel = readModel
    }

    /// A choice: written at once. A failure says so quietly and the choice
    /// steps back to what the server holds.
    private func apply(_ patch: AgentEditPatch) async {
        state.isApplyingChoice = true
        defer { state.isApplyingChoice = false }
        
        switch await agentPlatformService.editAgent(agentID: state.card.agentID, patch: patch) {
        case .success(let readModel):
            adopt(readModel)
            // S5: every screen holding the agent shows the answer at once.
            storeReadModel = readModel
            store.agentEdited(readModel)
            actionsSubject.send(.changed)
        case .failure(let error):
            MXLog.error("Failed to apply an agent setting: \(error)")
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentEditFailure,
                                                                  icon: \.error))
            let revertingTone = patch.persona?.tone != nil
            // Back to what the server last confirmed, even if the re-read fails too.
            if let readModel = state.readModel {
                seedChoices(from: readModel)
                if revertingTone, let persona = readModel.persona {
                    showTone(persona.tone)
                }
            }
            await reread(revertingTone: revertingTone)
        }
    }

    private func save() async {
        let patch = state.textPatch
        guard state.canSave else { return }
        state.isSaving = true
        defer { state.isSaving = false }

        switch await agentPlatformService.editAgent(agentID: state.card.agentID, patch: patch) {
        case .success(let readModel):
            adopt(readModel)
            // S5: every screen holding the agent shows the answer at once.
            storeReadModel = readModel
            store.agentEdited(readModel)
            actionsSubject.send(.changed)
            userIndicatorController.submitIndicator(UserIndicator(type: .toast,
                                                                  title: UntranslatedL10n.screenAgentSettingsSaved,
                                                                  icon: \.checkCircle))
        case .failure(let error):
            MXLog.error("Failed to save agent settings: \(error)")
            state.bindings.alertInfo = AlertInfo(id: .saveFailed, title: UntranslatedL10n.screenAgentEditFailure)
            // Part of it may have landed (the PATCH isn't atomic).
            await reread(revertingTone: false)
        }
    }

    /// After a failure: the server's state again. The choices follow it; an
    /// unsaved text edit stays (or, for a failed tone preset, steps back).
    private func reread(revertingTone: Bool) async {
        await store.reread(agentResource)
        guard store.failures[agentResource] == nil, let readModel = store.value(agentResource)?.agent?.readModel else { return }
        if revertingTone, let persona = readModel.persona {
            showTone(persona.tone)
        }
        adopt(readModel)
    }
    
    private func showTone(_ tone: String) {
        state.bindings.tone = tone
        state.bindings.isCustomTone = AgentToneChoice.preset(matching: tone) == nil
    }

    private func cancel() {
        guard state.canSave else {
            actionsSubject.send(.dismiss)
            return
        }
        state.bindings.alertInfo = AlertInfo(id: .unsavedChanges,
                                             title: L10n.dialogUnsavedChangesTitle,
                                             message: L10n.dialogUnsavedChangesDescription,
                                             primaryButton: .init(title: L10n.actionSave) { [weak self] in Task { await self?.save() } },
                                             secondaryButton: .init(title: L10n.actionDiscard, role: .cancel) { [weak self] in self?.actionsSubject.send(.dismiss) })
    }
}
