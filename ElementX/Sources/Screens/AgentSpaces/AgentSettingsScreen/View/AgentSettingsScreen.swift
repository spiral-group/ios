//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

/// One of the agent's «Настройки» (decision 194). Choices apply at once;
/// text saves with «Сохранить» in the toolbar.
struct AgentSettingsScreen: View {
    @Bindable var context: AgentSettingsScreenViewModel.Context
    @FocusState private var focus: Bool

    /// What the server holds of the agent is known, so a value's slot can show it.
    private var isRead: Bool {
        context.viewState.readModel != nil
    }

    var body: some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(context.viewState.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(context.viewState.canSave)
            .toolbar { toolbar }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .alert(item: $context.alertInfo)
    }

    /// The final form from the first frame, filled from the store: a late value only fills its slot.
    @ViewBuilder
    private var content: some View {
        if context.viewState.loadState.isAgentUnavailable {
            Form {
                failureSection
            }
            .compoundList()
        } else {
            Form {
                visitorPolicySection
                ForEach(context.viewState.personaFields, id: \.self) { field in
                    if field == .tone {
                        toneSection
                    } else {
                        textSection(title: field.title,
                                    text: personaBinding(field),
                                    count: context.viewState.personaLength(field),
                                    maxLength: context.viewState.personaBounds.map { field.bounds(in: $0).maxLength },
                                    issue: context.viewState.personaIssue(field))
                    }
                }
                if context.viewState.showsRoleBrief {
                    textSection(title: UntranslatedL10n.screenCreateAgentRoleBriefSection,
                                text: $context.roleBrief,
                                count: context.viewState.roleBriefLength,
                                maxLength: AgentSettingsScreenViewState.roleBriefBounds.maxLength,
                                issue: context.viewState.roleBriefIssue)
                }
                searchSection
                voiceLanguageSection
                // Last, so that nothing moves: the values stay, and the store keeps trying.
                if context.viewState.loadState.hasFailedLimits {
                    failureSection
                }
            }
            .compoundList()
        }
    }

