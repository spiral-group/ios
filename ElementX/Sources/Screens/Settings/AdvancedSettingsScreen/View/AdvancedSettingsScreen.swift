//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (decision 187): «Privacy» — consent and visibility. The AI
// consent row comes first: decision 150's «Open Settings» lands here.
struct AdvancedSettingsScreen: View {
    @Bindable var context: AdvancedSettingsScreenViewModel.Context
    
    var body: some View {
        Form {
            Section {
                aiConsentRow
                
                // AGENT-PLATFORM (Brief 0072, ADR-0084): the toggle is the account's
                // presence privacy too — say what it hides, and that it is mutual.
                ListRow(label: .plain(title: L10n.screenAdvancedSettingsSharePresence,
                                      description: UntranslatedL10n.screenAdvancedSettingsSharePresenceAccountDescription),
                        kind: .toggle($context.sharePresence))
            }
            
            moderationAndSafetySection
            timelineMediaSection
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenSettingsPrivacyTitle) // AGENT-PLATFORM (decision 187)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // AGENT-PLATFORM (Brief 0078 phase 2): withdraw or give consent to third-party AI.
    @ViewBuilder
    private var aiConsentRow: some View {
        if let granted = context.viewState.aiConsentGranted {
            let binding = Binding(get: {
                granted
            }, set: { newValue in
                context.send(viewAction: .updateAIConsent(newValue))
            })
            
            ListRow(label: .plain(title: UntranslatedL10n.screenAdvancedSettingsAiConsentTitle,
                                  description: UntranslatedL10n.screenAdvancedSettingsAiConsentDescription),
                    details: context.viewState.isWaitingAIConsent ? .isWaiting(true) : nil,
                    kind: .toggle(binding))
                .disabled(context.viewState.isWaitingAIConsent)
                .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.aiConsent) // AGENT-PLATFORM (decision 148)
        } else if context.viewState.aiConsentLoadFailed {
            // AGENT-PLATFORM (decision 150): the read failed — say so and offer a retry, never hide the choice.
            ListRow(label: .plain(title: UntranslatedL10n.screenAdvancedSettingsAiConsentTitle,
                                  description: L10n.commonSomethingWentWrongMessage),
                    details: .title(L10n.actionRetry, isWaiting: context.viewState.isWaitingAIConsent),
                    kind: .button {
                        context.send(viewAction: .retryAIConsent)
                    })
                    .disabled(context.viewState.isWaitingAIConsent)
                    .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.aiConsentRetry)
        }
    }
    
    @ViewBuilder
    private var moderationAndSafetySection: some View {
        let binding = Binding(get: {
            context.viewState.hideInviteAvatars
        }, set: { newValue in
            context.send(viewAction: .updateHideInviteAvatars(newValue))
        })
        
        Section {
            ListRow(label: .plain(title: L10n.screenAdvancedSettingsHideInviteAvatarsToggleTitle),
                    details: context.viewState.isWaitingHideInviteAvatars ? .isWaiting(true) : nil,
                    kind: .toggle(binding))
                .disabled(context.viewState.isWaitingHideInviteAvatars)
            
            // AGENT-PLATFORM (decision 187): moved here from the main Settings screen.
            if context.viewState.showBlockedUsers {
                ListRow(label: .plain(title: L10n.commonBlockedUsers),
                        kind: .navigationLink {
                            context.send(viewAction: .blockedUsers)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.advancedSettingsScreen.blockedUsers)
            }
        } header: {
            Text(L10n.screenAdvancedSettingsModerationAndSafetySectionTitle)
                .compoundListSectionHeader()
        }
    }
    
    @ViewBuilder
    private var timelineMediaSection: some View {
        let binding = Binding(get: {
            context.viewState.timelineMediaVisibility
        }, set: { newValue in
            context.send(viewAction: .updateTimelineMediaVisibility(newValue))
        })
        
        Section {
            ListRow(label: .plain(title: L10n.screenAdvancedSettingsShowMediaTimelineTitle),
                    details: .isWaiting(context.viewState.isWaitingTimelineMediaVisibility),
                    kind: .inlinePicker(selection: binding,
                                        items: TimelineMediaVisibility.items))
                .disabled(context.viewState.isWaitingTimelineMediaVisibility)
        } header: {
            Text(L10n.screenAdvancedSettingsShowMediaTimelineTitle)
                .compoundListSectionHeader()
        } footer: {
            Text(L10n.screenAdvancedSettingsShowMediaTimelineSubtitle)
                .compoundListSectionFooter()
        }
    }
    
    // AGENT-PLATFORM (decision 188): the live-location slider is gone — location
    // sharing is off in Spiral. Appearance and media compression are in
    // AppearanceAndMediaSettingsScreen, View source in Developer options.
}

// MARK: - Previews

struct AdvancedSettingsScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel(aiConsent: .success(AIConsent(isGranted: true, currentVersion: "2026-10-10", decidedVersion: "2026-10-10")))
    static let loadFailedViewModel = makeViewModel(aiConsent: .failure(.serverError(status: 500))) // AGENT-PLATFORM (decision 150)
    
    static var previews: some View {
        ElementNavigationStack {
            AdvancedSettingsScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.aiConsentGranted).map { $0 != nil })
        .previewDisplayName("Default")
        
        ElementNavigationStack {
            AdvancedSettingsScreen(context: loadFailedViewModel.context)
        }
        .snapshotPreferences(expect: loadFailedViewModel.context.observe(\.viewState.aiConsentLoadFailed))
        .previewDisplayName("AI consent not loaded")
    }
    
    static func makeViewModel(aiConsent: Result<AIConsent, AgentPlatformError>) -> AdvancedSettingsScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.fetchAIConsentReturnValue = aiConsent
        return AdvancedSettingsScreenViewModel(advancedSettings: AppSettings.volatile(),
                                               clientProxy: ClientProxyMock(.init()),
                                               userIndicatorController: UserIndicatorControllerMock(),
                                               agentPlatformService: service)
    }
}

private extension TimelineMediaVisibility {
    static var items: [(title: String, tag: TimelineMediaVisibility)] {
        [(title: L10n.screenAdvancedSettingsShowMediaTimelineAlwaysHide, tag: .never),
         (title: L10n.screenAdvancedSettingsShowMediaTimelinePrivateRooms, tag: .privateOnly),
         (title: L10n.screenAdvancedSettingsShowMediaTimelineAlwaysShow, tag: .always)]
    }
}
