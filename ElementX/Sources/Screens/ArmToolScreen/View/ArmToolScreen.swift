//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//

import Compound
import SFSafeSymbols
import SwiftUI

struct ArmToolScreen: View {
    @Bindable var context: ArmToolScreenViewModel.Context

    var body: some View {
        Form {
            exampleSection
            paramsSection
            if context.viewState.showsScopeSelector {
                scopeSection
            } else {
                fixedCallSection
            }
            if context.viewState.isEditing {
                turnOffSection
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083, question 359): the chat's other tool screens' cards.
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large, .medium])
        .navigationTitle(context.viewState.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .toolbar { toolbar }
        .interactiveDismissDisabled(context.viewState.isSubmitting)
    }

    // MARK: - Sections

    private var exampleSection: some View {
        Section {
            ToolExampleCard(example: context.viewState.example)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var paramsSection: some View {
        if context.viewState.kind.needsLanguage {
            Section {
                ListRow(label: .default(title: UntranslatedL10n.screenArmToolLanguageLabel, icon: \.translate),
                        details: .title(languageDescription, isWaiting: context.viewState.isLoadingLanguages),
                        kind: .navigationLink {
                            context.send(viewAction: .selectLanguage)
                        })
            } header: {
                whatSectionHeader
            }
        } else if context.viewState.kind.needsInstruction {
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenArmToolInstructionLabel),
                        kind: .textField(text: $context.instruction,
                                         axis: .vertical))
            } header: {
                whatSectionHeader
            } footer: {
                Text(UntranslatedL10n.screenArmToolInstructionFooter)
                    .compoundListSectionFooter()
            }
        }
    }

    private var whatSectionHeader: some View {
        Text(UntranslatedL10n.screenArmToolWhatSectionTitle)
            .compoundListSectionHeader()
    }

    private var scopeSection: some View {
        Section {
            ForEach(ArmToolScope.offered(current: context.scope)) { scope in
                ListRow(label: .plain(title: scope.title),
                        kind: .selection(isSelected: context.scope == scope) {
                            context.scope = scope
                        })
            }
            if context.viewState.bindings.scope.requiresMembers {
                ListRow(label: .default(title: UntranslatedL10n.screenArmToolMembersLabel,
                                        description: membersDescription,
                                        icon: \.userProfile),
                        kind: .navigationLink {
                            context.send(viewAction: .selectMembers)
                        })
            }
        } header: {
            Text(UntranslatedL10n.screenArmToolWhoSectionTitle)
                .compoundListSectionHeader()
        }
    }

    private var fixedCallSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenArmToolCallAudienceTitle,
                                    description: UntranslatedL10n.screenArmToolCallAudienceSubtitle,
                                    icon: \.voiceCall),
                    kind: .label)
        } footer: {
            if let disclosure = callDisclosure {
                Text(disclosure)
                    .compoundListSectionFooter()
            }
        }
    }

    /// Copy telling the owner what happens to the room's voice calls once
    /// this tool is on (summarised / recorded, and — for recording — posted
    /// back as an audio file).
    private var callDisclosure: String? {
        switch context.viewState.kind {
        case .callSummary: UntranslatedL10n.screenArmToolCallSummaryDisclosure
        case .callRecording: UntranslatedL10n.screenArmToolCallRecordingDisclosure
        default: nil
        }
    }

    private var turnOffSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenArmToolTurnOff,
                                    systemIcon: .power,
                                    role: .destructive),
                    details: context.viewState.isSubmitting ? .isWaiting(true) : nil,
                    kind: .button {
                        context.send(viewAction: .turnOff)
                    })
                    .disabled(context.viewState.isSubmitting)
        }
    }

    private var membersDescription: String {
        let members = context.viewState.bindings.members
        if members.isEmpty {
            return UntranslatedL10n.screenArmToolMembersNone
        }
        return members.joined(separator: ", ")
    }

    private var languageDescription: String {
        let code = context.viewState.bindings.language
        guard !code.isEmpty else { return UntranslatedL10n.screenArmToolLanguageChoose }
        return context.viewState.displayName(forLanguageCode: code)
    }

    /// The screen is always pushed onto the flow's sheet stack, so the system
    /// back button already dismisses it — no explicit cancel/close item (that
    /// would be a duplicate "X" next to the "<").
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ToolScreenTitle(title: context.viewState.kind.title, subtitle: context.viewState.agentDisplayName)
        }
        ToolbarItem(placement: .confirmationAction) {
            // AGENT-PLATFORM: a visible "Turn on" word, not a bare ✓ disc.
            Button(confirmTitle) {
                context.send(viewAction: .submit)
            }
            // AGENT-PLATFORM (decision 306): the filled blue, not the window tint (#0A84FF, 3.65:1 under white in dark).
            .backportButtonStyleGlassProminent(tint: .compound.bgActionPrimaryRest)
            .disabled(!context.viewState.canSubmit)
        }
    }

    private var confirmTitle: String {
        context.viewState.isEditing ? L10n.actionSave : UntranslatedL10n.screenArmToolConfirm
    }
}