    private var failureSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentEditLoadFailure) {
            context.send(viewAction: .retry)
        }
    }

    // MARK: Choices

    @ViewBuilder
    private var visitorPolicySection: some View {
        if context.viewState.showsVisitorPolicy {
            Section {
                ForEach(AgentVisitorPolicy.allCases, id: \.self) { policy in
                    ListRow(label: .plain(title: policy.title, description: policy.subtitle),
                            kind: .selection(isSelected: context.visitorPolicy == policy) {
                                context.send(viewAction: .setVisitorPolicy(policy))
                            })
                }
                .disabled(context.viewState.isWriting)
                .allowsHitTesting(isRead)
            } header: {
                Text(UntranslatedL10n.screenAgentSettingsVisitorSection)
                    .compoundListSectionHeader()
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        if context.viewState.showsSearchToggle {
            Section {
                if isRead {
                    ListRow(label: .default(title: UntranslatedL10n.screenAgentSettingsShowInSearch, icon: \.search),
                            kind: .toggle(Binding(get: { context.showInSearch },
                                                  set: { context.send(viewAction: .setShowInSearch($0)) })))
                        .disabled(context.viewState.isWriting)
                } else {
                    // Not known yet, so neither on nor off. `ListRow` has no slot for it.
                    ListRow(kind: .custom {
                        HStack(spacing: 0) {
                            ListRowLabel.default(title: UntranslatedL10n.screenAgentSettingsShowInSearch, icon: \.search)
                            Spacer()
                            SpiralPreloader(label: L10n.commonLoading) {
                                SpiralPlaceholderToggle()
                            }
                        }
                        .padding(.trailing, ListRowPadding.horizontal)
                    })
                }
            } footer: {
                Text(UntranslatedL10n.screenAgentSettingsShowInSearchFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    @ViewBuilder
    private var voiceLanguageSection: some View {
        if context.viewState.showsVoiceLanguage {
            Section {
                if isRead {
                    ListRow(label: .default(title: UntranslatedL10n.screenAgentEditVoiceLanguage, icon: \.voiceCall),
                            kind: .picker(selection: Binding(get: { context.voiceLanguage },
                                                             set: { context.send(viewAction: .setVoiceLanguage($0)) }),
                                          items: AgentVoiceLanguage.allCases.map { (title: $0.title, tag: $0) }))
                        .disabled(context.viewState.isWriting)
                } else {
                    ListRow(label: .default(title: UntranslatedL10n.screenAgentEditVoiceLanguage, icon: \.voiceCall),
                            // The longest name, with room for the picker's arrows: the title wraps as it will.
                            details: .icon(valueSlot(AgentVoiceLanguage.uk.title + "000")),
                            kind: .label)
                }
            } footer: {
                Text(UntranslatedL10n.screenAgentEditVoiceLanguageFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    /// Tone as a choice plus «Свой вариант» (decision 192), free text on the wire.
    private var toneSection: some View {
        Section {
            if isRead {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentEditPersonaTone),
                        kind: .picker(selection: Binding(get: { context.viewState.toneChoice },
                                                         set: { context.send(viewAction: .selectTone($0)) }),
                                      items: AgentToneChoice.allCases.map { (title: $0.title, tag: $0) }))
                    .disabled(context.viewState.isWriting || !context.viewState.isTextEditable)

                if context.viewState.toneChoice == .custom {
                    textField($context.tone)
                }
            } else {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentEditPersonaTone),
                        details: .icon(valueSlot(AgentToneChoice.friendly.title)),
                        kind: .label)
            }
        } footer: {
            if isRead, context.viewState.toneChoice == .custom {
                limitFooter(count: context.viewState.personaLength(.tone),
                            maxLength: context.viewState.personaBounds?.tone.maxLength,
                            issue: context.viewState.personaIssue(.tone))
            }
        }
    }

    // MARK: Text

    /// The header names the field once; the footer is its limit, and says
    /// when it is the reason Save is off.
    private func textSection(title: String, text: Binding<String>, count: Int, maxLength: Int?, issue: AgentEditPersonaIssue?) -> some View {
        Section {
            if isRead {
                textField(text)
            } else {
                // A `Text`, as a redacted `TextField` may not draw as one.
                ListRow(kind: .custom {
                    valueSlot(String(repeating: "0", count: 24))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ListRowPadding.textFieldInsets)
                })
            }
        } header: {
            Text(title)
                .compoundListSectionHeader()
        } footer: {
            limitFooter(count: count, maxLength: maxLength, issue: issue)
        }
    }

    private func textField(_ text: Binding<String>) -> some View {
        ListRow(label: .plain(title: ""),
                kind: .textField(text: text, axis: .vertical))
            .focused($focus)
            .disabled(!context.viewState.isTextEditable)
    }

    /// Without its limit the counter is a slot: a made-up number is never read.
    private func limitFooter(count: Int, maxLength: Int?, issue: AgentEditPersonaIssue?) -> some View {
        let limit = maxLength ?? 500
        return Group {
            switch issue {
            case .empty:
                Text(UntranslatedL10n.screenAgentEditPersonaEmpty)
            case .tooLong:
                Text(UntranslatedL10n.screenAgentEditPersonaTooLong(count, limit))
            case nil:
                Text(UntranslatedL10n.screenAgentEditPersonaCounter(count, limit))
            }
        }
        .foregroundStyle(issue == nil ? .compound.textSecondary : .compound.textCriticalPrimary)
        .compoundListSectionFooter()
        .spiralLoadingSlot(!context.viewState.isTextEditable, label: L10n.commonLoading)
    }

    /// A value not read yet, in the place it will take. `standIn` gives the shape and is never shown.
    private func valueSlot(_ standIn: String) -> some View {
        Text(standIn)
            .lineLimit(1)
            .spiralLoadingSlot(true, label: L10n.commonLoading)
    }

    private func personaBinding(_ field: AgentEditPersonaField) -> Binding<String> {
        switch field {
        case .ownerDisplayName: $context.ownerDisplayName
        case .tone: $context.tone
        case .greeting: $context.greeting
        case .visitorGreeting: $context.visitorGreeting
        }
    }

    /// Only a screen with text has «Сохранить»; Cancel replaces the back
    /// chevron while there is something to save.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if context.viewState.hasText {
            ToolbarItem(placement: .cancellationAction) {
                if context.viewState.canSave {
                    Button(L10n.actionCancel) {
                        context.send(viewAction: .cancel)
                    }
                    .disabled(context.viewState.isSaving)
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionSave) {
                    focus = false
                    context.send(viewAction: .save)
                }
                .disabled(!context.viewState.canSave)
            }
        }
    }
}

// MARK: - Previews

struct AgentSettingsScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    /// How a read behaves in a preview.
    enum Read {
        case answers, neverAnswers, fails
    }

    static let people = makeViewModel(section: .people)
    static let character = makeViewModel(section: .character)
    static let roleBrief = makeViewModel(section: .character, isRoleAgent: true)
    static let calls = makeViewModel(section: .calls)
    // Brief 0083, question 359: the store holds the agent and the limits are on their way, then what a cold open shows.
    static let characterWaitingForLimits = makeViewModel(section: .character, limits: .neverAnswers)
    static let peopleLoading = makeViewModel(section: .people, agent: .neverAnswers, limits: .neverAnswers)
    static let characterLoading = makeViewModel(section: .character, agent: .neverAnswers, limits: .neverAnswers)
    static let callsLoading = makeViewModel(section: .calls, agent: .neverAnswers)
    static let limitsFailed = makeViewModel(section: .character, limits: .fails)
    static let failed = makeViewModel(section: .character, agent: .fails)

    static var previews: some View {
        preview(people, name: "People")
        preview(character, name: "Character")
        preview(roleBrief, name: "Role brief")
        preview(calls, name: "Calls")
        preview(characterWaitingForLimits, name: "Character waiting for its limits") { $0.readModel != nil }
        preview(peopleLoading, name: "People loading", isLoading: true)
        preview(characterLoading, name: "Character loading", isLoading: true)
        preview(callsLoading, name: "Calls loading", isLoading: true)
        preview(limitsFailed, name: "Limits failed") { $0.hasFailedLimits && $0.readModel != nil }
        preview(failed, name: "Failed") { $0.isAgentUnavailable }
    }

    /// `isReady`: when the screen is as the preview means to show it; by default once every read answered.
    private static func preview(_ viewModel: AgentSettingsScreenViewModel,
                                name: String,
                                isLoading: Bool = false,
                                isReady: (@Sendable (AgentSettingsScreenLoadState) -> Bool)? = nil) -> some View {
        let needsLimits = viewModel.context.viewState.needsPersonaBounds
        let isReady = isReady ?? { $0.readModel != nil && (!needsLimits || $0.personaBounds != nil) }
        return ElementNavigationStack {
            AgentSettingsScreen(context: viewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.loadState).map { isLoading || isReady($0) })
        .previewDisplayName(name)
    }

    static func makeViewModel(section: AgentSettingsSection, isRoleAgent: Bool = false, agent: Read = .answers, limits: Read = .answers) -> AgentSettingsScreenViewModel {
        let card = isRoleAgent
            ? AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md", displayName: "Sales · Acme Corp",
                                  avatarMXC: nil, kind: "sales", visibility: "public", lifecycleState: "active",
                                  roomCount: 1, activeToolCount: 0)
            : AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                  avatarMXC: nil, kind: "personal_assistant", visibility: "private", lifecycleState: "active",
                                  roomCount: 2, activeToolCount: 1)
        let persona = PersonaView(agentID: card.agentID,
                                  ownerDisplayName: "Anna",
                                  tone: "Friendly",
                                  greeting: "Hi Anna! What can I do for you?",
                                  visitorGreeting: "Hello! I'm Anna's assistant.",
                                  toolUseEnabled: nil,
                                  model: nil,
                                  configVersionID: "cfg-1",
                                  versionNumber: 1)

        let schema = AgentEditSchema(agentID: card.agentID,
                                     kind: card.kind,
                                     displayName: .init(minLength: 1, maxLength: 64),
                                     persona: .init(ownerDisplayName: .init(minLength: 1, maxLength: 64),
                                                    tone: .init(minLength: 1, maxLength: 120),
                                                    greeting: .init(minLength: 1, maxLength: 500),
                                                    visitorGreeting: .init(minLength: 1, maxLength: 500)))
        let readModel = AgentReadModel(agentID: card.agentID,
                                       matrixUserID: card.matrixUserID,
                                       displayName: card.displayName,
                                       avatarMXC: nil,
                                       kind: card.kind,
                                       visibility: card.visibility,
                                       lifecycleState: card.lifecycleState,
                                       organizationID: "org-1",
                                       roomCount: card.roomCount,
                                       activeToolCount: card.activeToolCount,
                                       configVersionNumber: 1,
                                       persona: isRoleAgent ? nil : persona,
                                       roleBrief: isRoleAgent ? "Qualify inbound leads and answer pricing questions." : nil,
                                       voiceLanguage: isRoleAgent ? nil : .uk,
                                       visitorPolicy: isRoleAgent ? nil : .askFirst)

        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDClosure = { _ in await answer(limits, with: schema) }
        service.fetchAgentReadModelAgentIDClosure = { _ in await answer(agent, with: readModel) }
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])

        return AgentSettingsScreenViewModel(agent: card,
                                            section: section,
                                            agentPlatformService: service,
                                            store: AgentsStore(service: service),
                                            userIndicatorController: UserIndicatorControllerMock())
    }

    private nonisolated static func answer<Value>(_ read: Read, with value: Value) async -> Result<Value, AgentPlatformError> {
        switch read {
        case .answers:
            return .success(value)
        case .fails:
            return .failure(.serverError(status: 500))
        case .neverAnswers:
            try? await Task.sleep(for: .seconds(3600))
            return .failure(.serverError(status: 500))
        }
    }
}
