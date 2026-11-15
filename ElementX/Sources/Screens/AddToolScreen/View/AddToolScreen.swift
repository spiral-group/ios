//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

struct AddToolScreen: View {
    @Bindable var context: AddToolScreenViewModel.Context
    
    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                loadingSection
            case .loaded(let text, let calls):
                if text.isEmpty, calls.isEmpty {
                    nothingOfferedSection
                }
                kindsSection(text, header: L10n.commonText)
                kindsSection(calls, header: UntranslatedL10n.screenAgentUsageCategoryCalls)
            case .failed:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAddToolLoadFailed) { context.send(viewAction: .retry) }
            }
        }
        .spiralGroupedList()
        .navigationTitle(UntranslatedL10n.screenAgentCapabilitiesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolScreenTitle(title: UntranslatedL10n.screenAgentCapabilitiesTitle, subtitle: context.viewState.agentDisplayName)
            }
        }
    }
    
    // Decision 330: the kinds' rows as placeholders, after a short delay.
    private var loadingSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: AgentToolKind.allCases.count, leading: .icon)
                }
            })
        }
    }
    
    private var nothingOfferedSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenArmToolErrorDoesNotFireHere), kind: .label)
        }
    }
    
    @ViewBuilder
    private func kindsSection(_ kinds: [AgentToolKind], header: String) -> some View {
        if !kinds.isEmpty {
            Section {
                ForEach(kinds) { kind in
                    ListRow(label: .default(title: kind.title, description: kind.explanation, icon: kind.icon),
                            kind: .navigationLink {
                                context.send(viewAction: .selectKind(kind))
                            })
                            .accessibilityIdentifier(A11yIdentifiers.addToolScreen.kind(kind.rawValue))
                }
            } header: {
                Text(header)
                    .compoundListSectionHeader()
            }
        }
    }
}

// MARK: - Previews

struct AddToolScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let groupViewModel = makeViewModel(AgentToolKind.allCases.map(\.rawValue))
    /// The owner's chat with their assistant: only the call tools fire there (ADR-0088).
    static let ownerDMViewModel = makeViewModel(["call_summary", "call_recording"])
    static let failedViewModel = makeViewModel(nil)
    static let loadingViewModel = makeViewModel([], isLoading: true)
    
    static var previews: some View {
        ElementNavigationStack {
            AddToolScreen(context: groupViewModel.context)
        }
        .snapshotPreferences(expect: hasAnswered(groupViewModel))
        .previewDisplayName("Group chat")
        
        ElementNavigationStack {
            AddToolScreen(context: ownerDMViewModel.context)
        }
        .snapshotPreferences(expect: hasAnswered(ownerDMViewModel))
        .previewDisplayName("Owner's chat")
        
        ElementNavigationStack {
            AddToolScreen(context: failedViewModel.context)
        }
        .snapshotPreferences(expect: hasAnswered(failedViewModel))
        .previewDisplayName("Failed")
        
        ElementNavigationStack {
            AddToolScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")
    }
    
    private static func hasAnswered(_ viewModel: AddToolScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } }
    }
    
    private static func makeViewModel(_ kinds: [String]?, isLoading: Bool = false) -> AddToolScreenViewModel {
        let service = AgentPlatformServiceMock()
        if isLoading {
            // The snapshot suites share this view model in one run, which can outlast a minute.
            service.fetchToolsCatalogAgentIDRoomIDClosure = { _, _ in
                try? await Task.sleep(for: .seconds(24 * 3600))
                return .failure(.serverError(status: 0))
            }
        } else if let kinds {
            service.fetchToolsCatalogAgentIDRoomIDReturnValue = .success(ToolsCatalogView(agentID: "agent-1",
                                                                                          roomID: "!room:example.com",
                                                                                          paramsSchema: [:],
                                                                                          triggerSchema: [:],
                                                                                          textTranslationLanguages: [],
                                                                                          voiceTranslationLanguages: [],
                                                                                          availableToolKinds: kinds))
        } else {
            service.fetchToolsCatalogAgentIDRoomIDReturnValue = .failure(.serverError(status: 500))
        }
        return AddToolScreenViewModel(roomID: "!room:example.com", agentID: "agent-1", agentDisplayName: "Your assistant", store: AgentsStore(service: service))
    }
}
