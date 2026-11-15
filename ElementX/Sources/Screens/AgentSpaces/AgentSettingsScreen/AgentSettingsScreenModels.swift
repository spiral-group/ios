//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Agents tab step B, decision 194): one of the agent's
// «Настройки» rows — «Общение с людьми», «Характер» («Описание роли» for a
// role agent) or «Звонки». Choices apply at once and step back on a failure;
// text saves with «Сохранить». Every write is the one `PATCH /agents/{id}`
// with only what changed, re-read after a failure.
//

import Foundation

enum AgentSettingsSection: Hashable {
    /// How the agent treats people who aren't the owner.
    case people
    /// The assistant's character, or a role agent's brief.
    case character
    /// The assistant's call and summary language.
    case calls
}

enum AgentSettingsScreenViewModelAction {
    /// A write landed; what the agent screen shows may have changed.
    case changed
    /// Cancel: the flow pops the screen.
    case dismiss
}

struct AgentSettingsScreenViewState: BindableState {
    let card: AgentSpaceAgentCard
    let section: AgentSettingsSection

    var loadState = AgentSettingsScreenLoadState()
    var isSaving = false
    /// A choice's PATCH is on its way; the next choice waits for it.
    var isApplyingChoice = false
    var bindings = AgentSettingsScreenViewStateBindings()

    var title: String {
        switch section {
        case .people: UntranslatedL10n.screenAgentSettingsPeopleTitle
        case .character: card.isPersonalAssistant ? UntranslatedL10n.screenAgentEditPersonaSection : UntranslatedL10n.screenCreateAgentRoleBriefSection
        case .calls: UntranslatedL10n.screenAgentSettingsCallsTitle
        }
    }

    var readModel: AgentReadModel? {
        loadState.readModel
    }

    var personaBounds: AgentEditSchema.PersonaBounds? {
        loadState.personaBounds
    }

    // MARK: Rows the section has

    // The section and the card decide them, so the form has its shape before any read. A read only takes a row
    // away for a value the server didn't give, or one this build doesn't know.

    /// The person's own fields here, in screen order.
    var personaFields: [AgentEditPersonaField] {
        guard card.isPersonalAssistant else { return [] }
        switch section {
        case .people: return [.visitorGreeting]
        case .character: return [.ownerDisplayName, .tone, .greeting]
        case .calls: return []
        }
    }

    var showsRoleBrief: Bool {
        section == .character && !card.isPersonalAssistant
    }

    var showsVisitorPolicy: Bool {
        section == .people && card.isPersonalAssistant && (readModel == nil || readModel?.visitorPolicy != nil)
    }

    var visitorPolicy: AgentVisitorPolicy? {
        guard section == .people else { return nil }
        return readModel?.visitorPolicy
    }

    /// Whether the screen has text, and so «Сохранить».
    var hasText: Bool {
        !personaFields.isEmpty || showsRoleBrief
    }
    
    var showsSearchToggle: Bool {
        section == .people
    }

    var showsVoiceLanguage: Bool {
        section == .calls && card.isPersonalAssistant && (readModel == nil || readModel?.voiceLanguage != nil)
    }

    var voiceLanguage: AgentVoiceLanguage? {
        guard section == .calls, card.isPersonalAssistant else { return nil }
        return readModel?.voiceLanguage
    }

    /// The assistant's text needs its limits; without them a field can't be checked.
    var needsPersonaBounds: Bool {
        card.isPersonalAssistant && section != .calls
    }

    // MARK: Text

    /// A field can't be compared without what the server holds, nor checked without its limits.
    var isTextEditable: Bool {
        guard let readModel else { return false }
        return !card.isPersonalAssistant || (readModel.persona != nil && personaBounds != nil)
    }

    var toneChoice: AgentToneChoice {
        if bindings.isCustomTone { return .custom }
        return AgentToneChoice.preset(matching: bindings[persona: .tone]) ?? .custom
    }

    func personaLength(_ field: AgentEditPersonaField) -> Int {
        bindings[persona: field].trimmedForPersona.unicodeScalars.count
    }

    /// Only a changed field can block Save; an untouched one is never sent.
    func personaIssue(_ field: AgentEditPersonaField) -> AgentEditPersonaIssue? {
        guard let bounds = personaBounds, personaDidChange(field) else { return nil }
        return AgentEditPersonaIssue(value: bindings[persona: field], bounds: field.bounds(in: bounds))
    }

