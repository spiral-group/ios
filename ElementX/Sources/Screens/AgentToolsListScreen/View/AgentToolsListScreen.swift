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

struct AgentToolsListScreen: View {
    @Bindable var context: AgentToolsListScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                skeletonSection
            case .loaded where context.viewState.isLoadedEmpty:
                emptySection
            case .loaded:
                toolsSection
            case .failed:
                errorSection
            }

            if !context.viewState.isLoading {
                addToolSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenAgentToolsListTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .retry) }
        .onAppear { context.send(viewAction: .appeared) }
        .toolbar { toolbar }
    }

    // MARK: - Sections

    private var skeletonSection: some View {
        Section {
            ForEach(0..<2, id: \.self) { _ in
                ListRow(label: .default(title: "Translate → English",
                                        description: "Everyone",
                                        icon: \.translate),
                        kind: .label)
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
        .disabled(true)
        .accessibilityRepresentation { Text(L10n.commonLoading) }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Text(UntranslatedL10n.screenAgentToolsListEmptyTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenAgentToolsListEmptySubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var toolsSection: some View {
        Section {
            ForEach(context.viewState.tools) { tool in
                ListRow(label: .default(title: tool.title,
                                        description: tool.canFire ? tool.subtitle : UntranslatedL10n.screenAgentCapabilitiesUnavailableSubtitle,
                                        icon: tool.capability.icon),
                        details: tool.canFire ? nil : .title(UntranslatedL10n.screenAgentCapabilitiesUnavailable),
                        kind: .navigationLink {
                            context.send(viewAction: .selectTool(id: tool.id))
                        })
            }
        } header: {
            // "On" would be untrue of a row that says it doesn't run.
            Text(context.viewState.tools.allSatisfy(\.canFire)
                ? UntranslatedL10n.screenAgentToolsListSectionTitle
                : UntranslatedL10n.screenAgentToolsListSectionTitleMixed)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenAgentToolsListSectionFooter(context.viewState.agentDisplayName))
                .compoundListSectionFooter()
        }
    }

    private var addToolSection: some View {
        Section {
            ListRow(label: .action(title: UntranslatedL10n.screenAgentToolsListAdd,
                                   icon: \.plus),
                    kind: .button {
                        context.send(viewAction: .addTool)
                    })
        }
    }

    private var errorSection: some View {
        Section {
            VStack(spacing: 16) {
                Text(L10n.errorUnknown)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
                Button(L10n.actionRetry) { context.send(viewAction: .retry) }
                    .buttonStyle(.compound(.secondary, size: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionDone) { context.send(viewAction: .done) }
        }
    }
}

// MARK: - Previews

struct AgentToolsListScreen_Previews: PreviewProvider, TestablePreview {
    static let loadedViewModel = makeViewModel(tools: [
        RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                     targetLanguage: "English",
                     params: .translate(targetLanguage: "English"),
                     trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1"),
        RoomToolView(toolID: "t2", toolKind: "rephrase", triggerKind: "on_message",
                     targetLanguage: nil,
                     params: .rephrase(instruction: "more polite"),
                     trigger: .onMessage(senderScope: .everyoneExcept(members: ["@bob:host"])), safeSliceSalt: "t2"),
        RoomToolView(toolID: "t3", toolKind: "call_recording", triggerKind: "on_voice_call",
                     targetLanguage: nil, params: .callRecording,
                     trigger: .onVoiceCall(speakerScope: .anyone), safeSliceSalt: "t3")
    ])
    /// A company agent (decision 168): an old call tool the server still
    /// lists is shown as not available.
    static let companyAgentViewModel = makeViewModel(tools: [
        RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                     targetLanguage: "English",
                     params: .translate(targetLanguage: "English"),
                     trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1"),
        RoomToolView(toolID: "t3", toolKind: "call_summary", triggerKind: "on_voice_call",
                     targetLanguage: nil, params: .callSummary,
                     trigger: .onVoiceCall(speakerScope: .anyone), safeSliceSalt: "t3")
    ], availableToolKinds: ["translate", "simplify", "correct", "rephrase", "summarize", "custom"])
    static let emptyViewModel = makeViewModel(tools: [])
    static let loadingViewModel = makeViewModel(tools: nil)

    static var previews: some View {
        ElementNavigationStack {
            AgentToolsListScreen(context: loadedViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(loadedViewModel))
        .previewDisplayName("Loaded")

        ElementNavigationStack {
            AgentToolsListScreen(context: companyAgentViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(companyAgentViewModel))
        .previewDisplayName("Company agent")

        ElementNavigationStack {
            AgentToolsListScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(emptyViewModel))
        .previewDisplayName("Empty")

        ElementNavigationStack {
            AgentToolsListScreen(context: loadingViewModel.context)
        }
        .previewDisplayName("Loading")
    }

    /// The loaded states wait for their two reads; until then their
    /// snapshots showed the loading skeleton.
    private static func hasLoaded(_ viewModel: AgentToolsListScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } }
    }

    /// Configures the mock so `.appeared` resolves into the wanted state
    /// (nil → stays loading), mirroring the upstream mock-driven preview
    /// idiom rather than mutating the read-only view state.
    private static func makeViewModel(tools: [RoomToolView]?,
                                      availableToolKinds: [String] = ["translate", "simplify", "correct", "rephrase", "summarize", "custom",
                                                                      "live_translate", "call_summary", "call_recording"]) -> AgentToolsListScreenViewModel {
        let service = AgentPlatformServiceMock()
        // Read on every load; an unconfigured mock method would crash the preview process.
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                      roomID: "!room:example.com",
                                                                                      paramsSchema: [:],
                                                                                      triggerSchema: [:],
                                                                                      textTranslationLanguages: [],
                                                                                      voiceTranslationLanguages: [],
                                                                                      availableToolKinds: availableToolKinds))
        if let tools {
            service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: "!room:example.com",
                                                                             agents: [RoomToolAgentEntry(agentID: "agent-1",
                                                                                                         matrixUserID: "@agent:example.com",
                                                                                                         displayName: "Aria",
                                                                                                         ownerUserID: "@owner:example.com",
                                                                                                         isMine: true,
                                                                                                         tools: tools)]))
        } else {
            service.fetchRoomToolsRoomIDClosure = { _ in
                try? await Task.sleep(for: .seconds(60))
                return .failure(.serverError(status: 0))
            }
        }
        let viewModel = AgentToolsListScreenViewModel(roomID: "!room:example.com",
                                                      agentID: "agent-1",
                                                      agentDisplayName: "Aria",
                                                      agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        return viewModel
    }
}