// MARK: - Presentation

private extension ArmToolScope {
    var title: String {
        switch self {
        case .anyone: return UntranslatedL10n.screenArmToolScopeAnyone
        case .nonSelfNonOwner: return UntranslatedL10n.screenArmToolScopeOthers
        case .ownerOnly: return UntranslatedL10n.screenArmToolScopeOwner
        case .specificSenders: return UntranslatedL10n.screenArmToolScopeSpecific
        case .everyoneExcept: return UntranslatedL10n.screenArmToolScopeExcept
        }
    }
}

// MARK: - Previews

struct ArmToolScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let translateViewModel = makeViewModel(kind: .translate)
    static let simplifyViewModel = makeViewModel(kind: .simplify)
    static let correctViewModel = makeViewModel(kind: .correct)
    static let customViewModel = makeViewModel(kind: .custom)
    static let summaryViewModel = makeViewModel(kind: .callSummary)
    static let recordingViewModel = makeViewModel(kind: .callRecording)
    static let editViewModel = makeViewModel(editing: .init(RoomToolView(toolID: "t1",
                                                                         toolKind: "translate",
                                                                         triggerKind: "on_message",
                                                                         targetLanguage: "ru",
                                                                         params: .translate(targetLanguage: "ru"),
                                                                         trigger: .onMessage(senderScope: .anyone),
                                                                         safeSliceSalt: "t1",
                                                                         appliesToViewer: .yes)))

    static var previews: some View {
        ElementNavigationStack {
            ArmToolScreen(context: editViewModel.context)
        }
        .snapshotPreferences(expect: hasCatalog(editViewModel))
        .previewDisplayName("Edit")

        ElementNavigationStack {
            ArmToolScreen(context: translateViewModel.context)
        }
        .snapshotPreferences(expect: hasCatalog(translateViewModel))
        .previewDisplayName("Translate")

        ElementNavigationStack {
            ArmToolScreen(context: simplifyViewModel.context)
        }
        .previewDisplayName("Simplify")

        ElementNavigationStack {
            ArmToolScreen(context: correctViewModel.context)
        }
        .previewDisplayName("Correct")

        ElementNavigationStack {
            ArmToolScreen(context: customViewModel.context)
        }
        .previewDisplayName("Custom")

        ElementNavigationStack {
            ArmToolScreen(context: summaryViewModel.context)
        }
        .previewDisplayName("Call summary")

        ElementNavigationStack {
            ArmToolScreen(context: recordingViewModel.context)
        }
        .previewDisplayName("Call recording")
    }

    private static func hasCatalog(_ viewModel: ArmToolScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.isLoadingLanguages).map { !$0 }
    }

    private static func makeViewModel(kind: AgentToolKind) -> ArmToolScreenViewModel {
        let service = makeService()
        return ArmToolScreenViewModel(roomID: "!room:example.com",
                                      agentID: "agent-1",
                                      agentDisplayName: "Aria",
                                      kind: kind,
                                      agentPlatformService: service,
                                      store: AgentsStore(service: service))
    }

    private static func makeViewModel(editing tool: ActiveToolDetail?) -> ArmToolScreenViewModel {
        guard let tool else { fatalError("The preview's tool is the owner's") }
        let service = makeService()
        guard let viewModel = ArmToolScreenViewModel(roomID: "!room:example.com",
                                                     agentID: "agent-1",
                                                     agentDisplayName: "Aria",
                                                     editing: tool,
                                                     agentPlatformService: service,
                                                     store: AgentsStore(service: service)) else {
            fatalError("The preview's tool is of a known kind")
        }
        return viewModel
    }

    /// An unconfigured mock method fatal-errors on a background task, which kills the whole PreviewTests process.
    private static func makeService() -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                      roomID: "!room:example.com",
                                                                                      paramsSchema: [:],
                                                                                      triggerSchema: [:],
                                                                                      textTranslationLanguages: [],
                                                                                      voiceTranslationLanguages: [],
                                                                                      availableToolKinds: AgentToolKind.allCases.map(\.rawValue)))
        return service
    }
}
