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

struct AgentCapabilitiesScreen: View {
    @Bindable var context: AgentCapabilitiesScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                skeletonSection
            case .loaded:
                capabilitiesSection
                    .accessibilityIdentifier(A11yIdentifiers.agentCapabilitiesScreen.list)
            case .failed:
                errorSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenAgentCapabilitiesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .retry) }
        .onAppear { context.send(viewAction: .appeared) }
        .toolbar { toolbar }
    }

    // MARK: - Sections

    private var skeletonSection: some View {
        Section {
            ForEach(AgentCapability.allCases) { capability in
                ListRow(label: .default(title: capability.title,
                                        description: "Loading",
                                        icon: capability.icon),
                        kind: .label)
            }
        }
        .redacted(reason: .placeholder)
        .shimmer()
        .disabled(true)
        .accessibilityRepresentation { Text(L10n.commonLoading) }
    }

    private var capabilitiesSection: some View {
        Section {
            ForEach(context.viewState.offeredCapabilities) { capability in
                let active = context.viewState.activeTool(for: capability)
                let isUnavailable = context.viewState.isUnavailable(capability)
                ListRow(label: .default(title: capability.title,
                                        description: isUnavailable ? UntranslatedL10n.screenAgentCapabilitiesUnavailableSubtitle : rowDescription(for: capability, active: active),
                                        icon: capability.icon),
                        details: .title(rowDetails(active: active, isUnavailable: isUnavailable)),
                        kind: .navigationLink {
                            context.send(viewAction: .selectCapability(capability))
                        })
            }
        } header: {
            Text(UntranslatedL10n.screenAgentCapabilitiesSectionTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenAgentCapabilitiesSectionFooter(context.viewState.agentDisplayName))
                .compoundListSectionFooter()
        }
    }

    /// On, Off, or — for a tool the server lists but that can't fire here
    /// (decision 168) — neither: it doesn't run, whatever was armed.
    private func rowDetails(active: ActiveCapabilityTool?, isUnavailable: Bool) -> String {
        if isUnavailable { return UntranslatedL10n.screenAgentCapabilitiesUnavailable }
        return active == nil ? UntranslatedL10n.commonOff : UntranslatedL10n.commonOn
    }

    /// The row's secondary line: the active summary when the capability
    /// is on, otherwise the capability's static one-line description.
    private func rowDescription(for capability: AgentCapability, active: ActiveCapabilityTool?) -> String {
        active?.summary ?? capability.subtitle
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
        if context.viewState.showsDoneButton {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionDone) { context.send(viewAction: .done) }
            }
        }
    }
}

// MARK: - Capability presentation

private extension AgentCapability {
    var title: String {
        switch self {
        case .translateMessages: return UntranslatedL10n.screenAgentCapabilitiesTranslateTitle
        case .liveCallTranslation: return UntranslatedL10n.screenAgentCapabilitiesLiveCallTitle
        case .callSummary: return UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle
        case .callRecording: return UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
        }
    }

    var subtitle: String {
        switch self {
        case .translateMessages: return UntranslatedL10n.screenAgentCapabilitiesTranslateSubtitle
        case .liveCallTranslation: return UntranslatedL10n.screenAgentCapabilitiesLiveCallSubtitle
        case .callSummary: return UntranslatedL10n.screenAgentCapabilitiesCallSummarySubtitle
        case .callRecording: return UntranslatedL10n.screenAgentCapabilitiesCallRecordingSubtitle
        }
    }

    // `icon` lives on the model (AgentCapabilitiesScreenModels) so the banner
    // and this sheet share one source of truth.
}

// MARK: - Previews

