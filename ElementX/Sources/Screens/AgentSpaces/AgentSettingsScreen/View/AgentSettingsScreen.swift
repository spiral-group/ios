//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

/// One of the agent's «Настройки» (decision 194). Choices apply at once;
/// text saves with «Сохранить» in the toolbar.
struct AgentSettingsScreen: View {
    @Bindable var context: AgentSettingsScreenViewModel.Context
    @FocusState private var focus: Bool

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

    @ViewBuilder
    private var content: some View {
        switch context.viewState.loadState {
        case .loading:
            DelayedProgressView()
        case .failure:
            Form {
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentEditLoadFailure) {
                    context.send(viewAction: .retry)
                }
            }
            .compoundList()
        case .loaded:
            Form {
                visitorPolicySection
                ForEach(context.viewState.personaFields, id: \.self) { field in
                    if field == .tone {
                        toneSection
                    } else {
                        textSection(title: field.title,
                                    text: personaBinding(field),
                                    count: context.viewState.personaLength(field),
                                    maxLength: context.viewState.personaBounds.map { field.bounds(in: $0).maxLength } ?? 0,
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
            }
            .compoundList()
        }
    }

    // MARK: Choices

    @ViewBuilder
    private var visitorPolicySection: some View {
        if context.viewState.visitorPolicy != nil {
            Section {
                ForEach(AgentVisitorPolicy.allCases, id: \.self) { policy in
                    ListRow(label: .plain(title: policy.title, description: policy.subtitle),
                            kind: .selection(isSelected: context.visitorPolicy == policy) {
                                context.send(viewAction: .setVisitorPolicy(policy))
                            })
                }
                .disabled(context.viewState.isWriting)
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
                ListRow(label: .default(title: UntranslatedL10n.screenAgentSettingsShowInSearch, icon: \.search),
                        kind: .toggle(Binding(get: { context.showInSearch },
                                              set: { context.send(viewAction: .setShowInSearch($0)) })))
                    .disabled(context.viewState.isWriting)
            } footer: {
                Text(UntranslatedL10n.screenAgentSettingsShowInSearchFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    @ViewBuilder
    private var voiceLanguageSection: some View {
        if context.viewState.voiceLanguage != nil {
            Section {
                ListRow(label: .default(title: UntranslatedL10n.screenAgentEditVoiceLanguage, icon: \.voiceCall),
                        kind: .picker(selection: Binding(get: { context.voiceLanguage },
                                                         set: { context.send(viewAction: .setVoiceLanguage($0)) }),
                                      items: AgentVoiceLanguage.allCases.map { (title: $0.title, tag: $0) }))
                    .disabled(context.viewState.isWriting)
            } footer: {
                Text(UntranslatedL10n.screenAgentEditVoiceLanguageFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    /// Tone as a choice plus «Свой вариант» (decision 192), free text on the wire.
    private var toneSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenAgentEditPersonaTone),
                    kind: .picker(selection: Binding(get: { context.viewState.toneChoice },
                                                     set: { context.send(viewAction: .selectTone($0)) }),
                                  items: AgentToneChoice.allCases.map { (title: $0.title, tag: $0) }))
                .disabled(context.viewState.isWriting)

            if context.viewState.toneChoice == .custom {
                ListRow(label: .plain(title: ""),
                        kind: .textField(text: $context.tone, axis: .vertical))
                    .focused($focus)
            }
        } footer: {
            if context.viewState.toneChoice == .custom {
                limitFooter(count: context.viewState.personaLength(.tone),
                            maxLength: context.viewState.personaBounds?.tone.maxLength ?? 0,
                            issue: context.viewState.personaIssue(.tone))
            }
        }
    }

    // MARK: Text

    /// The header names the field once; the footer is its limit, and says
    /// when it is the reason Save is off.
    private func textSection(title: String, text: Binding<String>, count: Int, maxLength: Int, issue: AgentEditPersonaIssue?) -> some View {
        Section {
            ListRow(label: .plain(title: ""),
                    kind: .textField(text: text, axis: .vertical))
                .focused($focus)
        } header: {
            Text(title)
                .compoundListSectionHeader()
        } footer: {
            limitFooter(count: count, maxLength: maxLength, issue: issue)
        }
    }

    private func limitFooter(count: Int, maxLength: Int, issue: AgentEditPersonaIssue?) -> some View {
        Group {
            switch issue {
            case .empty:
                Text(UntranslatedL10n.screenAgentEditPersonaEmpty)
            case .tooLong:
                Text(UntranslatedL10n.screenAgentEditPersonaTooLong(count, maxLength))
            case nil:
                Text(UntranslatedL10n.screenAgentEditPersonaCounter(count, maxLength))
            }
        }
        .foregroundStyle(issue == nil ? .compound.textSecondary : .compound.textCriticalPrimary)
        .compoundListSectionFooter()
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

struct AgentSettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let people = makeViewModel(section: .people)
    static let character = makeViewModel(section: .character)
    static let roleBrief = makeViewModel(section: .character, isRoleAgent: true)
    static let calls = makeViewModel(section: .calls)

    static var previews: some View {
        preview(people, name: "People")
        preview(character, name: "Character")
        preview(roleBrief, name: "Role brief")
        preview(calls, name: "Calls")
    }

    private static func preview(_ viewModel: AgentSettingsScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            AgentSettingsScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(section: AgentSettingsSection, isRoleAgent: Bool = false) -> AgentSettingsScreenViewModel {
        let card = isRoleAgent
            ? AgentSpaceAgentCard(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md", displayName: "Sales · Acme Corp",
                                  avatarMXC: nil, kind: "sales", visibility: "public", lifecycleState: "active",
                                  presence: .online, roomCount: 1, activeToolCount: 0)
            : AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                  avatarMXC: nil, kind: "personal_assistant", visibility: "private", lifecycleState: "active",
                                  presence: .online, roomCount: 2, activeToolCount: 1)
        let persona = PersonaView(agentID: card.agentID,
                                  ownerDisplayName: "Anna",
                                  tone: "Friendly",
                                  greeting: "Hi Anna! What can I do for you?",
                                  visitorGreeting: "Hello! I'm Anna's assistant.",
                                  toolUseEnabled: nil,
                                  model: nil,
                                  configVersionID: "cfg-1",
                                  versionNumber: 1)

        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(.init(agentID: card.agentID,
                                                                        kind: card.kind,
                                                                        displayName: .init(minLength: 1, maxLength: 64),
                                                                        persona: .init(ownerDisplayName: .init(minLength: 1, maxLength: 64),
                                                                                       tone: .init(minLength: 1, maxLength: 120),
                                                                                       greeting: .init(minLength: 1, maxLength: 500),
                                                                                       visitorGreeting: .init(minLength: 1, maxLength: 500))))
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: card.agentID,
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
                                                                       visitorPolicy: isRoleAgent ? nil : .askFirst))

        return AgentSettingsScreenViewModel(agent: card,
                                            section: section,
                                            agentPlatformService: service,
                                            userIndicatorController: UserIndicatorControllerMock())
    }
}