    func personaDidChange(_ field: AgentEditPersonaField) -> Bool {
        guard let persona = readModel?.persona else { return false }
        return bindings[persona: field].trimmedForPersona != field.value(in: persona).trimmedForPersona
    }

    /// The server's role-brief bounds (`CreateAgentInput.role_brief`).
    static let roleBriefBounds = AgentEditSchema.FieldBounds(minLength: 1, maxLength: 500)

    var roleBriefLength: Int {
        bindings.roleBrief.trimmedForPersona.unicodeScalars.count
    }

    var roleBriefDidChange: Bool {
        showsRoleBrief && bindings.roleBrief.trimmedForPersona != (readModel?.roleBrief ?? "").trimmedForPersona
    }

    var roleBriefIssue: AgentEditPersonaIssue? {
        guard roleBriefDidChange else { return nil }
        return AgentEditPersonaIssue(value: bindings.roleBrief, bounds: Self.roleBriefBounds)
    }

    /// The text this screen would send: only the changed fields.
    var textPatch: AgentEditPatch {
        var persona = AgentEditPatch.Persona()
        for field in personaFields where personaDidChange(field) {
            persona[field] = bindings[persona: field].trimmedForPersona
        }
        return AgentEditPatch(persona: persona.isEmpty ? nil : persona,
                              roleBrief: roleBriefDidChange ? bindings.roleBrief.trimmedForPersona : nil)
    }

    /// One write at a time, so what is shown ends as what the server holds.
    var isWriting: Bool {
        isSaving || isApplyingChoice
    }

    var canSave: Bool {
        !isWriting
            && isTextEditable
            && !textPatch.isEmpty
            && personaFields.allSatisfy { personaIssue($0) == nil }
            && roleBriefIssue == nil
    }
}

/// What the form is filled from. The form never waits for it, and only `isAgentUnavailable` replaces it.
nonisolated struct AgentSettingsScreenLoadState: Equatable {
    /// The agent as the server holds it, the baseline of every write; `nil` until read.
    var readModel: AgentReadModel?
    /// The assistant's text limits; `nil` until read, and on a screen without that text.
    var personaBounds: AgentEditSchema.PersonaBounds?
    /// The agent's read failed and nothing is held: there is nothing to show.
    var isAgentUnavailable = false
    /// The limits' read failed: the values show and the text stays closed.
    var hasFailedLimits = false
}

struct AgentSettingsScreenViewStateBindings {
    var ownerDisplayName = ""
    var tone = ""
    var greeting = ""
    var visitorGreeting = ""
    /// «Свой вариант» picked: the tone is typed, even when it reads like a preset.
    var isCustomTone = false
    var roleBrief = ""
    /// The choices as shown: set at once on a tap, stepped back on a failure.
    var visitorPolicy: AgentVisitorPolicy?
    var showInSearch = false
    var voiceLanguage: AgentVoiceLanguage = .en
    var alertInfo: AlertInfo<AgentSettingsScreenAlertType>?

    subscript(persona field: AgentEditPersonaField) -> String {
        get {
            switch field {
            case .ownerDisplayName: ownerDisplayName
            case .tone: tone
            case .greeting: greeting
            case .visitorGreeting: visitorGreeting
            }
        }
        set {
            switch field {
            case .ownerDisplayName: ownerDisplayName = newValue
            case .tone: tone = newValue
            case .greeting: greeting = newValue
            case .visitorGreeting: visitorGreeting = newValue
            }
        }
    }
}

enum AgentSettingsScreenAlertType: Hashable {
    case saveFailed
    case unsavedChanges
}

enum AgentSettingsScreenViewAction {
    case setVisitorPolicy(AgentVisitorPolicy)
    case setShowInSearch(Bool)
    case setVoiceLanguage(AgentVoiceLanguage)
    case selectTone(AgentToneChoice)
    case save
    case cancel
    case retry
}

extension AgentSettingsScreenViewAction {
    /// A choice that is written the moment it is made.
    var writesAtOnce: Bool {
        switch self {
        case .setVisitorPolicy, .setShowInSearch, .setVoiceLanguage: true
        case .selectTone(let choice): choice.value != nil
        case .save, .cancel, .retry: false
        }
    }
}