struct AgentCapabilitiesScreen_Previews: PreviewProvider, TestablePreview {
    static let loadingViewModel = makeViewModel(tools: nil)
    static let allOffViewModel = makeViewModel(tools: [])
    static let mixedViewModel = makeViewModel(tools: [
        RoomToolView(toolID: "t1", toolKind: "translate", triggerKind: "on_message",
                     targetLanguage: "English",
                     params: .translate(targetLanguage: "English"),
                     trigger: .onMessage(senderScope: .anyone), safeSliceSalt: "t1"),
        RoomToolView(toolID: "t2", toolKind: "call_summary", triggerKind: "on_voice_call",
                     targetLanguage: nil, params: .callSummary,
                     trigger: .onVoiceCall(speakerScope: .anyone), safeSliceSalt: "t2")
    ])
    static let errorViewModel = makeErrorViewModel()
    /// The owner DM: only the call tools can fire there (ADR-0088).
    static let ownerDMViewModel = makeViewModel(tools: [], availableToolKinds: ["call_summary", "call_recording"])
    /// A company agent (decision 168): no call tools, and an old armed one
    /// says it won't run.
    static let companyAgentViewModel = makeViewModel(tools: [
        RoomToolView(toolID: "t2", toolKind: "call_summary", triggerKind: "on_voice_call",
                     targetLanguage: nil, params: .callSummary,
                     trigger: .onVoiceCall(speakerScope: .anyone), safeSliceSalt: "t2")
    ], availableToolKinds: ["translate", "simplify", "correct", "rephrase", "summarize", "custom"])

    static var previews: some View {
        ElementNavigationStack {
            AgentCapabilitiesScreen(context: loadingViewModel.context)
        }
        .previewDisplayName("Loading")

        ElementNavigationStack {
            AgentCapabilitiesScreen(context: allOffViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(allOffViewModel))
        .previewDisplayName("All off")

        ElementNavigationStack {
            AgentCapabilitiesScreen(context: mixedViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(mixedViewModel))
        .previewDisplayName("Mixed")

        ElementNavigationStack {
            AgentCapabilitiesScreen(context: errorViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(errorViewModel))
        .previewDisplayName("Error")

        ElementNavigationStack {
            AgentCapabilitiesScreen(context: ownerDMViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(ownerDMViewModel))
        .previewDisplayName("Owner DM")

        ElementNavigationStack {
            AgentCapabilitiesScreen(context: companyAgentViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(companyAgentViewModel))
        .previewDisplayName("Company agent")
    }

    /// The loaded states wait for their fetch; until then their snapshots
    /// showed the loading skeleton.
    private static func hasLoaded(_ viewModel: AgentCapabilitiesScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } }
    }

    /// Every kind fires in a group room.
    private static let groupRoomToolKinds = ["translate", "simplify", "correct", "rephrase", "summarize", "custom",
                                             "live_translate", "call_summary", "call_recording"]

    /// Configures the mock so `.appeared` resolves into the wanted state
    /// (nil tools → stays loading; otherwise loads with those own-agent
    /// tools). Mirrors the upstream mock-driven preview idiom rather than
    /// mutating the read-only view state.
    private static func makeViewModel(tools: [RoomToolView]?,
                                      availableToolKinds: [String] = groupRoomToolKinds) -> AgentCapabilitiesScreenViewModel {
        let service = makeService(availableToolKinds: availableToolKinds)
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
        let viewModel = makeBaseViewModel(service: service)
        viewModel.context.send(viewAction: .appeared)
        return viewModel
    }

    private static func makeErrorViewModel() -> AgentCapabilitiesScreenViewModel {
        let service = makeService(availableToolKinds: groupRoomToolKinds)
        service.fetchRoomToolsRoomIDReturnValue = .failure(.serverError(status: 500))
        let viewModel = makeBaseViewModel(service: service)
        viewModel.context.send(viewAction: .appeared)
        return viewModel
    }

    /// The view model reads the catalog on every load, and an unconfigured
    /// mock method fatal-errors on a background task, killing the whole
    /// PreviewTests process — so every preview service gets one.
    private static func makeService(availableToolKinds: [String]) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                      roomID: "!room:example.com",
                                                                                      paramsSchema: [:],
                                                                                      triggerSchema: [:],
                                                                                      textTranslationLanguages: [],
                                                                                      voiceTranslationLanguages: [],
                                                                                      availableToolKinds: availableToolKinds))
        return service
    }

    private static func makeBaseViewModel(service: AgentPlatformServiceMock) -> AgentCapabilitiesScreenViewModel {
        AgentCapabilitiesScreenViewModel(roomID: "!room:example.com",
                                         agentID: "agent-1",
                                         agentDisplayName: "Aria",
                                         agentPlatformService: service)
    }
}
