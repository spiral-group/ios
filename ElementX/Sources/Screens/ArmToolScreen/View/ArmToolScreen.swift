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
import SwiftUI

struct ArmToolScreen: View {
    @Bindable var context: ArmToolScreenViewModel.Context

    var body: some View {
        Form {
            if context.viewState.showsKindPicker {
                kindSection
            }
            paramsSection
            if context.viewState.showsScopeSelector {
                scopeSection
            } else {
                fixedCallSection
            }
            if context.viewState.hasActiveTool {
                turnOffSection
            }
        }
        .compoundList()
        .scrollBounceBehavior(.basedOnSize)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large, .medium])
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .toolbar { toolbar }
        .interactiveDismissDisabled(context.viewState.isSubmitting)
    }

    /// The title follows the chosen action (step B.5), in a create or an edit.
    private var title: String {
        switch context.viewState.capability {
        case .translateMessages: return context.viewState.bindings.kind.bannerTitle
        case .liveCallTranslation: return UntranslatedL10n.screenArmToolLiveCallTitle
        case .callSummary: return UntranslatedL10n.screenArmToolCallSummaryTitle
        case .callRecording: return UntranslatedL10n.screenArmToolCallRecordingTitle
        }
    }

    // MARK: - Sections

    private var kindSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenArmToolKindLabel),
                    kind: .inlinePicker(selection: $context.kind,
                                        items: ArmToolKind.allCases.map { (title: $0.title, tag: $0) }))
        } header: {
            Text(UntranslatedL10n.screenArmToolWhatSectionTitle)
                .compoundListSectionHeader()
        }
    }

    @ViewBuilder
    private var paramsSection: some View {
        if context.viewState.isLiveTranslation {
            liveTranslationSection
        } else if let row = context.viewState.textParamsRow {
            // Always one row and a footer, whichever kind is picked, so the
            // rows below never move under the finger (re-walk R5).
            Section {
                switch row {
                case .language:
                    ListRow(label: .default(title: UntranslatedL10n.screenArmToolLanguageLabel,
                                            description: languageDescription,
                                            icon: \.translate),
                            kind: .navigationLink {
                                context.send(viewAction: .selectLanguage(index: nil))
                            })
                case .instruction:
                    ListRow(label: .plain(title: UntranslatedL10n.screenArmToolInstructionLabel),
                            kind: .textField(text: $context.instruction,
                                             axis: .vertical))
                case .nothingToSet:
                    ListRow(label: .plain(title: UntranslatedL10n.screenArmToolNoSettings),
                            kind: .label)
                }
            } footer: {
                Text(textParamsFooter(row))
                    .compoundListSectionFooter()
            }
        }
    }

    private func textParamsFooter(_ row: ArmToolParamsRow) -> String {
        switch row {
        case .language: UntranslatedL10n.screenArmToolLanguageFooter
        case .instruction: UntranslatedL10n.screenArmToolInstructionFooter
        case .nothingToSet: UntranslatedL10n.screenArmToolNoSettingsFooter
        }
    }

    private var liveTranslationSection: some View {
        Section {
            ForEach(Array(context.viewState.bindings.targetLanguages.enumerated()), id: \.offset) { index, language in
                ListRow(label: .default(title: context.viewState.displayName(forLanguageCode: language),
                                        icon: \.translate),
                        kind: .navigationLink {
                            context.send(viewAction: .selectLanguage(index: index))
                        })
                        .swipeActions {
                            Button(L10n.actionRemove, role: .destructive) {
                                context.send(viewAction: .removeLanguage(index: index))
                            }
                        }
            }
            .onMove { offsets, destination in
                context.send(viewAction: .moveLanguages(fromOffsets: offsets, toOffset: destination))
            }
            ListRow(label: .action(title: UntranslatedL10n.screenArmToolLanguageAdd,
                                   icon: \.plus),
                    kind: .button {
                        context.send(viewAction: .selectLanguage(index: nil))
                    })
            ListRow(label: .plain(title: UntranslatedL10n.screenArmToolStyleLabel),
                    kind: .inlinePicker(selection: $context.liveStyle,
                                        items: LiveTranslationStyle.pickerItems))
        } footer: {
            Text(UntranslatedL10n.screenArmToolLanguagesFooter)
                .compoundListSectionFooter()
        }
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
    /// this parameterless capability is armed (summarised / recorded, and —
    /// for recording — posted back as an audio file).
    private var callDisclosure: String? {
        switch context.viewState.capability {
        case .callSummary: return UntranslatedL10n.screenArmToolCallSummaryDisclosure
        case .callRecording: return UntranslatedL10n.screenArmToolCallRecordingDisclosure
        case .translateMessages, .liveCallTranslation: return nil
        }
    }

    private var turnOffSection: some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenArmToolTurnOff,
                                    icon: \.close,
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
        if context.viewState.isLiveTranslation, context.viewState.bindings.targetLanguages.count > 1 {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            // AGENT-PLATFORM: a visible "Turn on" word, not a bare ✓ disc.
            Button(confirmTitle) {
                context.send(viewAction: .submit)
            }
            .backportButtonStyleGlassProminent()
            .disabled(!context.viewState.canSubmit)
        }
    }

    private var confirmTitle: String {
        context.viewState.isEditing ? L10n.actionSave : UntranslatedL10n.screenArmToolConfirm
    }
}

// MARK: - Presentation

private extension ArmToolKind {
    /// Alias of `bannerTitle` (shared with the tools banner, Brief 0044).
    var title: String {
        bannerTitle
    }
}

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

private extension LiveTranslationStyle {
    static var pickerItems: [(title: String, tag: LiveTranslationStyle)] {
        [(title: UntranslatedL10n.screenArmToolStyleSimultaneous, tag: .simultaneous),
         (title: UntranslatedL10n.screenArmToolStyleConsecutive, tag: .consecutive)]
    }
}

// MARK: - Previews

struct ArmToolScreen_Previews: PreviewProvider, TestablePreview {
    // AGENT-PLATFORM: the view model fetches the tools catalog at init, and
    // an unconfigured mock method fatal-errors by design — on a background
    // task, which kills the whole PreviewTests process and fails whichever
    // unrelated test happens to be running. Always hand the previews a
    // configured service.
    static func makeService() -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                      roomID: "!room:example.com",
                                                                                      paramsSchema: [:],
                                                                                      triggerSchema: [:],
                                                                                      textTranslationLanguages: [],
                                                                                      voiceTranslationLanguages: [],
                                                                                      availableToolKinds: []))
        return service
    }

    static let translateViewModel = makeViewModel(capability: .translateMessages, active: nil)
    static let liveViewModel = makeViewModel(capability: .liveCallTranslation, active: nil)
    static let summaryViewModel = makeViewModel(capability: .callSummary, active: nil)
    static let recordingViewModel = makeViewModel(capability: .callRecording, active: nil)
    static let activeViewModel = makeViewModel(capability: .translateMessages,
                                               active: ActiveCapabilityTool(toolIDs: ["t1"], summary: "Translating to English", count: 1))
    static let editViewModel = ArmToolScreenViewModel(roomID: "!room:example.com",
                                                      agentID: "agent-1",
                                                      agentDisplayName: "Aria",
                                                      editing: ActiveToolDetail(toolID: "t1",
                                                                                capability: .translateMessages,
                                                                                params: .translate(targetLanguage: "English"),
                                                                                trigger: .onMessage(senderScope: .everyoneExcept(members: ["@bob:host"])),
                                                                                title: "Translate → English",
                                                                                subtitle: "Everyone except @bob:host"),
                                                      agentPlatformService: makeService())

    static var previews: some View {
        ElementNavigationStack {
            ArmToolScreen(context: translateViewModel.context)
        }
        .previewDisplayName("Translate")

        ElementNavigationStack {
            ArmToolScreen(context: liveViewModel.context)
        }
        .previewDisplayName("Live call")

        ElementNavigationStack {
            ArmToolScreen(context: summaryViewModel.context)
        }
        .previewDisplayName("Call summary")

        ElementNavigationStack {
            ArmToolScreen(context: recordingViewModel.context)
        }
        .previewDisplayName("Call recording")

        ElementNavigationStack {
            ArmToolScreen(context: activeViewModel.context)
        }
        .previewDisplayName("With active tool")

        ElementNavigationStack {
            ArmToolScreen(context: editViewModel.context)
        }
        .previewDisplayName("Edit")
    }

    private static func makeViewModel(capability: AgentCapability,
                                      active: ActiveCapabilityTool?) -> ArmToolScreenViewModel {
        ArmToolScreenViewModel(roomID: "!room:example.com",
                               agentID: "agent-1",
                               agentDisplayName: "Aria",
                               capability: capability,
                               active: active,
                               agentPlatformService: makeService())
    }
}
